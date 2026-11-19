import 'dart:convert';

import 'package:flutter/material.dart' hide Split;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/routes/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/debts.dart';
import '../../core/utils/money.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../home/home_view.dart' show RoomIcon;
import 'room_scope.dart';

enum SplitFilter {
  all('All'),
  iOwe('You owe'),
  owedToMe('Owed to you'),
  overdue('Overdue'),
  monthly('Monthly');

  const SplitFilter(this.label);
  final String label;
}

class RoomController extends RoomScope {
  RoomController(super.roomId);

  final splits = <Split>[].obs;
  final loaded = false.obs;
  final requestCount = 0.obs;
  final query = ''.obs;
  final filter = SplitFilter.all.obs;
  final searching = false.obs;
  final fabExtended = true.obs;
  final search = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<SplitRepo>().splits(roomId), (v) {
      splits.assignAll(v);
      loaded.value = true;
    }, onError: (_) => loaded.value = true);
    watch(Get.find<RoomRepo>().joinRequests(roomId), (v) => requestCount.value = v.length);
  }

  @override
  void onClose() {
    search.dispose();
    super.onClose();
  }

  bool _matches(Split s) {
    final q = query.value.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = '${s.label} ${member(s.paidBy).displayName} ${s.note ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    final mine = s.shareSummary[uid];
    return switch (filter.value) {
      SplitFilter.all => true,
      SplitFilter.iOwe => s.paidBy != uid && mine != null && mine.status != ShareStatus.paid,
      SplitFilter.owedToMe => s.paidBy == uid && s.outstandingMinor > 0,
      SplitFilter.overdue => s.isOverdue,
      SplitFilter.monthly => s.isRecurring,
    };
  }

  List<Split> get open => splits.where((s) => !s.settled && _matches(s)).toList()
    ..sort((a, b) {
      // Soonest due first; bills without a due date after those.
      final ad = a.dueDate, bd = b.dueDate;
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      if (ad != null && bd == null) return -1;
      if (ad == null && bd != null) return 1;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });

  List<Split> get settled => splits.where((s) => s.settled && _matches(s)).toList();

  /// My balance in this room.
  int get myNet => member(uid).netMinor;

  List<PairBalance> get pairs => Debts.pairsFor(uid, splits);

  void toggleSearch() {
    searching.toggle();
    if (!searching.value) {
      search.clear();
      query.value = '';
    }
  }

  /// Every bill and every person's share, as a spreadsheet file.
  Future<void> exportCsv() async {
    String cell(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = <List<Object?>>[
      ['Date', 'Bill', 'Total', 'Currency', 'Paid by', 'Person', 'Share', 'Status', 'Due', 'Note'],
    ];
    final sorted = splits.toList()..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    for (final s in sorted) {
      for (final e in s.shareSummary.entries) {
        rows.add([
          s.createdAt == null ? '' : Dates.ymd(s.createdAt!),
          s.label,
          Money.editable(s.totalMinor, s.currency),
          s.currency,
          member(s.paidBy).displayName,
          member(e.key).displayName,
          Money.editable(e.value.amountMinor, s.currency),
          e.key == s.paidBy ? 'Payer' : e.value.status.label,
          s.dueDate ?? '',
          s.note ?? '',
        ]);
      }
    }
    final csv = rows.map((r) => r.map(cell).join(',')).join('\n');
    final name = '${(room.value?.name ?? 'room').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-bills.csv';
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: name)],
          fileNameOverrides: [name],
          subject: '${room.value?.name} bills',
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      Ui.toast('Copied the CSV to your clipboard');
    }
  }
}

class RoomView extends StatelessWidget {
  const RoomView({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scoped<RoomController>(
      create: () => RoomController(roomId),
      builder: (context, c) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Obx(() {
              final room = c.room.value;
              return Row(
                children: [
                  RoomIcon(icon: room?.icon ?? '🏠', size: 36, heroTag: 'room-icon-$roomId'),
                  const SizedBox(width: 10),
                  Flexible(child: Text(room?.name ?? '', overflow: TextOverflow.ellipsis)),
                ],
              );
            }),
            actions: [
              Obx(
                () => IconButton(
                  tooltip: c.searching.value ? 'Close search' : 'Search bills',
                  icon: Icon(c.searching.value ? Icons.close_rounded : Icons.search_rounded),
                  onPressed: c.toggleSearch,
                ),
              ),
              Obx(
                () => IconButton(
                  tooltip: 'Room settings',
                  icon: Badge(
                    isLabelVisible: c.isManager && c.requestCount.value > 0,
                    label: Text('${c.requestCount.value}'),
                    child: const Icon(Icons.group_outlined),
                  ),
                  onPressed: () => Get.toNamed(Routes.roomSettings(roomId)),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) => switch (v) {
                  'stats' => Get.toNamed(Routes.stats(roomId)),
                  'recurring' => Get.toNamed(Routes.recurring(roomId)),
                  'activity' => Get.toNamed(Routes.activity(roomId)),
                  _ => c.exportCsv(),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'stats',
                    child: ListTile(leading: Icon(Icons.insights_rounded), title: Text('Stats')),
                  ),
                  PopupMenuItem(
                    value: 'recurring',
                    child: ListTile(leading: Icon(Icons.event_repeat_rounded), title: Text('Monthly bills')),
                  ),
                  PopupMenuItem(
                    value: 'activity',
                    child: ListTile(leading: Icon(Icons.history_rounded), title: Text('Activity')),
                  ),
                  PopupMenuItem(
                    value: 'csv',
                    child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Export CSV')),
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Narrow(
              child: NotificationListener<UserScrollNotification>(
                onNotification: (n) {
                  if (n.direction == ScrollDirection.reverse) c.fabExtended.value = false;
                  if (n.direction == ScrollDirection.forward) c.fabExtended.value = true;
                  return false;
                },
                child: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(child: _Header(c: c)),
                    SliverToBoxAdapter(child: _SearchAndFilters(c: c)),
                    SliverPersistentHeader(pinned: true, delegate: _TabsHeader(c)),
                  ],
                  body: Obx(() {
                    c.members.length; // names on the cards update when members load
                    if (!c.loaded.value) return const SkeletonList(count: 3, height: 120);
                    final filtered = c.query.value.isNotEmpty || c.filter.value != SplitFilter.all;
                    return TabBarView(
                      children: [
                        _SplitList(
                          c: c,
                          splits: c.open,
                          empty: filtered
                              ? const EmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: 'No matches',
                                  message: 'Try another search or filter.',
                                )
                              : EmptyState(
                                  icon: c.splits.isEmpty ? Icons.receipt_long_rounded : Icons.celebration_rounded,
                                  title: c.splits.isEmpty ? 'No bills yet' : 'All settled up',
                                  message: c.splits.isEmpty
                                      ? 'Add the first bill and everyone in the room will see what they owe.'
                                      : 'Nobody owes anything in this room right now.',
                                ),
                        ),
                        _SplitList(
                          c: c,
                          splits: c.settled,
                          empty: const EmptyState(
                            icon: Icons.task_alt_rounded,
                            title: 'Nothing settled yet',
                            message: 'A bill moves here once everyone has paid their share.',
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
          floatingActionButton: Obx(
            () => FloatingActionButton.extended(
              onPressed: () => Get.toNamed(Routes.splitNew(roomId)),
              isExtended: c.fabExtended.value,
              tooltip: 'Add split',
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add split'),
            ),
          ).pop(context, delay: const Duration(milliseconds: 250)),
        ),
      ),
    );
  }
}

/// My balance in the room, with Settle up, and everyone's balances below.
class _Header extends StatelessWidget {
  const _Header({required this.c});
  final RoomController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    return Obx(() {
      final net = c.myNet;
      final people = [...c.activeMembers, ...c.members.where((m) => !m.isActive && m.netMinor != 0)];
      final label = net == 0 ? "You're all square here" : (net > 0 ? 'You get back' : 'You owe');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: HeroPanel(
              padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(color: Brand.onHeroMuted, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        MoneyCountUp(
                          minor: net,
                          currency: c.currency,
                          absolute: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                          currencyStyle: TextStyle(color: Brand.onHeroMuted, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  PressScale(
                    child: FilledButton.icon(
                      onPressed: () => Get.toNamed(Routes.settle(c.roomId)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0B6E4F), // brand green: readable on white in both themes
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.handshake_rounded, size: 20),
                      label: const Text('Settle up'),
                    ),
                  ),
                ],
              ),
            ).enter(context),
          ),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final m = people[i];
                final n = m.netMinor;
                final color = n == 0 ? theme.colorScheme.onSurfaceVariant : (n > 0 ? colors.owed : colors.owe);
                return Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Avatar(name: m.displayName, photoUrl: m.photoUrl, radius: 18),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.nameOf(m.uid), style: theme.textTheme.labelLarge),
                          if (n == 0)
                            Text('settled', style: theme.textTheme.labelSmall?.copyWith(color: color))
                          else
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: n > 0 ? '+ ' : '− '),
                                  TextSpan(text: Money.format(n.abs(), c.currency)),
                                ],
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
                            ),
                        ],
                      ),
                    ],
                  ),
                ).enter(context, index: i + 1, dx: 0.15, dy: 0);
              },
            ),
          ),
        ],
      );
    });
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({required this.c});
  final RoomController c;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: c.searching.value
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                    child: TextField(
                      controller: c.search,
                      autofocus: true,
                      onChanged: (v) => c.query.value = v,
                      decoration: const InputDecoration(
                        hintText: 'Search bills, people, notes',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: SplitFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = SplitFilter.values[i];
                return ChoiceChip(
                  label: Text(f.label),
                  selected: c.filter.value == f,
                  showCheckmark: false,
                  onSelected: (_) => c.filter.value = f,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader(this.c);
  final RoomController c;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Obx(
        () => TabBar(
          tabs: [
            Tab(text: 'Unpaid (${c.open.length})'),
            Tab(text: 'Settled (${c.settled.length})'),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabsHeader old) => old.c != c;
}

class _SplitList extends StatelessWidget {
  const _SplitList({required this.c, required this.splits, required this.empty});
  final RoomController c;
  final List<Split> splits;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) return empty;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      itemCount: splits.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) =>
          SplitCard(key: ValueKey(splits[i].id), c: c, split: splits[i]).enter(context, index: i),
    );
  }
}

class SplitCard extends StatelessWidget {
  const SplitCard({super.key, required this.c, required this.split});
  final RoomController c;
  final Split split;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final mine = split.shareSummary[c.uid];
    final iPaid = split.paidBy == c.uid;
    final toConfirm = iPaid
        ? split.shareSummary.entries.where((e) => e.key != c.uid && e.value.status == ShareStatus.markedPaid).length
        : 0;

    // What this bill means for me, in one line.
    String myLine;
    Color myColor = muted;
    IconData myIcon = Icons.info_outline_rounded;
    if (split.settled) {
      myLine = 'Settled';
      myColor = colors.owed;
      myIcon = Icons.check_circle_rounded;
    } else if (iPaid) {
      myLine = "You're owed ${Money.format(split.outstandingMinor, split.currency)}";
      myColor = colors.owed;
      myIcon = Icons.south_west_rounded;
    } else if (mine == null) {
      myLine = 'Not your bill';
    } else if (mine.status == ShareStatus.paid) {
      myLine = 'You paid ${Money.format(mine.amountMinor, split.currency)}';
      myColor = colors.owed;
      myIcon = Icons.check_circle_rounded;
    } else if (mine.status == ShareStatus.markedPaid) {
      myLine = 'Waiting for ${c.nameOf(split.paidBy)} to confirm';
      myColor = colors.pending;
      myIcon = Icons.hourglass_top_rounded;
    } else {
      myLine = 'You owe ${Money.format(mine.amountMinor, split.currency)}';
      myColor = colors.owe;
      myIcon = Icons.north_east_rounded;
    }

    final total = split.shareSummary.length;
    final payer = c.member(split.paidBy);
    return TapCard(
      onTap: () => Get.toNamed(Routes.split(split.roomId, split.id)),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(name: payer.displayName, photoUrl: payer.photoUrl, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            split.label,
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (split.isRecurring)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.event_repeat_rounded, size: 16, color: muted, semanticLabel: 'Monthly'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('Paid by ${c.nameOf(split.paidBy)}', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Hero(
                tag: 'split-amount-${split.id}',
                child: Material(
                  type: MaterialType.transparency,
                  child: Text(
                    Money.format(split.totalMinor, split.currency),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: total == 0 ? 0 : split.paidCount / total),
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  color: colors.owed,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(myIcon, size: 16, color: myColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  myLine,
                  style: theme.textTheme.labelLarge?.copyWith(color: myColor, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (split.commentCount > 0) ...[
                Icon(Icons.chat_bubble_outline_rounded, size: 15, color: muted),
                const SizedBox(width: 3),
                Text('${split.commentCount}', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                const SizedBox(width: 8),
              ],
              if (toConfirm > 0) ...[
                StatusChip(
                  label: '$toConfirm to confirm',
                  color: colors.pending,
                  background: colors.pendingContainer,
                  icon: Icons.hourglass_top_rounded,
                ).pop(context),
                const SizedBox(width: 6),
              ],
              if (split.isOverdue)
                StatusChip.overdue(context)
              else if (!split.settled && split.dueDate != null)
                StatusChip.neutral(context, 'Due ${Dates.short(split.dueDate!)}', icon: Icons.event_rounded)
              else
                Text('${split.paidCount} of $total paid', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}
