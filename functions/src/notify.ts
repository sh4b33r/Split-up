import { getMessaging } from 'firebase-admin/messaging';
import * as logger from 'firebase-functions/logger';
import { db, FieldValue } from './util';

export interface Notice {
  type: string;
  title: string;
  body: string;
  roomId?: string | null;
  splitId?: string | null;
  inviteId?: string | null;
}

const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/**
 * Writes the notice to each user's in-app inbox and sends the same thing as a
 * push to every device token they have. Never throws: a failed notification
 * must not fail the action that caused it.
 */
export async function notify(uids: string[], notice: Notice): Promise<void> {
  const targets = [...new Set(uids)].filter(Boolean);
  if (targets.length === 0) return;
  try {
    const batch = db.batch();
    for (const uid of targets) {
      batch.set(db.collection('users').doc(uid).collection('notifications').doc(), {
        type: notice.type,
        title: notice.title,
        body: notice.body,
        roomId: notice.roomId ?? null,
        splitId: notice.splitId ?? null,
        inviteId: notice.inviteId ?? null,
        read: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  } catch (e) {
    logger.error('notify: inbox write failed', e);
  }

  // The emulator has no FCM, so the inbox is the whole notification there.
  if (process.env.FUNCTIONS_EMULATOR === 'true') return;

  try {
    const users = await db.getAll(...targets.map((u) => db.collection('users').doc(u)));
    const owners: { uid: string; token: string }[] = [];
    for (const u of users) {
      for (const token of (u.data()?.fcmTokens as string[] | undefined) ?? []) {
        owners.push({ uid: u.id, token });
      }
    }
    if (owners.length === 0) return;

    const data: Record<string, string> = { type: notice.type };
    if (notice.roomId) data.roomId = notice.roomId;
    if (notice.splitId) data.splitId = notice.splitId;
    if (notice.inviteId) data.inviteId = notice.inviteId;

    for (let i = 0; i < owners.length; i += 500) {
      const chunk = owners.slice(i, i + 500);
      const res = await getMessaging().sendEachForMulticast({
        tokens: chunk.map((o) => o.token),
        notification: { title: notice.title, body: notice.body },
        data,
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default' } } },
      });
      const cleanup = db.batch();
      let dead = 0;
      res.responses.forEach((r, j) => {
        if (!r.success && r.error && DEAD_TOKEN_CODES.has(r.error.code)) {
          cleanup.update(db.collection('users').doc(chunk[j].uid), {
            fcmTokens: FieldValue.arrayRemove(chunk[j].token),
          });
          dead++;
        }
      });
      if (dead > 0) await cleanup.commit();
    }
  } catch (e) {
    logger.error('notify: push failed', e);
  }
}
