// Mirrors test/split_calculator_test.dart in the app. Keep the cases identical.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { computeShares, SplitError } from '../../src/calc';
import { addDays, daysBetween, lastDayOfMonth, money, runDate, splitLabel } from '../../src/util';

const amounts = (r: { amountMinor: number }[]) => r.map((x) => x.amountMinor);
const P = (...values: (number | undefined)[]) => values.map((value, i) => ({ uid: `u${i}`, value }));

test('equal: rent 3,000 between three is 1,000 each', () => {
  assert.deepEqual(amounts(computeShares('equal', 300000, P(undefined, undefined, undefined))), [100000, 100000, 100000]);
});

test('equal: internet 100 between three gives 33.34, 33.33, 33.33', () => {
  assert.deepEqual(amounts(computeShares('equal', 10000, P(undefined, undefined, undefined))), [3334, 3333, 3333]);
});

test('equal: leftover goes one each to the first participants', () => {
  assert.deepEqual(amounts(computeShares('equal', 1001, P(undefined, undefined, undefined, undefined))), [251, 250, 250, 250]);
  assert.deepEqual(amounts(computeShares('equal', 1003, P(undefined, undefined, undefined, undefined))), [251, 251, 251, 250]);
});

test('equal: total too small to split', () => {
  assert.throws(() => computeShares('equal', 2, P(undefined, undefined, undefined)), SplitError);
});

test('exact: as entered, must add up to the total', () => {
  assert.deepEqual(amounts(computeShares('exact', 10000, P(7000, 2000, 1000))), [7000, 2000, 1000]);
  assert.throws(() => computeShares('exact', 10000, P(7000, 2000, 999)), /add up to the total/);
  assert.throws(() => computeShares('exact', 10000, P(10000, 0)), SplitError);
});

test('percentage: basis points, must add up to 100%', () => {
  assert.deepEqual(amounts(computeShares('percentage', 10000, P(5000, 2500, 2500))), [5000, 2500, 2500]);
  assert.deepEqual(amounts(computeShares('percentage', 1000, P(3333, 3333, 3334))), [334, 333, 333]);
  assert.throws(() => computeShares('percentage', 10000, P(5000, 2500)), /100%/);
});

test('shares: weights 2:1:1', () => {
  assert.deepEqual(amounts(computeShares('shares', 10000, P(2, 1, 1))), [5000, 2500, 2500]);
  assert.deepEqual(amounts(computeShares('shares', 10001, P(2, 1, 1))), [5001, 2500, 2500]);
  assert.deepEqual(amounts(computeShares('shares', 100, P(1, 1, 1))), [34, 33, 33]);
});

test('every type always sums to the total', () => {
  for (const total of [1, 7, 99, 100, 101, 3333, 99999, 123456789]) {
    for (const n of [1, 2, 3, 7]) {
      if (total < n) continue;
      const eq = computeShares('equal', total, P(...Array(n).fill(undefined)));
      assert.equal(eq.reduce((s, x) => s + x.amountMinor, 0), total);
      if (total >= n * 10) {
        const sh = computeShares('shares', total, P(...Array.from({ length: n }, (_, i) => i + 1)));
        assert.equal(sh.reduce((s, x) => s + x.amountMinor, 0), total);
      }
    }
  }
});

test('rejects bad totals and duplicate participants', () => {
  assert.throws(() => computeShares('equal', 0, P(undefined)), SplitError);
  assert.throws(() => computeShares('equal', 10.5, P(undefined)), SplitError);
  assert.throws(() => computeShares('equal', 100, []), SplitError);
  assert.throws(() => computeShares('equal', 100, [{ uid: 'a' }, { uid: 'a' }]), /twice/);
});

test('money formatting', () => {
  assert.equal(money(120000, 'QAR'), '1,200 QAR');
  assert.equal(money(3334, 'QAR'), '33.34 QAR');
  assert.equal(money(5, 'QAR'), '0.05 QAR');
  assert.equal(money(1500, 'KWD'), '1.500 KWD');
  assert.equal(money(1500, 'JPY'), '1,500 JPY');
  assert.equal(money(-250050, 'USD'), '-2,500.50 USD');
});

test('dates', () => {
  assert.equal(addDays('2026-12-29', 5), '2027-01-03');
  assert.equal(daysBetween('2026-12-01', '2026-12-05'), 4);
  assert.equal(lastDayOfMonth('2028-02'), 29);
  assert.equal(runDate('2026-02', -1), '2026-02-28');
  assert.equal(runDate('2026-12', 1), '2026-12-01');
  assert.equal(splitLabel('Rent', '2026-12'), 'Rent · Dec 2026');
  assert.equal(splitLabel('Dinner', null), 'Dinner');
});
