import { FieldPath } from 'firebase-admin/firestore';
import { PAYMENT_METHODS } from './config';
import { notify } from './notify';
import {
  bad, callable, db, denied, FieldValue, id, isManager, loadRoomFor, logActivity, memberNames,
  memberRef, money, optStr, precondition, roomRef, splitLabel, toRoom,
} from './util';

// Settling up between two people clears every open share between them at once.
//
// When I settle up with someone:
//   - shares I owe them become "marked paid" (they confirm, as with I've paid);
//   - shares they owe me become "paid" (I am the payer, so I can say so).
// Only the difference changes hands, and they get one notification for it.

const MAX_SPLITS = 200;

interface PairShare {
  splitRef: FirebaseFirestore.DocumentReference;
  shareRef: FirebaseFirestore.DocumentReference;
  amountMinor: number;
  status: string;
  label: string;
  createdAt: number;
  summary: Record<string, { amountMinor: number; status: string }>;
}

async function openBetween(tx: FirebaseFirestore.Transaction, roomId: string, me: string, other: string) {
  const open = await tx.get(roomRef(roomId).collection('splits').where('status', '==', 'open').limit(MAX_SPLITS));
  const iOwe: PairShare[] = [];
  const owedToMe: PairShare[] = [];
  for (const doc of open.docs) {
    const s = doc.data();
    const summary = (s.shareSummary ?? {}) as PairShare['summary'];
    const debtor = s.paidBy === other ? me : s.paidBy === me ? other : null;
    if (!debtor) continue;
    const share = summary[debtor];
    if (!share || share.status === 'paid') continue;
    const entry: PairShare = {
      splitRef: doc.ref,
      shareRef: doc.ref.collection('shares').doc(debtor),
      amountMinor: share.amountMinor,
      status: share.status,
      label: splitLabel(s.title, s.periodKey),
      createdAt: s.createdAt?.toMillis?.() ?? 0,
      summary,
    };
    (debtor === me ? iOwe : owedToMe).push(entry);
  }
  const oldestFirst = (a: PairShare, b: PairShare) => a.createdAt - b.createdAt;
  return { iOwe: iOwe.sort(oldestFirst), owedToMe: owedToMe.sort(oldestFirst) };
}

function updateSummary(
  tx: FirebaseFirestore.Transaction,
  p: PairShare,
  debtor: string,
  status: string,
) {
  const summary = { ...p.summary, [debtor]: { ...p.summary[debtor], status } };
  const settled = Object.values(summary).every((s) => s.status === 'paid');
  tx.update(
    p.splitRef,
    new FieldPath('shareSummary', debtor, 'status'), status,
    'status', settled ? 'settled' : 'open',
    'updatedAt', FieldValue.serverTimestamp(),
  );
  return settled;
}

export const settleUp = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const other = id(data.uid, 'Member');
  if (other === uid) bad('You cannot settle up with yourself.');
  const method = data.method ?? 'cash';
  if (!PAYMENT_METHODS.includes(method)) bad('Pick how you paid.');
  const note = optStr(data.note, 'Note', 300);
  const names = await memberNames(roomId, [uid, other]);

  const result = await db.runTransaction(async (tx) => {
    const room = await loadRoomFor(uid, roomId, tx);
    const { iOwe, owedToMe } = await openBetween(tx, roomId, uid, other);
    if (iOwe.length === 0 && owedToMe.length === 0) precondition('You are already settled up with them.');

    let paidOut = 0; // what I owe them, now marked paid
    for (const p of iOwe) {
      paidOut += p.amountMinor;
      if (p.status === 'marked_paid') continue;
      tx.update(p.shareRef, {
        status: 'marked_paid', method, note, proofUrl: null,
        markedAt: FieldValue.serverTimestamp(), rejectReason: null,
      });
      updateSummary(tx, p, uid, 'marked_paid');
    }
    let received = 0; // what they owe me, now paid
    let settledSplits = 0;
    for (const p of owedToMe) {
      received += p.amountMinor;
      tx.update(p.shareRef, {
        status: 'paid', method: method, confirmedBy: uid,
        confirmedAt: FieldValue.serverTimestamp(), rejectReason: null,
      });
      if (updateSummary(tx, p, other, 'paid')) settledSplits++;
    }
    if (received > 0) {
      tx.update(memberRef(roomId, other), { netMinor: FieldValue.increment(received) });
      tx.update(memberRef(roomId, uid), { netMinor: FieldValue.increment(-received) });
    }
    logActivity(tx, roomId, {
      type: 'settled_up',
      actorId: uid,
      actorName: names[uid],
      targetUserId: other,
      targetName: names[other],
      amountMinor: Math.abs(paidOut - received),
      detail: paidOut >= received ? 'paid' : 'received',
    });
    return { room, paidOut, received, bills: iOwe.length + owedToMe.length, settledSplits };
  });

  const net = result.paidOut - result.received;
  const cur = result.room.currency;
  await notify([other], {
    type: net > 0 ? 'share_marked' : 'settled_up',
    title: result.room.name,
    body:
      net > 0
        ? `${names[uid]} settled up with you: paid ${money(net, cur)}. Confirm?`
        : net < 0
          ? `${names[uid]} settled up with you. They received ${money(-net, cur)} from you`
          : `${names[uid]} settled up with you. Your bills cancel out`,
    roomId,
  });
  return { ok: true, net, bills: result.bills };
});

/** The payer confirms every payment a member has marked as paid. */
export const confirmAll = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const from = id(data.uid, 'Member');
  const names = await memberNames(roomId, [uid, from]);

  const result = await db.runTransaction(async (tx) => {
    const room = toRoom(await tx.get(roomRef(roomId)));
    if (!room.memberIds.includes(uid)) denied('You are not a member of this room.');
    const open = await tx.get(roomRef(roomId).collection('splits').where('status', '==', 'open').limit(MAX_SPLITS));
    let total = 0;
    let count = 0;
    const settled: string[] = [];
    for (const doc of open.docs) {
      const s = doc.data();
      const mine = s.paidBy === uid || isManager(room, uid) || s.createdBy === uid;
      const share = s.shareSummary?.[from];
      if (!mine || from === s.paidBy || share?.status !== 'marked_paid') continue;
      const p: PairShare = {
        splitRef: doc.ref, shareRef: doc.ref.collection('shares').doc(from), amountMinor: share.amountMinor,
        status: share.status, label: splitLabel(s.title, s.periodKey), createdAt: 0, summary: s.shareSummary,
      };
      tx.update(p.shareRef, { status: 'paid', confirmedBy: uid, confirmedAt: FieldValue.serverTimestamp() });
      tx.update(memberRef(roomId, from), { netMinor: FieldValue.increment(p.amountMinor) });
      tx.update(memberRef(roomId, s.paidBy), { netMinor: FieldValue.increment(-p.amountMinor) });
      if (updateSummary(tx, p, from, 'paid')) settled.push(p.label);
      total += p.amountMinor;
      count++;
    }
    if (count === 0) precondition('There is nothing from them to confirm.');
    logActivity(tx, roomId, {
      type: 'share_confirmed_all',
      actorId: uid, actorName: names[uid], targetUserId: from, targetName: names[from], amountMinor: total,
      detail: `${count} bill${count === 1 ? '' : 's'}`,
    });
    return { room, total, count };
  });

  await notify([from], {
    type: 'share_confirmed',
    title: result.room.name,
    body: `${names[uid]} confirmed your payments of ${money(result.total, result.room.currency)}`,
    roomId,
  });
  return { ok: true, count: result.count };
});
