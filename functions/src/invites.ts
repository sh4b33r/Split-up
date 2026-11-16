import { createHash } from 'crypto';
import { getAuth } from 'firebase-admin/auth';
import { APP_NAME, inviteHost } from './config';
import { notify } from './notify';
import { joinDirect } from './rooms';
import {
  bad, callable, db, denied, FieldValue, id, isManager, loadRoomFor, memberRef,
  notFound, precondition, roomRef, toRoom,
} from './util';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function inviteId(roomId: string, emailLower: string): string {
  return `${roomId}_${createHash('sha256').update(emailLower).digest('hex').slice(0, 24)}`;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

/**
 * Invites an email address to a room. Someone who already has an account gets
 * a push and an in-app invite card. Anyone else gets an email, and the invite
 * waits in `invites` until they sign up with that address.
 */
export const inviteByEmail = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const email = typeof data.email === 'string' ? data.email.trim().toLowerCase() : '';
  if (!EMAIL_RE.test(email) || email.length > 200) bad('Enter a valid email address.');
  const room = await loadRoomFor(uid, roomId);
  if (!isManager(room, uid)) denied('Only the room owner can invite people.');

  let invitee: string | null = null;
  try {
    invitee = (await getAuth().getUserByEmail(email)).uid;
  } catch {
    invitee = null; // no account yet
  }
  if (invitee && room.memberIds.includes(invitee)) precondition('They are already in this room.');

  const inviter = (await memberRef(roomId, uid).get()).data()?.displayName ?? 'Someone';
  const ref = db.collection('invites').doc(inviteId(roomId, email));
  await ref.set({
    roomId,
    roomName: room.name,
    roomIcon: room.icon,
    emailLower: email,
    invitedBy: uid,
    invitedByName: inviter,
    status: 'pending',
    createdAt: FieldValue.serverTimestamp(),
  });

  if (invitee) {
    await notify([invitee], {
      type: 'invite',
      title: 'Room invite',
      body: `${inviter} invited you to "${room.name}"`,
      inviteId: ref.id,
    });
    return { ok: true, registered: true };
  }

  // Picked up by the Firebase "Trigger Email" extension, if it is installed.
  const link = `https://${inviteHost()}/j/${room.inviteToken}`;
  await db.collection('mail').add({
    to: [email],
    message: {
      subject: `${inviter} invited you to "${room.name}" on ${APP_NAME}`,
      text:
        `${inviter} invited you to share bills in "${room.name}" on ${APP_NAME}.\n\n` +
        `Open this link to join: ${link}\n\n` +
        `Or sign up with this email address and the invite will be waiting for you. ` +
        `You can also join with the room code ${room.code}.`,
      html:
        `<p><strong>${escapeHtml(inviter)}</strong> invited you to share bills in ` +
        `<strong>${escapeHtml(room.name)}</strong> on ${APP_NAME}.</p>` +
        `<p><a href="${link}">Join the room</a></p>` +
        `<p>Or sign up with this email address and the invite will be waiting for you. ` +
        `You can also join with the room code <strong>${room.code}</strong>.</p>`,
    },
  });
  return { ok: true, registered: false };
});

/** The invitee accepts or declines an email invite. */
export const respondInvite = callable(async (uid, data, req) => {
  const ref = db.collection('invites').doc(id(data.inviteId, 'Invite'));
  const accept = data.accept === true;
  const email = (req.auth?.token.email as string | undefined)?.toLowerCase();
  const snap = await ref.get();
  if (!snap.exists) notFound('That invite no longer exists.');
  const invite = snap.data()!;
  if (!email || invite.emailLower !== email) denied('That invite is for a different email address.');
  if (req.auth?.token.email_verified !== true) {
    precondition('Verify your email address before answering invites.');
  }
  if (invite.status !== 'pending') precondition('That invite has already been answered.');

  if (!accept) {
    await ref.update({ status: 'declined', respondedAt: FieldValue.serverTimestamp() });
    return { ok: true };
  }
  const roomSnap = await roomRef(invite.roomId).get();
  if (!roomSnap.exists) {
    await ref.update({ status: 'expired' });
    notFound('That room no longer exists.');
  }
  const room = await joinDirect(invite.roomId, uid);
  await ref.update({ status: 'accepted', respondedAt: FieldValue.serverTimestamp() });
  const name = (await memberRef(room.id, uid).get()).data()?.displayName ?? 'Someone';
  await notify([invite.invitedBy], {
    type: 'member_joined',
    title: room.name,
    body: `${name} accepted your invite to "${room.name}"`,
    roomId: room.id,
  });
  return { ok: true, roomId: room.id };
});

/** The owner withdraws a pending invite. */
export const cancelInvite = callable(async (uid, data) => {
  const ref = db.collection('invites').doc(id(data.inviteId, 'Invite'));
  const snap = await ref.get();
  if (!snap.exists) return { ok: true };
  const room = toRoom(await roomRef(snap.data()!.roomId).get());
  if (!isManager(room, uid)) denied('Only the room owner can cancel invites.');
  await ref.delete();
  return { ok: true };
});

/**
 * Called the first time a profile is saved: surfaces any invites that were
 * waiting for this email address in the new user's inbox.
 */
export async function announcePendingInvites(uid: string, emailLower: string | null): Promise<number> {
  if (!emailLower) return 0;
  const pending = await db
    .collection('invites')
    .where('emailLower', '==', emailLower)
    .where('status', '==', 'pending')
    .get();
  for (const doc of pending.docs) {
    const inv = doc.data();
    await notify([uid], {
      type: 'invite',
      title: 'Room invite',
      body: `${inv.invitedByName} invited you to "${inv.roomName}"`,
      inviteId: doc.id,
    });
  }
  return pending.size;
}
