import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../room/room_scope.dart';

/// One sentence describing a log entry, e.g. "Aj confirmed Rahul's payment".
String activityText(Activity a, String currency, {bool withSplit = true}) {
  final amount = a.amountMinor == null ? '' : Money.format(a.amountMinor!, currency);
  final split = a.splitTitle ?? 'a split';
  final target = a.targetName ?? 'someone';
  final forSplit = withSplit ? ' for $split' : '';
  final ofSplit = withSplit ? ' of $split' : '';
  switch (a.type) {
    case 'room_created':
      return '${a.actorName} created the room';
    case 'room_updated':
      return a.detail == null ? '${a.actorName} updated the room' : '${a.actorName} updated the room: ${a.detail}';
    case 'member_joined':
      return '${a.actorName} joined';
    case 'member_left':
      return '${a.actorName} left the room';
    case 'member_removed':
      return '${a.actorName} removed $target';
    case 'owner_changed':
      return '${a.actorName} made $target the owner';
    case 'split_created':
      return withSplit ? '${a.actorName} added $split ($amount)' : '${a.actorName} added this split ($amount)';
    case 'split_updated':
      final base = withSplit ? '${a.actorName} edited $split' : '${a.actorName} edited this split';
      return a.detail == null ? base : '$base (${a.detail!.toLowerCase()})';
    case 'split_deleted':
      return '${a.actorName} deleted $split ($amount)';
    case 'share_marked':
      return '${a.actorName} marked $amount as paid$forSplit';
    case 'share_confirmed':
      return "${a.actorName} confirmed $target's payment of $amount$forSplit";
    case 'share_rejected':
      return "${a.actorName} rejected $target's payment$forSplit: “${a.detail ?? ''}”";
    case 'share_paid_direct':
      return "${a.actorName} marked $target's share$ofSplit as paid ($amount)";
    case 'share_undone':
      return "${a.actorName} moved $target's share$ofSplit back to unpaid";
    case 'settled_up':
      return a.detail == 'received'
          ? '${a.actorName} settled up with $target and received $amount'
          : '${a.actorName} settled up with $target and paid $amount';
    case 'share_confirmed_all':
      return "${a.actorName} confirmed $target's payments of $amount (${a.detail ?? ''})";
    case 'rule_skipped':
      return '${a.actorName} skipped ${a.detail ?? 'a month'} of $split';
    case 'rule_unskipped':
      return '${a.actorName} un-skipped ${a.detail ?? 'a month'} of $split';
    case 'rule_updated':
      return '${a.actorName} changed $split to $amount a month';
    case 'rule_paused':
      return '${a.actorName} paused the monthly bill $split';
    case 'rule_resumed':
      return '${a.actorName} resumed the monthly bill $split';
    case 'rule_ended':
      return '${a.actorName} ended the monthly bill $split';
    default:
      return '${a.actorName} made a change';
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.activity, required this.currency, this.withSplit = true, this.onTap});
  final Activity activity;
  final String currency;
  final bool withSplit;
  final VoidCallback? onTap;

  (IconData, Color, Color) _style(BuildContext context) {
    final c = StatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final neutral = (scheme.onSurfaceVariant, scheme.surfaceContainerHighest);
    return switch (activity.type) {
      'share_confirmed' ||
      'share_paid_direct' ||
      'share_confirmed_all' ||
      'settled_up' => (Icons.check_rounded, c.owed, c.owedContainer),
      'share_marked' => (Icons.hourglass_top_rounded, c.pending, c.pendingContainer),
      'share_rejected' || 'share_undone' => (Icons.undo_rounded, c.owe, c.oweContainer),
      'split_created' => (Icons.receipt_long_outlined, scheme.onPrimaryContainer, scheme.primaryContainer),
      'split_updated' => (Icons.edit_outlined, neutral.$1, neutral.$2),
      'split_deleted' => (Icons.delete_outline, c.owe, c.oweContainer),
      'member_joined' || 'room_created' => (Icons.person_add_alt_1_outlined, neutral.$1, neutral.$2),
      'member_left' || 'member_removed' => (Icons.person_remove_outlined, neutral.$1, neutral.$2),
      'rule_paused' ||
      'rule_resumed' ||
      'rule_ended' ||
      'rule_skipped' ||
      'rule_unskipped' ||
      'rule_updated' => (Icons.event_repeat_outlined, neutral.$1, neutral.$2),
      _ => (Icons.tune, neutral.$1, neutral.$2),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, background) = _style(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: background,
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(activityText(activity, currency, withSplit: withSplit), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    Dates.ago(activity.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

class ActivityController extends RoomScope {
  ActivityController(super.roomId);
  final items = <Activity>[].obs;
  final loaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<RoomRepo>().activity(roomId), (v) {
      items.assignAll(v);
      loaded.value = true;
    }, onError: (_) => loaded.value = true);
  }
}

/// Everything that happened in the room, newest first.
class ActivityView extends StatelessWidget {
  const ActivityView({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scoped<ActivityController>(
      create: () => ActivityController(roomId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(title: const Text('Activity')),
        body: SafeArea(
          child: Narrow(
            child: Obx(() {
              if (!c.loaded.value) return const Center(child: CircularProgressIndicator());
              if (c.items.isEmpty) {
                return const EmptyState(
                  icon: Icons.history,
                  title: 'Nothing here yet',
                  message: 'Every bill, payment and confirmation in this room is logged here.',
                );
              }
              final currency = c.currency;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: c.items.length,
                itemBuilder: (context, i) {
                  final a = c.items[i];
                  final canOpen = a.splitId != null && a.type != 'split_deleted';
                  return ActivityTile(
                    activity: a,
                    currency: currency,
                    onTap: canOpen ? () => Get.toNamed(Routes.split(roomId, a.splitId!)) : null,
                  ).enter(context, index: i);
                },
              );
            }),
          ),
        ),
      ),
    );
  }
}
