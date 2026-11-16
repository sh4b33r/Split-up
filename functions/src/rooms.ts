import { randomBytes, randomInt } from 'crypto';
import { Transaction } from 'firebase-admin/firestore';
import { CODE_ALPHABET, CODE_LENGTH, CURRENCIES } from './config';
import { notify } from './notify';
import { announcePendingInvites } from './invites';
import {
  bad, callable, db, denied, FieldValue, HttpsError, id, isManager, loadRoomFor,
  logActivity, memberRef, notFound, precondition, Room, roomRef, str, toRoom,
} from './util';

const CODE_RE = new RegExp(`^[${CODE_ALPHABET}]{${CODE_LENGTH}}$`);

function newCode(): string {
  let out = '';
  for (let i = 0; i < CODE_LENGTH; i++) out += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return out;
}
/** 128-bit random invite token. */
function newToken(): string {
  return randomBytes(16).toString('base64url');
}

/** The caller's public profile, as copied into each room's member doc. */
export async function profileOf(uid: string): Promise<{ displayName: string; photoUrl: string | null }> {
  const snap = await db.collection('users').doc(uid).get();
  const d = snap.data() ?? {};
  return { displayName: (d.name as string) || 'Someone', photoUrl: (d.photoUrl as string) || null };
}

// ---- create ----------------------------------------------------------------

export const createRoom = callable(async (uid, data) => {
  const name = str(data.name, 'Room name', 40);
  const currency = typeof data.currency === 'string' ? data.currency : 'QAR';
  if (!(currency in CURRENCIES)) bad('That currency is not supported.');
  const icon = str(data.icon ?? '🏠', 'Icon', 16);
  const profile = await profileOf(uid);

  // The code must be unique: create() fails if roomCodes/{code} exists, and we retry.
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = newCode();
    const token = newToken();
    const room = db.collection('rooms').doc();
    const batch = db.batch();
    batch.create(db.collection('roomCodes').doc(code), { roomId: room.id });
    batch.create(db.collection('inviteTokens').doc(token), { roomId: room.id });
    batch.create(room, {
      name, icon, currency, code,
      inviteToken: token,
      ownerId: uid,
      adminIds: [],
      memberIds: [uid],
      requireApproval: false,
      createdAt: FieldValue.serverTimestamp(),
    });
    batch.create(memberRef(room.id, uid), {
      uid,
      role: 'owner',
      displayName: profile.displayName,
      photoUrl: profile.photoUrl,
      status: 'active',
      netMinor: 0,
      joinedAt: FieldValue.serverTimestamp(),
    });
    logActivity(batch, room.id, { type: 'room_created', actorId: uid, actorName: profile.displayName });
    try {
      await batch.commit();
      return { roomId: room.id, code };
    } catch (e: any) {
      if (e?.code === 6 /* ALREADY_EXISTS */) continue;
      throw e;
    }
  }
  throw new HttpsError('unavailable', 'Could not create a room code. Please try again.');
});

// ---- join ------------------------------------------------------------------

/** Limits code and token guesses: 20 lookups per 10 minutes per user. */
async function rateLimitLookups(uid: string): Promise<void> {
  const ref = db.collection('rateLimits').doc(uid);
  const WINDOW_MS = 10 * 60 * 1000;
  const MAX = 20;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();
    const d = snap.data();
    if (!d || now - d.windowStart > WINDOW_MS) {
      tx.set(ref, { windowStart: now, count: 1 });
    } else if (d.count >= MAX) {
      throw new HttpsError('resource-exhausted', 'Too many attempts. Please wait a few minutes.');
    } else {
      tx.update(ref, { count: d.count + 1 });
    }
  });
}

/** Finds the room for a typed room code or an invite-link token. */
async function resolveRoomId(codeOrToken: unknown): Promise<{ roomId: string; via: 'code' | 'link' }> {
  if (typeof codeOrToken !== 'string') bad('Enter a room code.');
  const raw = (codeOrToken as string).trim();
  const asCode = raw.toUpperCase().replace(/[\s-]/g, '');
  if (CODE_RE.test(asCode)) {
    const snap = await db.collection('roomCodes').doc(asCode).get();
    if (snap.exists) return { roomId: snap.data()!.roomId, via: 'code' };
  }
  if (/^[A-Za-z0-9_-]{16,64}$/.test(raw)) {
    const snap = await db.collection('inviteTokens').doc(raw).get();
    if (snap.exists) return { roomId: snap.data()!.roomId, via: 'link' };
  }
  return notFound('No room matches that code or link. It may have been reset.');
}

/** What the join screen shows before the user taps Join. */
export const previewRoom = callable(async (uid, data) => {
  await rateLimitLookups(uid);
  const { roomId } = await resolveRoomId(data.codeOrToken);
  const room = toRoom(await roomRef(roomId).get());
  const [owner, request] = await Promise.all([
    memberRef(roomId, room.ownerId).get(),
    roomRef(roomId).collection('joinRequests').doc(uid).get(),
  ]);
  return {
    roomId,
    name: room.name,
    icon: room.icon,
    currency: room.currency,
    ownerName: owner.data()?.displayName ?? 'Someone',
    memberCount: room.memberIds.length,
    requireApproval: room.requireApproval,
    alreadyMember: room.memberIds.includes(uid),
    requested: request.exists,
  };
});

/** Adds `uid` to the room inside a transaction. All reads must already be done. */
function addMember(
  tx: Transaction,
  room: Room,
  uid: string,
  profile: { displayName: string; photoUrl: string | null },
  existing: FirebaseFirestore.DocumentSnapshot,
): void {
  tx.update(roomRef(room.id), { memberIds: FieldValue.arrayUnion(uid) });
  tx.set(memberRef(room.id, uid), {
    uid,
    role: 'member',
    displayName: profile.displayName,
    photoUrl: profile.photoUrl,
    status: 'active',
    // Someone who rejoins keeps the balance they left with.
    netMinor: existing.exists ? existing.data()!.netMinor ?? 0 : 0,
    joinedAt: FieldValue.serverTimestamp(),
  });
  tx.delete(roomRef(room.id).collection('joinRequests').doc(uid));
  logActivity(tx, room.id, { type: 'member_joined', actorId: uid, actorName: profile.displayName });
}

export const joinRoom = callable(async (uid, data) => {
  await rateLimitLookups(uid);
  const { roomId, via } = await resolveRoomId(data.codeOrToken);
  const profile = await profileOf(uid);

  const result = await db.runTransaction(async (tx) => {
    const room = toRoom(await tx.get(roomRef(roomId)));
    if (room.memberIds.includes(uid)) return { status: 'already', room };
    if (room.memberIds.length >= 50) precondition('This room is full.');
    const existing = await tx.get(memberRef(roomId, uid));
    if (room.requireApproval) {
      tx.set(roomRef(roomId).collection('joinRequests').doc(uid), {
        uid,
        displayName: profile.displayName,
        photoUrl: profile.photoUrl,
        via,
        requestedAt: FieldValue.serverTimestamp(),
      });
      return { status: 'requested', room };
    }
    addMember(tx, room, uid, profile, existing);
    return { status: 'joined', room };
  });

  const { room, status } = result;
  if (status === 'requested') {
    await notify([room.ownerId, ...room.adminIds], {
      type: 'join_request',
      title: room.name,
      body: `${profile.displayName} wants to join "${room.name}"`,
      roomId,
    });
  } else if (status === 'joined') {
    await notify([room.ownerId], {
      type: 'member_joined',
      title: room.name,
      body: `${profile.displayName} joined "${room.name}"`,
      roomId,
    });
  }
  return { roomId, status };
});

export const respondJoinRequest = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const target = id(data.uid, 'Member');
  const approve = data.approve === true;
  const profile = await profileOf(target);

  const room = await db.runTransaction(async (tx) => {
    const r = await loadRoomFor(uid, roomId, tx);
    if (!isManager(r, uid)) denied('Only the room owner can answer join requests.');
    const reqRef = roomRef(roomId).collection('joinRequests').doc(target);
    const [request, existing] = await Promise.all([tx.get(reqRef), tx.get(memberRef(roomId, target))]);
    if (!request.exists) precondition('That request has already been answered.');
    if (approve && !r.memberIds.includes(target)) addMember(tx, r, target, profile, existing);
    else tx.delete(reqRef);
    return r;
  });

  await notify([target], {
    type: approve ? 'join_approved' : 'join_declined',
    title: room.name,
    body: approve
      ? `You're in! Your request to join "${room.name}" was approved`
      : `Your request to join "${room.name}" was declined`,
    roomId: approve ? roomId : null,
  });
  return { ok: true };
});

/** Adds an invited user straight into the room (used when an email invite is accepted). */
export async function joinDirect(roomId: string, uid: string): Promise<Room> {
  const profile = await profileOf(uid);
  return db.runTransaction(async (tx) => {
    const room = toRoom(await tx.get(roomRef(roomId)));
    if (room.memberIds.includes(uid)) return room;
    const existing = await tx.get(memberRef(roomId, uid));
    addMember(tx, room, uid, profile, existing);
    return room;
  });
}

// ---- manage ----------------------------------------------------------------

export const updateRoom = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const room = await loadRoomFor(uid, roomId);
  if (!isManager(room, uid)) denied('Only the room owner can change room settings.');
  const patch: Record<string, unknown> = {};
  if (data.name !== undefined) patch.name = str(data.name, 'Room name', 40);
  if (data.icon !== undefined) patch.icon = str(data.icon, 'Icon', 16);
  if (data.requireApproval !== undefined) patch.requireApproval = data.requireApproval === true;
  if (Object.keys(patch).length === 0) return { ok: true };
  const batch = db.batch();
  batch.update(roomRef(roomId), patch);
  const me = await memberRef(roomId, uid).get();
  logActivity(batch, roomId, {
    type: 'room_updated',
    actorId: uid,
    actorName: me.data()?.displayName ?? 'Someone',
    detail: patch.name ? `Renamed to "${patch.name}"` : null,
  });
  await batch.commit();
  return { ok: true };
});

/** New code and link; the old ones stop working. */
export const resetInvite = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const room = await loadRoomFor(uid, roomId);
  if (!isManager(room, uid)) denied('Only the room owner can reset the code.');
  for (let attempt = 0; attempt < 6; attempt++) {
    const code = newCode();
    const token = newToken();
    const batch = db.batch();
    batch.create(db.collection('roomCodes').doc(code), { roomId });
    batch.create(db.collection('inviteTokens').doc(token), { roomId });
    batch.delete(db.collection('roomCodes').doc(room.code));
    batch.delete(db.collection('inviteTokens').doc(room.inviteToken));
    batch.update(roomRef(roomId), { code, inviteToken: token });
    try {
      await batch.commit();
      return { code, inviteToken: token };
    } catch (e: any) {
      if (e?.code === 6) continue;
      throw e;
    }
  }
  throw new HttpsError('unavailable', 'Could not create a new code. Please try again.');
});

/** Throws if `target` still owes, or is still owed, money on an open split. */
async function assertSettled(roomId: string, target: string, who: 'you' | 'they'): Promise<void> {
  const open = await roomRef(roomId).collection('splits').where('status', '==', 'open').get();
  for (const doc of open.docs) {
    const s = doc.data();
    const mine = s.shareSummary?.[target];
    if (mine && mine.status !== 'paid') {
      precondition(
        who === 'you'
          ? `You still have an unpaid share on "${s.title}". Settle it before leaving.`
          : `They still have an unpaid share on "${s.title}". Mark it paid or delete the split first.`,
      );
    }
    if (s.paidBy === target) {
      precondition(
        who === 'you'
          ? `Others still owe you for "${s.title}". Settle it before leaving.`
          : `Others still owe them for "${s.title}". Settle it first.`,
      );
    }
  }
}

/** Tells rule creators to re-check monthly bills that included a departed member. */
async function flagRules(room: Room, target: string, targetName: string): Promise<void> {
  const rules = await roomRef(room.id).collection('recurringRules').where('active', '==', true).get();
  for (const doc of rules.docs) {
    const r = doc.data();
    const involved = r.paidBy === target || (r.participants as any[]).some((p) => p.uid === target);
    if (!involved) continue;
    await notify([r.createdBy], {
      type: 'rule_check',
      title: room.name,
      body: `${targetName} left "${room.name}". Please re-check the monthly bill "${r.title}"`,
      roomId: room.id,
    });
  }
}

async function detach(room: Room, target: string, status: 'left' | 'removed', actor: string) {
  const names = await db.getAll(memberRef(room.id, target), memberRef(room.id, actor));
  const targetName = names[0].data()?.displayName ?? 'Someone';
  const actorName = names[1].data()?.displayName ?? 'Someone';
  const batch = db.batch();
  batch.update(roomRef(room.id), {
    memberIds: FieldValue.arrayRemove(target),
    adminIds: FieldValue.arrayRemove(target),
  });
  batch.update(memberRef(room.id, target), { status, role: 'member' });
  logActivity(batch, room.id, {
    type: status === 'left' ? 'member_left' : 'member_removed',
    actorId: actor,
    actorName,
    targetUserId: target,
    targetName,
  });
  await batch.commit();
  await flagRules(room, target, targetName);
  return { targetName, actorName };
}

export const removeMember = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const target = id(data.uid, 'Member');
  const room = await loadRoomFor(uid, roomId);
  if (!isManager(room, uid)) denied('Only the room owner can remove members.');
  if (target === room.ownerId) denied('The owner cannot be removed.');
  if (target === uid) bad('Use Leave room to remove yourself.');
  if (room.adminIds.includes(target) && uid !== room.ownerId) denied('Only the owner can remove an admin.');
  if (!room.memberIds.includes(target)) precondition('They are no longer in this room.');
  await assertSettled(roomId, target, 'they');
  const { actorName } = await detach(room, target, 'removed', uid);
  await notify([target], {
    type: 'removed',
    title: room.name,
    body: `${actorName} removed you from "${room.name}"`,
  });
  return { ok: true };
});

export const leaveRoom = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const room = await loadRoomFor(uid, roomId);
  if (room.ownerId === uid) {
    precondition('Transfer ownership to another member before leaving.');
  }
  await assertSettled(roomId, uid, 'you');
  await detach(room, uid, 'left', uid);
  return { ok: true };
});

export const transferOwnership = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const target = id(data.uid, 'Member');
  const room = await loadRoomFor(uid, roomId);
  if (room.ownerId !== uid) denied('Only the owner can transfer ownership.');
  if (target === uid) bad('You already own this room.');
  if (!room.memberIds.includes(target)) precondition('They are no longer in this room.');
  const names = await db.getAll(memberRef(roomId, uid), memberRef(roomId, target));
  const batch = db.batch();
  batch.update(roomRef(roomId), {
    ownerId: target,
    adminIds: [...room.adminIds.filter((a) => a !== target), uid],
  });
  batch.update(memberRef(roomId, target), { role: 'owner' });
  batch.update(memberRef(roomId, uid), { role: 'admin' });
  logActivity(batch, roomId, {
    type: 'owner_changed',
    actorId: uid,
    actorName: names[0].data()?.displayName ?? 'Someone',
    targetUserId: target,
    targetName: names[1].data()?.displayName ?? 'Someone',
  });
  await batch.commit();
  await notify([target], {
    type: 'owner_changed',
    title: room.name,
    body: `You are now the owner of "${room.name}"`,
    roomId,
  });
  return { ok: true };
});

export const setRole = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const target = id(data.uid, 'Member');
  const role = data.role;
  if (role !== 'admin' && role !== 'member') bad('Role is invalid.');
  const room = await loadRoomFor(uid, roomId);
  if (room.ownerId !== uid) denied('Only the owner can change roles.');
  if (target === room.ownerId) bad('The owner is always the owner.');
  if (!room.memberIds.includes(target)) precondition('They are no longer in this room.');
  const batch = db.batch();
  batch.update(roomRef(roomId), {
    adminIds: role === 'admin' ? FieldValue.arrayUnion(target) : FieldValue.arrayRemove(target),
  });
  batch.update(memberRef(roomId, target), { role });
  await batch.commit();
  return { ok: true };
});

// ---- profile ---------------------------------------------------------------

/** Saves the caller's profile and refreshes their public copy in every room. */
export const updateProfile = callable(async (uid, data, req) => {
  const name = str(data.name, 'Name', 40);
  const phone = data.phone ? str(data.phone, 'Phone', 24, 0) : '';
  const photoUrl =
    typeof data.photoUrl === 'string' && data.photoUrl.length <= 1000 && data.photoUrl.startsWith('http')
      ? data.photoUrl
      : null;
  const email = (req.auth?.token.email as string | undefined)?.toLowerCase() ?? null;

  const userRef = db.collection('users').doc(uid);
  const [existing, rooms] = await Promise.all([
    userRef.get(),
    db.collection('rooms').where('memberIds', 'array-contains', uid).get(),
  ]);
  const firstTime = !existing.data()?.name;
  const batch = db.batch();
  batch.set(
    userRef,
    {
      name, phone, photoUrl,
      emailLower: email,
      updatedAt: FieldValue.serverTimestamp(),
      ...(existing.data()?.createdAt ? {} : { createdAt: FieldValue.serverTimestamp() }),
    },
    { merge: true },
  );
  for (const room of rooms.docs) {
    batch.update(memberRef(room.id, uid), { displayName: name, photoUrl });
  }
  await batch.commit();
  // A brand-new account: show the invites that were waiting for this email.
  if (firstTime) await announcePendingInvites(uid, email);
  return { ok: true };
});
