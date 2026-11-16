// Split calculator. Pure, integer-only maths in minor units (1 QAR = 100).
//
// This file is mirrored by lib/core/utils/split_calculator.dart in the app.
// Keep both in sync and keep their unit tests identical, so the amounts the
// app previews are exactly what the server saves.

export type SplitType = 'equal' | 'exact' | 'percentage' | 'shares';

export const SPLIT_TYPES: SplitType[] = ['equal', 'exact', 'percentage', 'shares'];

/** 100,000,000.00 in a 2-decimal currency. Keeps every product below 2^53. */
export const MAX_TOTAL_MINOR = 10_000_000_000;
export const MAX_WEIGHT = 1000;
export const PERCENT_SCALE = 10_000; // percentages are basis points: 25% = 2500

export interface ParticipantInput {
  uid: string;
  /** exact: amount in minor units · percentage: basis points · shares: weight */
  value?: number;
}

export interface ShareAmount {
  uid: string;
  amountMinor: number;
}

export class SplitError extends Error {}

function isInt(n: unknown): n is number {
  return typeof n === 'number' && Number.isInteger(n);
}

/**
 * Divides `totalMinor` between `participants` and returns one amount per
 * participant, in the same order. The amounts always sum to `totalMinor`.
 */
export function computeShares(
  type: SplitType,
  totalMinor: number,
  participants: ParticipantInput[],
): ShareAmount[] {
  if (!isInt(totalMinor) || totalMinor <= 0) {
    throw new SplitError('Enter a total greater than zero.');
  }
  if (totalMinor > MAX_TOTAL_MINOR) {
    throw new SplitError('That total is too large.');
  }
  if (participants.length === 0) {
    throw new SplitError('Pick at least one participant.');
  }
  const seen = new Set<string>();
  for (const p of participants) {
    if (seen.has(p.uid)) throw new SplitError('A participant is listed twice.');
    seen.add(p.uid);
  }

  switch (type) {
    case 'equal': {
      const n = participants.length;
      if (totalMinor < n) {
        throw new SplitError('The total is too small to split between everyone.');
      }
      return proportional(totalMinor, participants.map((p) => ({ uid: p.uid, w: 1 })), n);
    }
    case 'exact': {
      let sum = 0;
      for (const p of participants) {
        if (!isInt(p.value) || p.value <= 0) {
          throw new SplitError('Enter an amount for every participant.');
        }
        sum += p.value;
      }
      if (sum !== totalMinor) {
        throw new SplitError('The amounts must add up to the total.');
      }
      return participants.map((p) => ({ uid: p.uid, amountMinor: p.value as number }));
    }
    case 'percentage': {
      let sum = 0;
      for (const p of participants) {
        if (!isInt(p.value) || p.value <= 0 || p.value > PERCENT_SCALE) {
          throw new SplitError('Enter a percentage for every participant.');
        }
        sum += p.value;
      }
      if (sum !== PERCENT_SCALE) {
        throw new SplitError('The percentages must add up to 100%.');
      }
      return proportional(
        totalMinor,
        participants.map((p) => ({ uid: p.uid, w: p.value as number })),
        PERCENT_SCALE,
      );
    }
    case 'shares': {
      let sum = 0;
      for (const p of participants) {
        if (!isInt(p.value) || p.value <= 0 || p.value > MAX_WEIGHT) {
          throw new SplitError('Enter a share for every participant.');
        }
        sum += p.value;
      }
      return proportional(
        totalMinor,
        participants.map((p) => ({ uid: p.uid, w: p.value as number })),
        sum,
      );
    }
    default:
      throw new SplitError('Unknown split type.');
  }
}

/**
 * total × w ÷ sumW, rounded down; the leftover minor units go one each to the
 * first participants in list order.
 */
function proportional(
  totalMinor: number,
  weights: { uid: string; w: number }[],
  sumW: number,
): ShareAmount[] {
  const out = weights.map(({ uid, w }) => ({
    uid,
    amountMinor: Math.floor((totalMinor * w) / sumW),
  }));
  let leftover = totalMinor - out.reduce((s, o) => s + o.amountMinor, 0);
  for (let i = 0; leftover > 0; i = (i + 1) % out.length) {
    out[i].amountMinor += 1;
    leftover -= 1;
  }
  if (out.some((o) => o.amountMinor <= 0)) {
    throw new SplitError('The total is too small to split this way.');
  }
  return out;
}
