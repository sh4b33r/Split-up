import 'package:flutter_test/flutter_test.dart';
import 'package:splitup/core/utils/debts.dart';
import 'package:splitup/core/utils/split_calculator.dart';
import 'package:splitup/data/models/models.dart';

Split bill(String paidBy, Map<String, (int, ShareStatus)> shares, {bool settled = false}) => Split(
      id: 'x',
      roomId: 'r',
      title: 't',
      totalMinor: shares.values.fold(0, (s, v) => s + v.$1),
      currency: 'QAR',
      paidBy: paidBy,
      createdBy: paidBy,
      splitType: SplitType.equal,
      participantIds: shares.keys.toList(),
      inputs: const {},
      shareSummary: {for (final e in shares.entries) e.key: ShareSummary(e.value.$1, e.value.$2)},
      settled: settled,
    );

void main() {
  test('simplify: a chain becomes one payment', () {
    // A owes B 10, B owes C 10 -> A pays C 10
    expect(Debts.simplify({'A': -10, 'B': 0, 'C': 10}).map((t) => '$t'), ['A->C:10']);
  });

  test('simplify: at most n - 1 transfers and everyone ends at zero', () {
    final nets = {'a': 5000, 'b': -2000, 'c': -2500, 'd': 1000, 'e': -1500};
    final plan = Debts.simplify(nets);
    expect(plan.length, lessThanOrEqualTo(nets.length - 1));
    final after = Map.of(nets);
    for (final t in plan) {
      after[t.from] = after[t.from]! + t.amountMinor;
      after[t.to] = after[t.to]! - t.amountMinor;
    }
    expect(after.values.every((v) => v == 0), isTrue);
  });

  test('simplify: nothing to do when everyone is settled', () {
    expect(Debts.simplify({'a': 0, 'b': 0}), isEmpty);
  });

  test('pairs: nets what two people owe each other', () {
    final pairs = Debts.pairsFor('me', [
      bill('aj', {'aj': (5000, ShareStatus.paid), 'me': (5000, ShareStatus.unpaid)}),
      bill('me', {'me': (1500, ShareStatus.paid), 'aj': (1500, ShareStatus.markedPaid)}),
      bill('sara', {'sara': (100, ShareStatus.paid), 'me': (100, ShareStatus.paid)}),
      bill('aj', {'aj': (999, ShareStatus.paid), 'me': (999, ShareStatus.unpaid)}, settled: true),
    ]);
    expect(pairs.length, 1);
    final aj = pairs.single;
    expect(aj.otherId, 'aj');
    expect(aj.iOwe, 5000);
    expect(aj.theyOwe, 1500);
    expect(aj.toConfirm, 1500);
    expect(aj.net, -3500);
    expect(aj.bills, 2);
  });
}
