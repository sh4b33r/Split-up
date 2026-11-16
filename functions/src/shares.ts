import { FieldPath, Transaction } from 'firebase-admin/firestore';
import { PAYMENT_METHODS } from './config';
import { notify } from './notify';
import {
  bad, callable, db, denied, FieldValue, id, isManager, loadRoomFor, logActivity,
  memberNames, memberRef, money, notFound, optStr, precondition, Room, splitLabel,
  splitRef, str,
} from './util';

// A share is always in one of three states:
//
//   unpaid ──(I've paid)──▶ marked_paid ──(confirm)──▶ paid
//     ▲                         │                        │
//     └────────(reject)─────────┘                        │
//     ├────────────────(mark paid directly)─────────────▶│
//     └────────────────────(undo)────────────────────────┘
//
// Every transition runs in a transaction that re-reads the current status, so
// two people acting at once cannot both succeed.

interface Ctx {
  room: Room;
  split: FirebaseFirestore.DocumentData;
  share: FirebaseFirestore.DocumentData;
  shareRef: FirebaseFirestore.DocumentReference;
  label: string;
}

async function load(tx: Transaction, uid: string, roomId: string, splitId: string, target: string): Promise<Ctx> {
  const room = await loadRoomFor(uid, roomId, tx);
  const sRef = splitRef(roomId, splitId);
  const shareRef = sRef.collection('shares').doc(target);
  const [split, share] = await Promise.all([tx.get(sRef), tx.get(shareRef)]);
  if (!split.exists || !share.exists) notFound('That share no longer exists.');
  return {
    room,
    split: split.data()!,
    share: share.data()!,
    shareRef,
    label: splitLabel(split.data()!.title, split.data()!.periodKey),
  };
}

/** Owner, admin, split creator or payer. */
function canSettle(c: Ctx, uid: string): boolean {
  return isManager(c.room, uid) || c.split.createdBy === uid || c.split.paidBy === uid;
}

/** Updates the share's status on the split and returns whether the split is now settled. */
function setSummary(tx: Transaction, c: Ctx, roomId: string, splitId: string, target: string, status: string): boolean {
  const summary = { ...(c.split.shareSummary ?? {}) };
  summary[target] = { ...summary[target], status };
  const settled = Object.values(summary).every((s: any) => s.status === 'paid');
  tx.update(
    splitRef(roomId, splitId),
    new FieldPath('shareSummary', target, 'status'), status,
    'status', settled ? 'settled' : 'open',
    'updatedAt', FieldValue.serverTimestamp(),
  );
  return settled;
}

/** Moves the amount out of (paid) or back into (unpaid) both members' balances. */
function applyBalance(tx: Transaction, c: Ctx, roomId: string, target: string, paid: boolean) {
  const amount = c.share.amountMinor as number;
  tx.update(memberRef(roomId, target), { netMinor: FieldValue.increment(paid ? amount : -amount) });
  tx.update(memberRef(roomId, c.split.paidBy), { netMinor: FieldValue.increment(paid ? -amount : amount) });
}

async function notifySettled(c: Ctx, roomId: string, splitId: string) {
  await notify([c.split.paidBy], {
    type: 'split_settled',
    title: c.room.name,
    body: `Everyone has paid for ${c.label}`,
    roomId,
    splitId,
  });
}

/** A member taps "I've paid" on their own share. */
export const markPaid = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const method = data.method;
  if (!PAYMENT_METHODS.includes(method)) bad('Pick how you paid.');
  const note = optStr(data.note, 'Note', 300);
  const proofUrl = optStr(data.proofUrl, 'Proof', 1000);
  if (proofUrl && !proofUrl.startsWith('http')) bad('Proof is invalid.');
  const names = await memberNames(roomId, [uid]);

  const c = await db.runTransaction(async (tx) => {
    const ctx = await load(tx, uid, roomId, splitId, uid);
    if (ctx.share.status === 'paid') precondition('This share is already paid.');
    if (ctx.share.status === 'marked_paid') precondition('You already marked this as paid.');
    tx.update(ctx.shareRef, {
      status: 'marked_paid',
      method,
      note,
      proofUrl,
      markedAt: FieldValue.serverTimestamp(),
      rejectReason: null,
    });
    setSummary(tx, ctx, roomId, splitId, uid, 'marked_paid');
    logActivity(tx, roomId, {
      type: 'share_marked',
      actorId: uid,
      actorName: names[uid],
      splitId,
      splitTitle: ctx.label,
      amountMinor: ctx.share.amountMinor,
    });
    return ctx;
  });

  await notify([c.split.paidBy], {
    type: 'share_marked',
    title: c.label,
    body: `${names[uid]} marked ${money(c.share.amountMinor, c.room.currency)} as paid. Confirm?`,
    roomId,
    splitId,
  });
  return { ok: true };
});

/** The payer (or split creator / owner) confirms a Marked paid share. */
export const confirmShare = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const target = id(data.uid, 'Member');
  const names = await memberNames(roomId, [uid, target]);

  const { c, settled } = await db.runTransaction(async (tx) => {
    const ctx = await load(tx, uid, roomId, splitId, target);
    if (!canSettle(ctx, uid)) denied('Only whoever paid the bill can confirm payments.');
    if (ctx.share.status === 'paid') precondition('This share is already paid.');
    if (ctx.share.status !== 'marked_paid') precondition('This share has not been marked as paid.');
    tx.update(ctx.shareRef, {
      status: 'paid',
      confirmedBy: uid,
      confirmedAt: FieldValue.serverTimestamp(),
    });
    applyBalance(tx, ctx, roomId, target, true);
    const done = setSummary(tx, ctx, roomId, splitId, target, 'paid');
    logActivity(tx, roomId, {
      type: 'share_confirmed',
      actorId: uid,
      actorName: names[uid],
      splitId,
      splitTitle: ctx.label,
      targetUserId: target,
      targetName: names[target],
      amountMinor: ctx.share.amountMinor,
    });
    return { c: ctx, settled: done };
  });

  if (target !== uid) {
    await notify([target], {
      type: 'share_confirmed',
      title: c.label,
      body: `${names[uid]} confirmed your payment of ${money(c.share.amountMinor, c.room.currency)}`,
      roomId,
      splitId,
    });
  }
  if (settled) await notifySettled(c, roomId, splitId);
  return { ok: true, settled };
});

/** The payer rejects a Marked paid share with a reason; it goes back to Unpaid. */
export const rejectShare = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const target = id(data.uid, 'Member');
  const reason = str(data.reason, 'Reason', 200);
  const names = await memberNames(roomId, [uid, target]);

  const c = await db.runTransaction(async (tx) => {
    const ctx = await load(tx, uid, roomId, splitId, target);
    if (!canSettle(ctx, uid)) denied('Only whoever paid the bill can reject payments.');
    if (ctx.share.status !== 'marked_paid') precondition('This share is not waiting for confirmation.');
    tx.update(ctx.shareRef, { status: 'unpaid', rejectReason: reason, markedAt: null });
    setSummary(tx, ctx, roomId, splitId, target, 'unpaid');
    logActivity(tx, roomId, {
      type: 'share_rejected',
      actorId: uid,
      actorName: names[uid],
      splitId,
      splitTitle: ctx.label,
      targetUserId: target,
      targetName: names[target],
      amountMinor: ctx.share.amountMinor,
      detail: reason,
    });
    return ctx;
  });

  await notify([target], {
    type: 'share_rejected',
    title: c.label,
    body: `${names[uid]} rejected your payment: "${reason}"`,
    roomId,
    splitId,
  });
  return { ok: true };
});

/** Marks any share Paid straight away, for cash handed over in person. */
export const markPaidDirect = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const target = id(data.uid, 'Member');
  const names = await memberNames(roomId, [uid, target]);

  const { c, settled } = await db.runTransaction(async (tx) => {
    const ctx = await load(tx, uid, roomId, splitId, target);
    if (!canSettle(ctx, uid)) denied('Only whoever paid the bill can mark shares as paid.');
    if (ctx.share.status === 'paid') precondition('This share is already paid.');
    tx.update(ctx.shareRef, {
      status: 'paid',
      method: ctx.share.method ?? 'cash',
      confirmedBy: uid,
      confirmedAt: FieldValue.serverTimestamp(),
      rejectReason: null,
    });
    applyBalance(tx, ctx, roomId, target, true);
    const done = setSummary(tx, ctx, roomId, splitId, target, 'paid');
    logActivity(tx, roomId, {
      type: 'share_paid_direct',
      actorId: uid,
      actorName: names[uid],
      splitId,
      splitTitle: ctx.label,
      targetUserId: target,
      targetName: names[target],
      amountMinor: ctx.share.amountMinor,
    });
    return { c: ctx, settled: done };
  });

  if (target !== uid) {
    await notify([target], {
      type: 'share_paid_direct',
      title: c.label,
      body: `${names[uid]} marked your ${c.label} share as paid`,
      roomId,
      splitId,
    });
  }
  if (settled) await notifySettled(c, roomId, splitId);
  return { ok: true, settled };
});

/** The split creator or room owner puts a Paid share back to Unpaid. */
export const undoPaid = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const target = id(data.uid, 'Member');
  const names = await memberNames(roomId, [uid, target]);

  const c = await db.runTransaction(async (tx) => {
    const ctx = await load(tx, uid, roomId, splitId, target);
    if (!isManager(ctx.room, uid) && ctx.split.createdBy !== uid) {
      denied('Only the room owner or whoever added this split can undo a payment.');
    }
    if (target === ctx.split.paidBy) bad('Whoever paid the bill has nothing to pay back.');
    if (ctx.share.status !== 'paid') precondition('This share is not paid.');
    tx.update(ctx.shareRef, {
      status: 'unpaid',
      method: null,
      note: null,
      proofUrl: null,
      markedAt: null,
      confirmedBy: null,
      confirmedAt: null,
    });
    applyBalance(tx, ctx, roomId, target, false);
    setSummary(tx, ctx, roomId, splitId, target, 'unpaid');
    logActivity(tx, roomId, {
      type: 'share_undone',
      actorId: uid,
      actorName: names[uid],
      splitId,
      splitTitle: ctx.label,
      targetUserId: target,
      targetName: names[target],
      amountMinor: ctx.share.amountMinor,
    });
    return ctx;
  });

  if (target !== uid) {
    await notify([target], {
      type: 'share_undone',
      title: c.label,
      body: `${names[uid]} moved your ${c.label} share back to unpaid`,
      roomId,
      splitId,
    });
  }
  return { ok: true };
});
