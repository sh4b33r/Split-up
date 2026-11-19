import '../../data/models/models.dart';

/// What two people owe each other across the open bills in a room.
class PairBalance {
  PairBalance({required this.otherId});
  final String otherId;

  /// Still owed by me to them (unpaid or waiting for their confirmation).
  int iOwe = 0;

  /// Still owed by them to me.
  int theyOwe = 0;

  /// Of [theyOwe]: what they say they paid and I haven't confirmed yet.
  int toConfirm = 0;

  /// Of [iOwe]: what I marked paid and they haven't confirmed yet.
  int waiting = 0;
  int bills = 0;

  /// Positive: they owe me. Negative: I owe them.
  int get net => theyOwe - iOwe;
}

/// One payment in the "fewest payments" plan.
class Transfer {
  const Transfer(this.from, this.to, this.amountMinor);
  final String from;
  final String to;
  final int amountMinor;

  @override
  String toString() => '$from->$to:$amountMinor';
}

class Debts {
  Debts._();

  /// Everyone I have open bills with, biggest balance first.
  static List<PairBalance> pairsFor(String me, Iterable<Split> splits) {
    final map = <String, PairBalance>{};
    for (final s in splits) {
      if (s.settled) continue;
      if (s.paidBy == me) {
        for (final e in s.shareSummary.entries) {
          if (e.key == me || e.value.status == ShareStatus.paid) continue;
          final p = map.putIfAbsent(e.key, () => PairBalance(otherId: e.key));
          p.theyOwe += e.value.amountMinor;
          if (e.value.status == ShareStatus.markedPaid) p.toConfirm += e.value.amountMinor;
          p.bills++;
        }
      } else {
        final mine = s.shareSummary[me];
        if (mine == null || mine.status == ShareStatus.paid) continue;
        final p = map.putIfAbsent(s.paidBy, () => PairBalance(otherId: s.paidBy));
        p.iOwe += mine.amountMinor;
        if (mine.status == ShareStatus.markedPaid) p.waiting += mine.amountMinor;
        p.bills++;
      }
    }
    return map.values.toList()..sort((a, b) => b.net.abs().compareTo(a.net.abs()));
  }

  /// The fewest payments that settle everyone: repeatedly match the largest
  /// creditor with the largest debtor. At most n - 1 transfers.
  static List<Transfer> simplify(Map<String, int> nets) {
    final creditors = [for (final e in nets.entries) if (e.value > 0) MapEntry(e.key, e.value)];
    final debtors = [for (final e in nets.entries) if (e.value < 0) MapEntry(e.key, -e.value)];
    final out = <Transfer>[];
    while (creditors.isNotEmpty && debtors.isNotEmpty) {
      creditors.sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
      debtors.sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
      final c = creditors.first, d = debtors.first;
      final amount = c.value < d.value ? c.value : d.value;
      out.add(Transfer(d.key, c.key, amount));
      creditors[0] = MapEntry(c.key, c.value - amount);
      debtors[0] = MapEntry(d.key, d.value - amount);
      creditors.removeWhere((e) => e.value == 0);
      debtors.removeWhere((e) => e.value == 0);
    }
    return out;
  }
}
