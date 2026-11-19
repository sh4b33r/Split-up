import { notify } from './notify';
import {
  callable, db, denied, FieldValue, id, isManager, loadRoomFor, memberNames, notFound, splitLabel,
  splitRef, str,
} from './util';

/** A comment on a split. Everyone on the split (and whoever paid) is notified. */
export const addComment = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const text = str(data.text, 'Comment', 500);
  const room = await loadRoomFor(uid, roomId);
  const split = await splitRef(roomId, splitId).get();
  if (!split.exists) notFound('That split no longer exists.');
  const s = split.data()!;
  const names = await memberNames(roomId, [uid]);
  const ref = splitRef(roomId, splitId).collection('comments').doc();
  await ref.set({ authorId: uid, authorName: names[uid], text, createdAt: FieldValue.serverTimestamp() });
  await db.doc(`rooms/${roomId}/splits/${splitId}`).update({ commentCount: FieldValue.increment(1) });

  const preview = text.length > 80 ? `${text.slice(0, 77)}…` : text;
  await notify([...(s.participantIds as string[]), s.paidBy].filter((u) => u !== uid), {
    type: 'comment',
    title: `${names[uid]} on ${splitLabel(s.title, s.periodKey)}`,
    body: preview,
    roomId: room.id,
    splitId,
  });
  return { id: ref.id };
});

export const deleteComment = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const ref = splitRef(roomId, splitId).collection('comments').doc(id(data.commentId, 'Comment'));
  const room = await loadRoomFor(uid, roomId);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true };
  if (snap.data()!.authorId !== uid && !isManager(room, uid)) denied('You can only delete your own comments.');
  await ref.delete();
  await splitRef(roomId, splitId).update({ commentCount: FieldValue.increment(-1) });
  return { ok: true };
});
