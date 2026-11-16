import * as logger from 'firebase-functions/logger';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { REGION, TIME_ZONE } from './config';
import { notify } from './notify';
import { computeFor, notifyNewSplit, SplitInput, writeSplit } from './splits';
import {
  addDays, daysBetween, db, memberNames, money, roomRef, runDate, shortDate, splitLabel,
  splitRef, today, toRoom,
} from './util';

/**
 * Creates this month's split for every active rule whose day has arrived.
 * The split id is ruleId + period and the rule remembers the last period it
 * generated, so running the job twice never creates a duplicate.
 */
export async function runRecurring(date: string = today()): Promise<number> {
  const period = date.slice(0, 7);
  const rules = await db.collectionGroup('recurringRules').where('active', '==', true).get();
  let created = 0;

  for (const doc of rules.docs) {
    const rule = doc.data();
    const roomId = doc.ref.parent.parent!.id;
    try {
      if (rule.endPeriod && period > rule.endPeriod) {
        await doc.ref.update({ active: false, pausedReason: 'ended' });
        continue;
      }
      if (period < rule.startPeriod || (rule.lastGeneratedPeriod ?? '') >= period) continue;
      const runsOn = runDate(period, rule.dayOfMonth);
      if (date < runsOn) continue;

      const splitId = `${doc.id}_${period}`;
      const input: SplitInput = {
        title: rule.title,
        totalMinor: rule.totalMinor,
        paidBy: rule.paidBy,
        splitType: rule.splitType,
        participants: (rule.participants as any[]).map((p) => ({ uid: p.uid, value: p.value ?? undefined })),
        dueDate: addDays(runsOn, rule.dueAfterDays ?? 0),
        note: rule.note ?? null,
        receiptUrl: null,
      };
      const names = await memberNames(roomId, [rule.createdBy, rule.paidBy]);

      const outcome = await db.runTransaction(async (tx) => {
        const room = toRoom(await tx.get(roomRef(roomId)));
        const [fresh, existing] = await Promise.all([tx.get(doc.ref), tx.get(splitRef(roomId, splitId))]);
        if (!fresh.exists || fresh.data()!.active !== true) return null;
        if ((fresh.data()!.lastGeneratedPeriod ?? '') >= period || existing.exists) {
          tx.update(doc.ref, { lastGeneratedPeriod: period });
          return null;
        }
        // Someone on the bill has left the room: pause it and ask the creator to re-check.
        const gone = [rule.paidBy, ...input.participants.map((p) => p.uid)]
          .some((u) => !room.memberIds.includes(u));
        if (gone) {
          tx.update(doc.ref, { active: false, pausedReason: 'member_left' });
          return { room, paused: true as const };
        }
        const amounts = computeFor(room, input);
        writeSplit(tx, room, splitId, input, amounts,
          { id: rule.createdBy, name: names[rule.createdBy] }, { ruleId: doc.id, periodKey: period });
        tx.update(doc.ref, { lastGeneratedPeriod: period });
        return { room, amounts, paused: false as const };
      });

      if (!outcome) continue;
      if (outcome.paused) {
        await notify([rule.createdBy], {
          type: 'rule_check',
          title: outcome.room.name,
          body: `"${rule.title}" was paused because someone on it left the room. Please re-check it`,
          roomId,
        });
        continue;
      }
      created++;
      await notifyNewSplit(outcome.room, splitId, input, outcome.amounts, period, null, names[rule.paidBy]);
    } catch (e) {
      logger.error(`recurring rule ${doc.ref.path} failed`, e);
    }
  }
  return created;
}

/**
 * Reminds members about shares that are not Paid: 2 days before the due date,
 * on the due date, then every 3 days while overdue.
 */
export async function runReminders(date: string = today()): Promise<number> {
  const due = await db
    .collectionGroup('shares')
    .where('status', '==', 'unpaid')
    .where('dueDate', '<=', addDays(date, 2))
    .get();
  let sent = 0;
  const payerNames = new Map<string, Record<string, string>>();

  for (const doc of due.docs) {
    const s = doc.data();
    if (!s.dueDate) continue;
    const days = daysBetween(date, s.dueDate); // > 0 upcoming, 0 today, < 0 overdue
    let when: string;
    if (days === 2) when = 'is due in 2 days';
    else if (days === 0) when = 'is due today';
    else if (days < 0 && -days % 3 === 0) when = `was due on ${shortDate(s.dueDate)}`;
    else continue;

    const key = `${s.roomId}/${s.payerId}`;
    if (!payerNames.has(key)) payerNames.set(key, await memberNames(s.roomId, [s.payerId]));
    const payer = payerNames.get(key)![s.payerId];
    const label = splitLabel(s.splitTitle, s.periodKey);
    await notify([s.userId], {
      type: days < 0 ? 'overdue' : 'reminder',
      title: days < 0 ? `Overdue: ${label}` : `Reminder: ${label}`,
      body: `${label} ${when}: ${money(s.amountMinor, s.currency)} to ${payer}`,
      roomId: s.roomId,
      splitId: s.splitId,
    });
    sent++;
  }
  return sent;
}

export const generateRecurring = onSchedule(
  { schedule: '0 6 * * *', timeZone: TIME_ZONE, region: REGION },
  async () => {
    const n = await runRecurring();
    logger.info(`generateRecurring: created ${n} split(s)`);
  },
);

export const sendReminders = onSchedule(
  { schedule: '0 10 * * *', timeZone: TIME_ZONE, region: REGION },
  async () => {
    const n = await runReminders();
    logger.info(`sendReminders: sent ${n} reminder(s)`);
  },
);
