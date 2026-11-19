import 'package:flutter/material.dart' hide Split;
import 'package:get/get.dart';

import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../room/room_scope.dart';

class MonthTotal {
  MonthTotal(this.period, this.total, this.mine, this.count);
  final String period;
  final int total;
  final int mine;
  final int count;
}

class StatsController extends RoomScope {
  StatsController(super.roomId);

  final splits = <Split>[].obs;
  final loaded = false.obs;

  /// The month the user tapped in the chart; defaults to this month.
  final selected = RxnString();

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<SplitRepo>().splits(roomId), (v) {
      splits.assignAll(v);
      loaded.value = true;
    }, onError: (_) => loaded.value = true);
  }

  String _periodOf(Split s) => s.periodKey ?? Dates.period(s.createdAt ?? DateTime.now());

  /// The last six months, oldest first, including empty ones.
  List<MonthTotal> get months {
    final now = DateTime.now();
    final periods = [for (var i = 5; i >= 0; i--) Dates.period(DateTime(now.year, now.month - i))];
    return [
      for (final p in periods)
        () {
          final inMonth = splits.where((s) => _periodOf(s) == p);
          return MonthTotal(
            p,
            inMonth.fold(0, (a, s) => a + s.totalMinor),
            inMonth.fold(0, (a, s) => a + (s.shareSummary[uid]?.amountMinor ?? 0)),
            inMonth.length,
          );
        }(),
    ];
  }

  /// Who paid the most, across every bill in the room.
  List<MapEntry<String, int>> get payers {
    final totals = <String, int>{};
    for (final s in splits) {
      totals[s.paidBy] = (totals[s.paidBy] ?? 0) + s.totalMinor;
    }
    return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  int get allTime => splits.fold(0, (a, s) => a + s.totalMinor);
  int get myAllTime => splits.fold(0, (a, s) => a + (s.shareSummary[uid]?.amountMinor ?? 0));
}

class StatsView extends StatelessWidget {
  const StatsView({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scoped<StatsController>(
      create: () => StatsController(roomId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(title: const Text('Stats')),
        body: SafeArea(
          child: Narrow(
            child: Obx(() {
              c.members.length;
              if (!c.loaded.value) return const SkeletonList(count: 3, height: 140);
              if (c.splits.isEmpty) {
                return const EmptyState(
                  icon: Icons.insights_rounded,
                  title: 'No numbers yet',
                  message: 'Once the room has bills, you will see where the money goes each month.',
                );
              }
              final months = c.months;
              final sel = months.firstWhere(
                (m) => m.period == (c.selected.value ?? months.last.period),
                orElse: () => months.last,
              );
              final theme = Theme.of(context);
              final muted = theme.colorScheme.onSurfaceVariant;
              var i = 0;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          label: 'All bills',
                          value: c.allTime,
                          currency: c.currency,
                          sub: '${c.splits.length} bills',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Tile(label: 'Your share', value: c.myAllTime, currency: c.currency, sub: 'all time'),
                      ),
                    ],
                  ).enter(context, index: i++),
                  const SectionTitle('Spending by month'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Dates.periodLabel(sel.period),
                            style: theme.textTheme.labelLarge?.copyWith(color: muted),
                          ),
                          const SizedBox(height: 2),
                          MoneyCountUp(
                            minor: sel.total,
                            currency: c.currency,
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                            currencyStyle: theme.textTheme.titleSmall?.copyWith(color: muted),
                          ),
                          Text(
                            '${sel.count} bill${sel.count == 1 ? '' : 's'} · your share ${Money.format(sel.mine, c.currency)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: muted),
                          ),
                          const SizedBox(height: 16),
                          _MonthBars(c: c, months: months, selected: sel.period),
                        ],
                      ),
                    ),
                  ).enter(context, index: i++),
                  const SectionTitle('Who paid the most'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Column(
                        children: [
                          for (final (k, e) in c.payers.indexed)
                            _PayerBar(
                              name: c.nameOf(e.key),
                              member: c.member(e.key),
                              value: e.value,
                              max: c.payers.first.value,
                              currency: c.currency,
                            ).enter(context, index: i + k),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.currency, required this.sub});
  final String label;
  final int value;
  final String currency;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyCountUp(
                minor: value,
                currency: currency,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                currencyStyle: theme.textTheme.labelLarge?.copyWith(color: muted),
              ),
            ),
            Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
    );
  }
}

/// Six monthly bars, one hue. Tap a bar to see that month above the chart.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.c, required this.months, required this.selected});
  final StatsController c;
  final List<MonthTotal> months;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final max = months.fold<int>(1, (a, m) => m.total > a ? m.total : a);
    const height = 150.0;
    return SizedBox(
      height: height + 26,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: Stack(
              children: [
                // Recessive guide at the top value and the baseline.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: scheme.outlineVariant)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final (i, m) in months.indexed)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: m.period == selected,
                          label: '${Dates.periodLabel(m.period)}: ${Money.format(m.total, c.currency)}',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => c.selected.value = m.period,
                            child: Padding(
                              // The 2px surface gap between neighbouring bars, plus breathing room.
                              padding: const EdgeInsets.symmetric(horizontal: 7),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: m.total / max),
                                  duration: reduceMotion(context)
                                      ? Duration.zero
                                      : Duration(milliseconds: 700 + i * 70),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    height: m.total == 0 ? 2 : (height - 4) * v + 2,
                                    constraints: const BoxConstraints(maxWidth: 34),
                                    decoration: BoxDecoration(
                                      color: m.period == selected
                                          ? scheme.primary
                                          : scheme.primary.withValues(alpha: 0.38),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: Row(
              children: [
                for (final m in months)
                  Expanded(
                    child: Text(
                      Dates.periodLabel(m.period).split(' ').first,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: m.period == selected ? scheme.onSurface : scheme.onSurfaceVariant,
                        fontWeight: m.period == selected ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PayerBar extends StatelessWidget {
  const _PayerBar({
    required this.name,
    required this.member,
    required this.value,
    required this.max,
    required this.currency,
  });
  final String name;
  final Member member;
  final int value;
  final int max;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: '$name paid ${Money.format(value, currency)}',
        excludeSemantics: true,
        child: Row(
          children: [
            Avatar(name: member.displayName, photoUrl: member.photoUrl, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(name, style: theme.textTheme.labelLarge)),
                      Text(
                        Money.format(value, currency),
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, box) {
                      return Stack(
                        children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: max == 0 ? 0 : value / max),
                            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => Container(
                              height: 8,
                              width: box.maxWidth * v,
                              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
