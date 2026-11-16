// Split calculator. Pure Dart, integer-only maths in minor units.
//
// This file is mirrored by functions/src/calc.ts on the server. Keep both in
// sync and keep their unit tests identical, so the amounts the app previews
// are exactly what the server saves.

enum SplitType {
  equal('equal', 'Equally'),
  exact('exact', 'Exact amounts'),
  percentage('percentage', 'Percentages'),
  shares('shares', 'Shares');

  const SplitType(this.id, this.label);
  final String id;
  final String label;

  static SplitType fromId(String? id) =>
      SplitType.values.firstWhere((t) => t.id == id, orElse: () => SplitType.equal);
}

class ParticipantInput {
  const ParticipantInput(this.uid, [this.value]);
  final String uid;

  /// exact: amount in minor units · percentage: basis points · shares: weight
  final int? value;
}

class ShareAmount {
  const ShareAmount(this.uid, this.amountMinor);
  final String uid;
  final int amountMinor;
}

class SplitException implements Exception {
  const SplitException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SplitCalculator {
  SplitCalculator._();

  static const int maxTotalMinor = 10000000000;
  static const int maxWeight = 1000;

  /// Percentages are basis points: 25% = 2500.
  static const int percentScale = 10000;

  /// Divides [totalMinor] between [participants] and returns one amount per
  /// participant, in the same order. The amounts always sum to [totalMinor].
  static List<ShareAmount> compute(SplitType type, int totalMinor, List<ParticipantInput> participants) {
    if (totalMinor <= 0) throw const SplitException('Enter a total greater than zero.');
    if (totalMinor > maxTotalMinor) throw const SplitException('That total is too large.');
    if (participants.isEmpty) throw const SplitException('Pick at least one participant.');
    final seen = <String>{};
    for (final p in participants) {
      if (!seen.add(p.uid)) throw const SplitException('A participant is listed twice.');
    }

    switch (type) {
      case SplitType.equal:
        final n = participants.length;
        if (totalMinor < n) {
          throw const SplitException('The total is too small to split between everyone.');
        }
        return _proportional(totalMinor, [for (final p in participants) (p.uid, 1)], n);
      case SplitType.exact:
        var sum = 0;
        for (final p in participants) {
          final v = p.value;
          if (v == null || v <= 0) throw const SplitException('Enter an amount for every participant.');
          sum += v;
        }
        if (sum != totalMinor) throw const SplitException('The amounts must add up to the total.');
        return [for (final p in participants) ShareAmount(p.uid, p.value!)];
      case SplitType.percentage:
        var sum = 0;
        for (final p in participants) {
          final v = p.value;
          if (v == null || v <= 0 || v > percentScale) {
            throw const SplitException('Enter a percentage for every participant.');
          }
          sum += v;
        }
        if (sum != percentScale) throw const SplitException('The percentages must add up to 100%.');
        return _proportional(totalMinor, [for (final p in participants) (p.uid, p.value!)], percentScale);
      case SplitType.shares:
        var sum = 0;
        for (final p in participants) {
          final v = p.value;
          if (v == null || v <= 0 || v > maxWeight) {
            throw const SplitException('Enter a share for every participant.');
          }
          sum += v;
        }
        return _proportional(totalMinor, [for (final p in participants) (p.uid, p.value!)], sum);
    }
  }

  /// total × w ÷ sumW, rounded down; the leftover minor units go one each to
  /// the first participants in list order.
  static List<ShareAmount> _proportional(int totalMinor, List<(String, int)> weights, int sumW) {
    final amounts = [for (final (_, w) in weights) (totalMinor * w) ~/ sumW];
    var leftover = totalMinor - amounts.fold<int>(0, (s, a) => s + a);
    for (var i = 0; leftover > 0; i = (i + 1) % amounts.length) {
      amounts[i] += 1;
      leftover -= 1;
    }
    if (amounts.any((a) => a <= 0)) {
      throw const SplitException('The total is too small to split this way.');
    }
    return [for (var i = 0; i < weights.length; i++) ShareAmount(weights[i].$1, amounts[i])];
  }
}
