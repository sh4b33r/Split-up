import 'package:flutter/material.dart' hide Split;
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import 'room_scope.dart';

class RoomController extends RoomScope {
  RoomController(super.roomId);

  final splits = <Split>[].obs;
  final loaded = false.obs;
  final requestCount = 0.obs;

  List<Split> get open => splits.where((s) => !s.settled).toList()
    ..sort((a, b) {
      // Soonest due first; bills without a due date after those.
      final ad = a.dueDate, bd = b.dueDate;
      if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
      if (ad != null && bd == null) return -1;
      if (ad == null && bd != null) return 1;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });

  List<Split> get settled => splits.where((s) => s.settled).toList();

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<SplitRepo>().splits(roomId), (v) {
      splits.assignAll(v);
      loaded.value = true;
    }, onError: (_) => loaded.value = true);
    watch(Get.find<RoomRepo>().joinRequests(roomId), (v) => requestCount.value = v.length);
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
              if (room == null) return const SizedBox.shrink();
              return Row(children: [
                Text(room.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Flexible(child: Text(room.name, overflow: TextOverflow.ellipsis)),
              ]);
            }),
            actions: [
              IconButton(
                tooltip: 'Monthly bills',
                icon: const Icon(Icons.event_repeat_outlined),
                onPressed: () => Get.toNamed(Routes.recurring(roomId)),
              ),
              IconButton(
                tooltip: 'Activity',
                icon: const Icon(Icons.history),
                onPressed: () => Get.toNamed(Routes.activity(roomId)),
              ),
              Obx(() => IconButton(
                    tooltip: 'Room settings',
                    icon: Badge(
                      isLabelVisible: c.isManager && c.requestCount.value > 0,
                      label: Text('${c.requestCount.value}'),
                      child: const Icon(Icons.group_outlined),
                    ),
                    onPressed: () => Get.toNamed(Routes.roomSettings(roomId)),
                  )),
              const SizedBox(width: 4),
            ],
          ),
          body: SafeArea(
            child: Narrow(
              child: Column(children: [
                _Balances(c: c),
                Obx(() => TabBar(tabs: [
                      Tab(text: 'Unpaid (${c.open.length})'),
                      Tab(text: 'Settled (${c.settled.length})'),
                    ])),
                Expanded(
                  child: Obx(() {
                    c.members.length; // names on the cards update when members load
                    if (!c.loaded.value) return const Center(child: CircularProgressIndicator());
                    return TabBarView(children: [
                      _SplitList(
                        c: c,
                        splits: c.open,
                        empty: EmptyState(
                          icon: c.splits.isEmpty ? Icons.receipt_long_outlined : Icons.celebration_outlined,
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
                          icon: Icons.task_alt,
                          title: 'Nothing settled yet',
                          message: 'A bill moves here once everyone has paid their share.',
                        ),
                      ),
                    ]);
                  }),
                ),
              ]),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Get.toNamed(Routes.splitNew(roomId)),
            icon: const Icon(Icons.add),
            label: const Text('Add split'),
          ),
        ),
      ),
    );
  }
}

/// Net balance of every member: who gets money back and who owes.
class _Balances extends StatelessWidget {
  const _Balances({required this.c});
  final RoomController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    return Obx(() {
      // People who left still appear while they have a balance.
      final list = [...c.activeMembers, ...c.members.where((m) => !m.isActive && m.netMinor != 0)];
      if (list.isEmpty) return const SizedBox(height: 96);
      return SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final m = list[i];
            final net = m.netMinor;
            final color = net == 0 ? theme.colorScheme.onSurfaceVariant : (net > 0 ? colors.owed : colors.owe);
            return Container(
              constraints: const BoxConstraints(minWidth: 132),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Avatar(name: m.displayName, photoUrl: m.photoUrl, radius: 17),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.nameOf(m.uid), style: theme.textTheme.labelLarge),
                    Text(
                      net == 0 ? 'settled' : (net > 0 ? 'gets back' : (m.uid == c.uid ? 'owe' : 'owes')),
                      style: theme.textTheme.labelSmall?.copyWith(color: color),
                    ),
                    if (net != 0)
                      Text(
                        Money.format(net.abs(), c.currency),
                        style: theme.textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ]),
            );
          },
        ),
      );
    });
  }
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      itemCount: splits.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => SplitCard(c: c, split: splits[i]),
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
    if (split.settled) {
      myLine = 'Settled';
      myColor = colors.owed;
    } else if (iPaid) {
      myLine = "You're owed ${Money.format(split.outstandingMinor, split.currency)}";
      myColor = colors.owed;
    } else if (mine == null) {
      myLine = 'Not your bill';
    } else if (mine.status == ShareStatus.paid) {
      myLine = 'You paid ${Money.format(mine.amountMinor, split.currency)}';
      myColor = colors.owed;
    } else if (mine.status == ShareStatus.markedPaid) {
      myLine = 'Waiting for ${c.nameOf(split.paidBy)} to confirm';
      myColor = colors.pending;
    } else {
      myLine = 'You owe ${Money.format(mine.amountMinor, split.currency)}';
      myColor = colors.owe;
    }

    final total = split.shareSummary.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.toNamed(Routes.split(split.roomId, split.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(split.label, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (split.isRecurring)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.event_repeat, size: 16, color: muted, semanticLabel: 'Monthly'),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    'Paid by ${c.nameOf(split.paidBy)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Text(
                Money.format(split.totalMinor, split.currency),
                style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : split.paidCount / total,
                minHeight: 5,
                color: colors.owed,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(
                  myLine,
                  style: theme.textTheme.labelLarge?.copyWith(color: myColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (toConfirm > 0) ...[
                StatusChip(
                  label: '$toConfirm to confirm',
                  color: colors.pending,
                  background: colors.pendingContainer,
                  icon: Icons.hourglass_top,
                ),
                const SizedBox(width: 6),
              ],
              if (split.isOverdue)
                StatusChip.overdue(context)
              else if (!split.settled && split.dueDate != null)
                StatusChip.neutral(context, 'Due ${Dates.short(split.dueDate!)}', icon: Icons.event)
              else
                Text('${split.paidCount} of $total paid', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            ]),
          ]),
        ),
      ),
    );
  }
}
