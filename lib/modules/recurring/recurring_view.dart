import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../room/room_scope.dart';

class RecurringController extends RoomScope {
  RecurringController(super.roomId);
  final rules = <RecurringRule>[].obs;
  final loaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<RoomRepo>().rules(roomId), (v) {
      rules.assignAll(v);
      loaded.value = true;
    }, onError: (_) => loaded.value = true);
  }

  bool canManage(RecurringRule r) => isManager || r.createdBy == uid;

  Future<void> setActive(RecurringRule r, bool active) => Ui.attempt(
        () => api.setRuleActive(roomId, r.id, active),
        busy: busy,
        success: active ? '${r.title} will repeat again' : '${r.title} is paused',
      );

  Future<void> end(RecurringRule r) async {
    final ok = await Ui.confirm(
      title: 'End "${r.title}"?',
      message: 'No more monthly bills will be created. Bills already created stay as they are.',
      confirmLabel: 'End',
      destructive: true,
    );
    if (ok) await Ui.attempt(() => api.endRule(roomId, r.id), busy: busy, success: '${r.title} ended');
  }
}

/// The room's monthly bills: when each one runs next, with pause and end.
class RecurringView extends StatelessWidget {
  const RecurringView({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scoped<RecurringController>(
      create: () => RecurringController(roomId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(title: const Text('Monthly bills')),
        body: SafeArea(
          child: Narrow(
            child: Obx(() {
              c.members.length; // payer names update when members load
              if (!c.loaded.value) return const Center(child: CircularProgressIndicator());
              if (c.rules.isEmpty) {
                return const EmptyState(
                  icon: Icons.event_repeat_outlined,
                  title: 'No monthly bills',
                  message: 'When you add a split, turn on "Repeat monthly" for bills like rent or internet. '
                      'A new one is created for you every month.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: c.rules.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _RuleCard(c: c, rule: c.rules[i]),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.c, required this.rule});
  final RecurringController c;
  final RecurringRule rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final next = rule.nextRun;

    final String status;
    if (!rule.active) {
      status = switch (rule.pausedReason) {
        'member_left' => 'Paused: someone on this bill left the room. End it and add it again with the right people.',
        'ended' => 'Ended',
        _ => 'Paused',
      };
    } else if (next == null) {
      status = 'Ended after ${Dates.periodLabel(rule.endPeriod!)}';
    } else {
      status = 'Next: ${Dates.short(Dates.ymd(next))}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(rule.title, style: theme.textTheme.titleMedium)),
            Text(Money.format(rule.totalMinor, rule.currency), style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
          ]),
          const SizedBox(height: 4),
          Text(rule.scheduleLabel, style: muted),
          Text('Paid by ${c.nameOf(rule.paidBy)} · ${rule.participantCount} people', style: muted),
          if (rule.endPeriod != null && rule.active && next != null)
            Text('Ends after ${Dates.periodLabel(rule.endPeriod!)}', style: muted),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: rule.active && next != null
                    ? StatusChip(label: status, color: colors.owed, background: colors.owedContainer, icon: Icons.event)
                    : Text(status, style: theme.textTheme.labelLarge?.copyWith(color: colors.pending)),
              ),
            ),
            if (c.canManage(rule)) ...[
              if (rule.pausedReason != 'member_left' && rule.pausedReason != 'ended')
                TextButton(
                  onPressed: () => c.setActive(rule, !rule.active),
                  child: Text(rule.active ? 'Pause' : 'Resume'),
                ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () => c.end(rule),
                child: const Text('End'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
