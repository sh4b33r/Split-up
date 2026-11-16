import { Transaction } from 'firebase-admin/firestore';
import { computeShares, ParticipantInput, ShareAmount, SPLIT_TYPES, SplitError, SplitType } from './calc';
import { notify } from './notify';
import {
  bad, callable, db, denied, FieldValue, id, int, isManager, isValidPeriod, loadRoomFor,
  logActivity, memberNames, memberRef, money, notFound, optDate, optStr, precondition,
  Room, roomRef, shortDate, splitLabel, splitRef, str, today, Writer,
} from './util';

export interface SplitInput {
  title: string;
  totalMinor: number;
  paidBy: string;
  splitType: SplitType;
  participants: ParticipantInput[];
  dueDate: string | null;
  note: string | null;
  receiptUrl: string | null;
}

/** Validates the money part of a split against the room and computes each share. */
export function computeFor(room: Room, input: Pick<SplitInput, 'totalMinor' | 'paidBy' | 'splitType' | 'participants'>): ShareAmount[] {
  if (!room.memberIds.includes(input.paidBy)) precondition('The person who paid is not in this room.');
  for (const p of input.participants) {
    if (!room.memberIds.includes(p.uid)) precondition('A participant is no longer in this room.');
  }
  if (!input.participants.some((p) => p.uid !== input.paidBy)) {
    precondition('Add at least one person other than whoever paid.');
  }
  try {
    return computeShares(input.splitType, input.totalMinor, input.participants);
  } catch (e) {
    if (e instanceof SplitError) bad(e.message);
    throw e;
  }
}

function parseInput(data: any): SplitInput {
  const splitType = data.splitType as SplitType;
  if (!SPLIT_TYPES.includes(splitType)) bad('Split type is invalid.');
  if (!Array.isArray(data.participants) || data.participants.length === 0) bad('Pick at least one participant.');
  if (data.participants.length > 50) bad('Too many participants.');
  const participants: ParticipantInput[] = data.participants.map((p: any) => {
    const out: ParticipantInput = { uid: id(p?.uid, 'Participant') };
    if (splitType !== 'equal') out.value = int(p?.value, 'Amount', 1, 10_000_000_000);
    return out;
  });
  const receiptUrl = optStr(data.receiptUrl, 'Receipt', 1000);
  if (receiptUrl && !receiptUrl.startsWith('https://') && !receiptUrl.startsWith('http://')) bad('Receipt is invalid.');
  return {
    title: str(data.title, 'Title', 60),
    totalMinor: int(data.totalMinor, 'Total', 1, 10_000_000_000),
    paidBy: id(data.paidBy, 'Paid by'),
    splitType,
    participants,
    dueDate: optDate(data.dueDate, 'Due date'),
    note: optStr(data.note, 'Note', 500),
    receiptUrl,
  };
}

/**
 * Writes a new split, one share per participant, the balance changes and the
 * activity entry. The payer's own share is created already Paid, because they
 * cannot owe themselves.
 */
export function writeSplit(
  w: Writer,
  room: Room,
  splitId: string,
  input: SplitInput,
  amounts: ShareAmount[],
  actor: { id: string; name: string },
  recurring: { ruleId: string; periodKey: string } | null,
): void {
  const ref = splitRef(room.id, splitId);
  const set = (r: FirebaseFirestore.DocumentReference, d: any) => (w as any).set(r, d);
  const update = (r: FirebaseFirestore.DocumentReference, d: any) => (w as any).update(r, d);
  const shareSummary: Record<string, { amountMinor: number; status: string }> = {};
  const inputs: Record<string, number | null> = {};
  let owedToPayer = 0;

  for (const a of amounts) {
    const isPayer = a.uid === input.paidBy;
    shareSummary[a.uid] = { amountMinor: a.amountMinor, status: isPayer ? 'paid' : 'unpaid' };
    inputs[a.uid] = input.participants.find((p) => p.uid === a.uid)?.value ?? null;
    set(ref.collection('shares').doc(a.uid), {
      userId: a.uid,
      roomId: room.id,
      splitId,
      payerId: input.paidBy,
      amountMinor: a.amountMinor,
      currency: room.currency,
      splitTitle: input.title,
      periodKey: recurring?.periodKey ?? null,
      dueDate: input.dueDate,
      status: isPayer ? 'paid' : 'unpaid',
      method: null,
      note: null,
      proofUrl: null,
      markedAt: null,
      confirmedBy: null,
      confirmedAt: null,
      rejectReason: null,
      createdAt: FieldValue.serverTimestamp(),
    });
    if (!isPayer) {
      owedToPayer += a.amountMinor;
      update(memberRef(room.id, a.uid), { netMinor: FieldValue.increment(-a.amountMinor) });
    }
  }
  update(memberRef(room.id, input.paidBy), { netMinor: FieldValue.increment(owedToPayer) });

  set(ref, {
    title: input.title,
    totalMinor: input.totalMinor,
    currency: room.currency,
    paidBy: input.paidBy,
    createdBy: actor.id,
    splitType: input.splitType,
    participantIds: amounts.map((a) => a.uid),
    inputs,
    shareSummary,
    dueDate: input.dueDate,
    note: input.note,
    receiptUrl: input.receiptUrl,
    ruleId: recurring?.ruleId ?? null,
    periodKey: recurring?.periodKey ?? null,
    status: 'open',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  logActivity(w, room.id, {
    type: 'split_created',
    actorId: actor.id,
    actorName: actor.name,
    splitId,
    splitTitle: splitLabel(input.title, recurring?.periodKey),
    amountMinor: input.totalMinor,
  });
}

/** "New split: Rent · Dec 2026" / "You owe 1,000 QAR, due 5 Dec" */
export async function notifyNewSplit(
  room: Room,
  splitId: string,
  input: SplitInput,
  amounts: ShareAmount[],
  periodKey: string | null,
  skipUid: string | null,
  payerName: string,
): Promise<void> {
  const label = splitLabel(input.title, periodKey);
  const due = input.dueDate ? `, due ${shortDate(input.dueDate)}` : '';
  await Promise.all(
    amounts
      .filter((a) => a.uid !== skipUid)
      .map((a) =>
        notify([a.uid], {
          type: 'split_created',
          title: `New split: ${label}`,
          body:
            a.uid === input.paidBy
              ? `You paid ${money(input.totalMinor, room.currency)} in "${room.name}"`
              : `You owe ${money(a.amountMinor, room.currency)} to ${payerName}${due}`,
          roomId: room.id,
          splitId,
        }),
      ),
  );
}

interface RepeatInput {
  dayOfMonth: number;
  dueAfterDays: number;
  endPeriod: string | null;
}

function parseRepeat(v: any): RepeatInput | null {
  if (!v) return null;
  const dayOfMonth = v.dayOfMonth === -1 ? -1 : int(v.dayOfMonth, 'Repeat day', 1, 28);
  const dueAfterDays = int(v.dueAfterDays ?? 0, 'Due after', 0, 60);
  let endPeriod: string | null = null;
  if (v.endPeriod) {
    if (typeof v.endPeriod !== 'string' || !isValidPeriod(v.endPeriod)) bad('End month is invalid.');
    endPeriod = v.endPeriod;
  }
  return { dayOfMonth, dueAfterDays, endPeriod };
}

export const createSplit = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const input = parseInput(data);
  const repeat = parseRepeat(data.repeat);
  const period = today().slice(0, 7);
  if (repeat?.endPeriod && repeat.endPeriod < period) bad('The end month is in the past.');
  const names = await memberNames(roomId, [uid, input.paidBy]);

  const ruleRef = repeat ? roomRef(roomId).collection('recurringRules').doc() : null;
  // A recurring split's id is ruleId + period, so a month can never be created twice.
  const splitId = ruleRef ? `${ruleRef.id}_${period}` : roomRef(roomId).collection('splits').doc().id;

  const { room, amounts } = await db.runTransaction(async (tx) => {
    const r = await loadRoomFor(uid, roomId, tx);
    const a = computeFor(r, input);
    if (ruleRef && repeat) {
      tx.set(ruleRef, {
        title: input.title,
        totalMinor: input.totalMinor,
        currency: r.currency,
        paidBy: input.paidBy,
        createdBy: uid,
        splitType: input.splitType,
        participants: input.participants.map((p) => ({ uid: p.uid, value: p.value ?? null })),
        note: input.note,
        dayOfMonth: repeat.dayOfMonth,
        dueAfterDays: repeat.dueAfterDays,
        startPeriod: period,
        endPeriod: repeat.endPeriod,
        active: true,
        lastGeneratedPeriod: period,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    writeSplit(tx, r, splitId, input, a, { id: uid, name: names[uid] },
      ruleRef ? { ruleId: ruleRef.id, periodKey: period } : null);
    return { room: r, amounts: a };
  });

  await notifyNewSplit(room, splitId, input, amounts, ruleRef ? period : null, uid, names[input.paidBy]);
  return { splitId, ruleId: ruleRef?.id ?? null };
});

interface Loaded {
  room: Room;
  split: FirebaseFirestore.DocumentData;
  shares: FirebaseFirestore.QueryDocumentSnapshot[];
}

async function loadSplit(tx: Transaction, uid: string, roomId: string, splitId: string): Promise<Loaded> {
  const room = await loadRoomFor(uid, roomId, tx);
  const ref = splitRef(roomId, splitId);
  const snap = await tx.get(ref);
  if (!snap.exists) notFound('That split no longer exists.');
  const shares = await tx.get(ref.collection('shares'));
  return { room, split: snap.data()!, shares: shares.docs };
}

/** Takes a split's unpaid shares back out of the members' balances. */
function reverseBalances(tx: Transaction, roomId: string, split: FirebaseFirestore.DocumentData, shares: FirebaseFirestore.QueryDocumentSnapshot[]) {
  let owed = 0;
  for (const s of shares) {
    const d = s.data();
    if (d.status === 'paid') continue;
    owed += d.amountMinor;
    tx.update(memberRef(roomId, s.id), { netMinor: FieldValue.increment(d.amountMinor) });
  }
  if (owed > 0) tx.update(memberRef(roomId, split.paidBy), { netMinor: FieldValue.increment(-owed) });
}

export const updateSplit = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const input = parseInput(data);
  const names = await memberNames(roomId, [uid, input.paidBy]);

  const result = await db.runTransaction(async (tx) => {
    const { room, split, shares } = await loadSplit(tx, uid, roomId, splitId);
    const manager = isManager(room, uid);
    const hasPaid = shares.some((s) => s.id !== split.paidBy && s.data().status === 'paid');
    if (hasPaid ? !manager : !manager && split.createdBy !== uid) {
      denied(hasPaid
        ? 'Only the room owner can edit a split after someone has paid.'
        : 'Only the room owner or whoever added this split can edit it.');
    }

    const old = new Map(shares.map((s) => [s.id, s.data().amountMinor as number]));
    const amounts = computeFor(room, input);
    const moneyChanged =
      input.paidBy !== split.paidBy ||
      input.totalMinor !== split.totalMinor ||
      amounts.length !== old.size ||
      amounts.some((a) => old.get(a.uid) !== a.amountMinor);

    const ref = splitRef(roomId, splitId);
    const label = splitLabel(input.title, split.periodKey);
    if (!moneyChanged) {
      tx.update(ref, {
        title: input.title,
        dueDate: input.dueDate,
        note: input.note,
        receiptUrl: input.receiptUrl,
        updatedAt: FieldValue.serverTimestamp(),
      });
      for (const s of shares) tx.update(s.ref, { splitTitle: input.title, dueDate: input.dueDate });
    } else {
      if (hasPaid) {
        precondition('Someone has already paid. Undo the paid shares before changing the amounts.');
      }
      reverseBalances(tx, roomId, split, shares);
      for (const s of shares) tx.delete(s.ref);
      // Keep the original creator and creation time: only the content changes.
      writeSplitUpdate(tx, room, splitId, input, amounts, split);
    }
    logActivity(tx, roomId, {
      type: 'split_updated',
      actorId: uid,
      actorName: names[uid],
      splitId,
      splitTitle: label,
      amountMinor: input.totalMinor,
      detail: hasPaid ? 'Edited after a payment' : null,
    });
    return { room, amounts, moneyChanged, label, participantIds: split.participantIds as string[] };
  });

  const { room, amounts, moneyChanged, label } = result;
  if (moneyChanged) {
    await Promise.all(
      amounts
        .filter((a) => a.uid !== uid && a.uid !== input.paidBy)
        .map((a) =>
          notify([a.uid], {
            type: 'split_updated',
            title: room.name,
            body: `${names[uid]} changed ${label}: you now owe ${money(a.amountMinor, room.currency)}`,
            roomId,
            splitId,
          }),
        ),
    );
    const dropped = result.participantIds.filter((p) => !amounts.some((a) => a.uid === p) && p !== uid);
    await notify(dropped, {
      type: 'split_updated',
      title: room.name,
      body: `${names[uid]} removed you from ${label}`,
      roomId,
    });
  } else {
    await notify(amounts.map((a) => a.uid).filter((u) => u !== uid), {
      type: 'split_updated',
      title: room.name,
      body: `${names[uid]} updated ${label}`,
      roomId,
      splitId,
    });
  }
  return { ok: true };
});

/** Rewrites a split's money in place, keeping who created it and when. */
function writeSplitUpdate(
  tx: Transaction, room: Room, splitId: string, input: SplitInput,
  amounts: ShareAmount[], previous: FirebaseFirestore.DocumentData,
) {
  const ref = splitRef(room.id, splitId);
  const shareSummary: Record<string, { amountMinor: number; status: string }> = {};
  const inputs: Record<string, number | null> = {};
  let owed = 0;
  for (const a of amounts) {
    const isPayer = a.uid === input.paidBy;
    shareSummary[a.uid] = { amountMinor: a.amountMinor, status: isPayer ? 'paid' : 'unpaid' };
    inputs[a.uid] = input.participants.find((p) => p.uid === a.uid)?.value ?? null;
    tx.set(ref.collection('shares').doc(a.uid), {
      userId: a.uid,
      roomId: room.id,
      splitId,
      payerId: input.paidBy,
      amountMinor: a.amountMinor,
      currency: room.currency,
      splitTitle: input.title,
      periodKey: previous.periodKey ?? null,
      dueDate: input.dueDate,
      status: isPayer ? 'paid' : 'unpaid',
      method: null,
      note: null,
      proofUrl: null,
      markedAt: null,
      confirmedBy: null,
      confirmedAt: null,
      rejectReason: null,
      createdAt: previous.createdAt,
    });
    if (!isPayer) {
      owed += a.amountMinor;
      tx.update(memberRef(room.id, a.uid), { netMinor: FieldValue.increment(-a.amountMinor) });
    }
  }
  tx.update(memberRef(room.id, input.paidBy), { netMinor: FieldValue.increment(owed) });
  tx.update(ref, {
    title: input.title,
    totalMinor: input.totalMinor,
    paidBy: input.paidBy,
    splitType: input.splitType,
    participantIds: amounts.map((a) => a.uid),
    inputs,
    shareSummary,
    dueDate: input.dueDate,
    note: input.note,
    receiptUrl: input.receiptUrl,
    status: 'open',
    updatedAt: FieldValue.serverTimestamp(),
  });
}

export const deleteSplit = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const splitId = id(data.splitId, 'Split');
  const names = await memberNames(roomId, [uid]);

  const result = await db.runTransaction(async (tx) => {
    const { room, split, shares } = await loadSplit(tx, uid, roomId, splitId);
    if (!isManager(room, uid) && split.createdBy !== uid) {
      denied('Only the room owner or whoever added this split can delete it.');
    }
    if (shares.some((s) => s.id !== split.paidBy && s.data().status === 'paid')) {
      precondition('A split with paid shares cannot be deleted. Undo the paid shares first.');
    }
    reverseBalances(tx, roomId, split, shares);
    for (const s of shares) tx.delete(s.ref);
    tx.delete(splitRef(roomId, splitId));
    const label = splitLabel(split.title, split.periodKey);
    logActivity(tx, roomId, {
      type: 'split_deleted',
      actorId: uid,
      actorName: names[uid],
      splitTitle: label,
      amountMinor: split.totalMinor,
    });
    return { room, label, participantIds: split.participantIds as string[] };
  });

  await notify(result.participantIds.filter((p) => p !== uid), {
    type: 'split_deleted',
    title: result.room.name,
    body: `${names[uid]} deleted ${result.label}`,
    roomId,
  });
  return { ok: true };
});

/** Pause, resume or end a monthly bill. */
export const updateRule = callable(async (uid, data) => {
  const roomId = id(data.roomId, 'Room');
  const ref = roomRef(roomId).collection('recurringRules').doc(id(data.ruleId, 'Rule'));
  const room = await loadRoomFor(uid, roomId);
  const snap = await ref.get();
  if (!snap.exists) notFound('That monthly bill no longer exists.');
  const rule = snap.data()!;
  if (!isManager(room, uid) && rule.createdBy !== uid) {
    denied('Only the room owner or whoever set up this bill can change it.');
  }
  const names = await memberNames(roomId, [uid]);
  const batch = db.batch();
  if (data.end === true) {
    batch.delete(ref);
    logActivity(batch, roomId, { type: 'rule_ended', actorId: uid, actorName: names[uid], splitTitle: rule.title });
  } else if (typeof data.active === 'boolean') {
    batch.update(ref, { active: data.active, pausedReason: null });
    logActivity(batch, roomId, {
      type: data.active ? 'rule_resumed' : 'rule_paused',
      actorId: uid,
      actorName: names[uid],
      splitTitle: rule.title,
    });
  } else {
    bad('Nothing to change.');
  }
  await batch.commit();
  return { ok: true };
});
