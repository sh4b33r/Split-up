// Mirrors functions/test/unit/calc.test.ts. Keep the cases identical.
import 'package:flutter_test/flutter_test.dart';
import 'package:splitup/core/services/deep_link_service.dart';
import 'package:splitup/core/utils/date_utils.dart';
import 'package:splitup/core/utils/money.dart';
import 'package:splitup/core/utils/split_calculator.dart';

List<int> amounts(List<ShareAmount> r) => r.map((x) => x.amountMinor).toList();
List<ParticipantInput> p(List<int?> values) =>
    [for (var i = 0; i < values.length; i++) ParticipantInput('u$i', values[i])];
List<ParticipantInput> eq(int n) => p(List.filled(n, null));

void main() {
  group('SplitCalculator', () {
    test('equal: rent 3,000 between three is 1,000 each', () {
      expect(amounts(SplitCalculator.compute(SplitType.equal, 300000, eq(3))), [100000, 100000, 100000]);
    });

    test('equal: internet 100 between three gives 33.34, 33.33, 33.33', () {
      expect(amounts(SplitCalculator.compute(SplitType.equal, 10000, eq(3))), [3334, 3333, 3333]);
    });

    test('equal: leftover goes one each to the first participants', () {
      expect(amounts(SplitCalculator.compute(SplitType.equal, 1001, eq(4))), [251, 250, 250, 250]);
      expect(amounts(SplitCalculator.compute(SplitType.equal, 1003, eq(4))), [251, 251, 251, 250]);
    });

    test('equal: total too small to split', () {
      expect(() => SplitCalculator.compute(SplitType.equal, 2, eq(3)), throwsA(isA<SplitException>()));
    });

    test('exact: as entered, must add up to the total', () {
      expect(amounts(SplitCalculator.compute(SplitType.exact, 10000, p([7000, 2000, 1000]))), [7000, 2000, 1000]);
      expect(
        () => SplitCalculator.compute(SplitType.exact, 10000, p([7000, 2000, 999])),
        throwsA(predicate((e) => e is SplitException && e.message.contains('add up to the total'))),
      );
      expect(() => SplitCalculator.compute(SplitType.exact, 10000, p([10000, 0])), throwsA(isA<SplitException>()));
    });

    test('percentage: basis points, must add up to 100%', () {
      expect(amounts(SplitCalculator.compute(SplitType.percentage, 10000, p([5000, 2500, 2500]))), [5000, 2500, 2500]);
      expect(amounts(SplitCalculator.compute(SplitType.percentage, 1000, p([3333, 3333, 3334]))), [334, 333, 333]);
      expect(
        () => SplitCalculator.compute(SplitType.percentage, 10000, p([5000, 2500])),
        throwsA(predicate((e) => e is SplitException && e.message.contains('100%'))),
      );
    });

    test('shares: weights 2:1:1', () {
      expect(amounts(SplitCalculator.compute(SplitType.shares, 10000, p([2, 1, 1]))), [5000, 2500, 2500]);
      expect(amounts(SplitCalculator.compute(SplitType.shares, 10001, p([2, 1, 1]))), [5001, 2500, 2500]);
      expect(amounts(SplitCalculator.compute(SplitType.shares, 100, p([1, 1, 1]))), [34, 33, 33]);
    });

    test('every type always sums to the total', () {
      for (final total in [1, 7, 99, 100, 101, 3333, 99999, 123456789]) {
        for (final n in [1, 2, 3, 7]) {
          if (total < n) continue;
          final e = SplitCalculator.compute(SplitType.equal, total, eq(n));
          expect(e.fold<int>(0, (s, x) => s + x.amountMinor), total);
          if (total >= n * 10) {
            final sh = SplitCalculator.compute(SplitType.shares, total, p([for (var i = 1; i <= n; i++) i]));
            expect(sh.fold<int>(0, (s, x) => s + x.amountMinor), total);
          }
        }
      }
    });

    test('rejects bad totals and duplicate participants', () {
      expect(() => SplitCalculator.compute(SplitType.equal, 0, eq(1)), throwsA(isA<SplitException>()));
      expect(() => SplitCalculator.compute(SplitType.equal, 100, []), throwsA(isA<SplitException>()));
      expect(
        () => SplitCalculator.compute(SplitType.equal, 100, const [ParticipantInput('a'), ParticipantInput('a')]),
        throwsA(predicate((e) => e is SplitException && e.message.contains('twice'))),
      );
    });
  });

  group('Money', () {
    test('formatting', () {
      expect(Money.format(120000, 'QAR'), '1,200 QAR');
      expect(Money.format(3334, 'QAR'), '33.34 QAR');
      expect(Money.format(5, 'QAR'), '0.05 QAR');
      expect(Money.format(1500, 'KWD'), '1.500 KWD');
      expect(Money.format(1500, 'JPY'), '1,500 JPY');
      expect(Money.format(-250050, 'USD'), '-2,500.50 USD');
    });

    test('parsing what people type', () {
      expect(Money.parse('1,200', 'QAR'), 120000);
      expect(Money.parse('33.34', 'QAR'), 3334);
      expect(Money.parse('33.3', 'QAR'), 3330);
      expect(Money.parse('.5', 'QAR'), 50);
      expect(Money.parse('0.001', 'QAR'), isNull);
      expect(Money.parse('1.500', 'KWD'), 1500);
      expect(Money.parse('12.5', 'JPY'), isNull);
      expect(Money.parse('abc', 'QAR'), isNull);
      expect(Money.parse('', 'QAR'), isNull);
      expect(Money.editable(120000, 'QAR'), '1200');
    });
  });

  group('Dates', () {
    test('labels and month maths', () {
      expect(Dates.periodLabel('2026-12'), 'Dec 2026');
      expect(Dates.splitLabel('Rent', '2026-12'), 'Rent · Dec 2026');
      expect(Dates.splitLabel('Dinner', null), 'Dinner');
      expect(Dates.ymd(Dates.runDate('2026-02', -1)), '2026-02-28');
      expect(Dates.ymd(Dates.runDate('2028-02', -1)), '2028-02-29');
      expect(Dates.nextPeriod('2026-12'), '2027-01');
      expect(Dates.ordinal(1), '1st');
      expect(Dates.ordinal(12), '12th');
      expect(Dates.ordinal(23), '23rd');
    });
  });

  group('Invite links', () {
    test('extracts the token from https and app-scheme links', () {
      expect(DeepLinkService.tokenFrom(Uri.parse('https://split-up-cd996.web.app/j/abcDEF123_-xyz0000')), 'abcDEF123_-xyz0000');
      expect(DeepLinkService.tokenFrom(Uri.parse('splitup://j/abcDEF123_-xyz0000')), 'abcDEF123_-xyz0000');
      expect(DeepLinkService.tokenFrom(Uri.parse('https://split-up-cd996.web.app/room/abc')), isNull);
      expect(DeepLinkService.tokenFrom(Uri.parse('https://split-up-cd996.web.app/j/')), isNull);
    });
  });
}
