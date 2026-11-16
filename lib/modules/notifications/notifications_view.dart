import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/push_service.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/live_controller.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

class NotificationsController extends LiveController {
  final AuthService _auth = Get.find();
  final NotificationRepo _repo = Get.find();
  final items = <AppNotification>[].obs;
  final loaded = false.obs;

  bool get hasUnread => items.any((n) => !n.read);

  @override
  void onInit() {
    super.onInit();
    watch(_repo.inbox(_auth.uid), (v) {
      items.assignAll(v);
      loaded.value = true;
    }, onError: (_) => loaded.value = true);
  }

  void open(AppNotification n) {
    if (!n.read) _repo.markRead(_auth.uid, n.id);
    if (n.type == 'invite') {
      Get.back(); // invites are answered on Home
    } else {
      PushService.openTarget(roomId: n.roomId, splitId: n.splitId);
    }
  }

  void markAllRead() => _repo.markAllRead(_auth.uid, items);
  void remove(AppNotification n) => _repo.delete(_auth.uid, n.id);
}

/// The in-app inbox: the same events that go out as push notifications.
class NotificationsView extends GetView<NotificationsController> {
  const NotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          Obx(() => controller.hasUnread
              ? TextButton(onPressed: controller.markAllRead, child: const Text('Mark all read'))
              : const SizedBox.shrink()),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Narrow(
          child: Obx(() {
            if (!controller.loaded.value) return const Center(child: CircularProgressIndicator());
            if (controller.items.isEmpty) {
              return const EmptyState(
                icon: Icons.notifications_none,
                title: "You're all caught up",
                message: 'New bills, payments to confirm and reminders will show up here.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: controller.items.length,
              itemBuilder: (context, i) => _Tile(n: controller.items[i]),
            );
          }),
        ),
      ),
    );
  }
}

class _Tile extends GetView<NotificationsController> {
  const _Tile({required this.n});
  final AppNotification n;

  (IconData, Color, Color) _style(BuildContext context) {
    final c = StatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return switch (n.type) {
      'share_confirmed' || 'share_paid_direct' || 'split_settled' || 'join_approved' => (Icons.check_rounded, c.owed, c.owedContainer),
      'share_marked' || 'join_request' || 'reminder' => (Icons.hourglass_top_rounded, c.pending, c.pendingContainer),
      'share_rejected' || 'share_undone' || 'overdue' || 'removed' || 'join_declined' => (Icons.error_outline, c.owe, c.oweContainer),
      'invite' || 'member_joined' => (Icons.mail_outline, scheme.onPrimaryContainer, scheme.primaryContainer),
      _ => (Icons.receipt_long_outlined, scheme.onPrimaryContainer, scheme.primaryContainer),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, background) = _style(context);
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => controller.remove(n),
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      child: InkWell(
        onTap: () => controller.open(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 19, backgroundColor: background, child: Icon(icon, size: 20, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  n.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: n.read ? FontWeight.w500 : FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(n.body, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  Dates.ago(n.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
            if (!n.read)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 6),
                child: Semantics(
                  label: 'Unread',
                  child: CircleAvatar(radius: 4.5, backgroundColor: theme.colorScheme.primary),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
