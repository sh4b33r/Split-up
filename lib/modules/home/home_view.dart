import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../../app/routes/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/services/api.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/deep_link_service.dart';
import '../../core/services/push_service.dart';
import '../../core/utils/live_controller.dart';
import '../../core/utils/money.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

class HomeController extends LiveController {
  final AuthService auth = Get.find();
  final Api _api = Get.find();

  final rooms = <Room>[].obs;
  final roomsLoaded = false.obs;
  final owe = <Share>[].obs;
  final owed = <Share>[].obs;
  final invites = <Invite>[].obs;
  final unread = 0.obs;
  final busyInvite = RxnString();
  final verifying = false.obs;
  StreamSubscription<List<Invite>>? _inviteSub;

  @override
  void onInit() {
    super.onInit();
    final uid = auth.uid;
    watch(Get.find<RoomRepo>().myRooms(uid), (v) {
      rooms.assignAll(v);
      roomsLoaded.value = true;
    }, onError: (_) => roomsLoaded.value = true);
    watch(Get.find<ShareRepo>().iOwe(uid), owe.assignAll);
    watch(Get.find<ShareRepo>().owedToMe(uid), owed.assignAll);
    watch(Get.find<NotificationRepo>().inbox(uid), (v) => unread.value = v.where((n) => !n.read).length);
    _watchInvites();
    ever<bool>(auth.emailVerified, (_) => _watchInvites());
  }

  @override
  void onReady() {
    super.onReady();
    // A link or notification that arrived before sign-in finished.
    Get.find<DeepLinkService>().flushPending();
    Get.find<PushService>().flushPending();
  }

  /// Email invites are only readable once the address is verified.
  void _watchInvites() {
    _inviteSub?.cancel();
    final email = auth.email;
    if (email == null || !auth.emailVerified.value) {
      invites.clear();
      return;
    }
    _inviteSub = watch(Get.find<InviteRepo>().pendingFor(email), invites.assignAll);
  }

  bool get needsVerification => auth.email != null && !auth.emailVerified.value;

  /// Totals per currency, because rooms can use different currencies.
  Map<String, int> _totals(List<Share> shares) {
    final out = <String, int>{};
    for (final s in shares) {
      out[s.currency] = (out[s.currency] ?? 0) + s.amountMinor;
    }
    return out;
  }

  Map<String, int> get oweTotals => _totals(owe);
  Map<String, int> get owedTotals => _totals(owed);

  /// Shares other people marked as paid and I still have to confirm.
  List<Share> get toConfirm => owed.where((s) => s.status == ShareStatus.markedPaid).toList();

  /// My balance in one room: what I'm owed minus what I owe.
  int netIn(String roomId) =>
      owed.where((s) => s.roomId == roomId).fold<int>(0, (a, s) => a + s.amountMinor) -
      owe.where((s) => s.roomId == roomId).fold<int>(0, (a, s) => a + s.amountMinor);

  Future<void> respond(Invite invite, bool accept) async {
    if (busyInvite.value != null) return;
    busyInvite.value = invite.id;
    try {
      final roomId = await _api.respondInvite(invite.id, accept: accept);
      if (accept && roomId != null) {
        Ui.toast('You joined ${invite.roomName}');
        Get.toNamed(Routes.room(roomId));
      }
    } catch (e) {
      Ui.toast(Ui.messageOf(e), error: true);
    } finally {
      busyInvite.value = null;
    }
  }

  Future<void> resendVerification() =>
      Ui.attempt(auth.sendVerificationEmail, success: 'Verification email sent to ${auth.email}');

  Future<void> checkVerification() async {
    verifying.value = true;
    final ok = await auth.refreshVerification();
    verifying.value = false;
    Ui.toast(ok ? 'Email verified' : "Not verified yet. Tap the link in the email first.", error: !ok);
  }
}

class HomeView extends GetView<HomeController> {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          Obx(() => IconButton(
                tooltip: 'Notifications',
                onPressed: () => Get.toNamed(Routes.notifications),
                icon: Badge(
                  isLabelVisible: controller.unread.value > 0,
                  label: Text('${controller.unread.value}'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              )),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: Obx(() => Semantics(
                  button: true,
                  label: 'Your profile',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Get.toNamed(Routes.profile),
                    child: Avatar(
                      name: controller.auth.displayName,
                      photoUrl: controller.auth.profile.value?.photoUrl,
                      radius: 17,
                    ),
                  ),
                )),
          ),
        ],
      ),
      body: SafeArea(
        child: Narrow(
          child: Obx(() {
            final rooms = controller.rooms;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
                  child: Text(
                    'Hi ${controller.auth.displayName.split(' ').first}',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                if (controller.needsVerification) const _VerifyBanner(),
                _Totals(owe: controller.oweTotals, owed: controller.owedTotals),
                if (controller.toConfirm.isNotEmpty) ...[
                  const SectionTitle('Waiting for your confirmation'),
                  for (final s in controller.toConfirm) _ConfirmTile(share: s),
                ],
                if (controller.invites.isNotEmpty) ...[
                  const SectionTitle('Invites'),
                  for (final i in controller.invites) _InviteCard(invite: i),
                ],
                SectionTitle('Your rooms', trailing: rooms.isEmpty ? null : Text('${rooms.length}')),
                if (!controller.roomsLoaded.value)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (rooms.isEmpty)
                  const _NoRooms()
                else
                  for (final r in rooms) _RoomTile(room: r, net: controller.netIn(r.id)),
              ],
            );
          }),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 608),
          child: Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => Get.toNamed(Routes.join),
                icon: const Icon(Icons.login),
                label: const Text('Join room'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Get.toNamed(Routes.createRoom),
                icon: const Icon(Icons.add),
                label: const Text('New room'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.owe, required this.owed});
  final Map<String, int> owe;
  final Map<String, int> owed;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _TotalCard(label: 'You owe', totals: owe, color: c.owe, background: c.oweContainer, icon: Icons.north_east)),
        const SizedBox(width: 12),
        Expanded(child: _TotalCard(label: "You're owed", totals: owed, color: c.owed, background: c.owedContainer, icon: Icons.south_west)),
      ]),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.label, required this.totals, required this.color, required this.background, required this.icon});
  final String label;
  final Map<String, int> totals;
  final Color color;
  final Color background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = totals.entries.where((e) => e.value != 0).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
        ]),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          Text('Nothing', style: theme.textTheme.titleLarge?.copyWith(color: color))
        else
          for (final e in lines)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: Money.number(e.value, e.key),
                  style: theme.textTheme.headlineSmall?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                TextSpan(text: ' ${e.key}', style: theme.textTheme.labelLarge?.copyWith(color: color)),
              ])),
            ),
      ]),
    );
  }
}

class _VerifyBanner extends GetView<HomeController> {
  const _VerifyBanner();

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(color: c.pendingContainer, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.mark_email_unread_outlined, color: c.pending),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verify ${controller.auth.email} to receive room invites sent to your email.',
              style: TextStyle(color: c.pending, fontWeight: FontWeight.w500),
            ),
          ),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: controller.resendVerification, child: const Text('Resend email')),
          Obx(() => TextButton(
                onPressed: controller.verifying.value ? null : controller.checkVerification,
                child: const Text("I've verified"),
              )),
        ]),
      ]),
    );
  }
}

class _ConfirmTile extends StatelessWidget {
  const _ConfirmTile({required this.share});
  final Share share;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => Get.toNamed(Routes.split(share.roomId, share.splitId)),
          leading: CircleAvatar(backgroundColor: c.pendingContainer, child: Icon(Icons.hourglass_top, color: c.pending, size: 20)),
          title: Text(share.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${Money.format(share.amountMinor, share.currency)} marked as paid'),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}

class _InviteCard extends GetView<HomeController> {
  const _InviteCard({required this.invite});
  final Invite invite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _RoomIcon(icon: invite.roomIcon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(invite.roomName, style: theme.textTheme.titleMedium),
                  Text(
                    '${invite.invitedByName} invited you',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Obx(() {
              final busy = controller.busyInvite.value == invite.id;
              return Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => controller.respond(invite, false),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => controller.respond(invite, true),
                    child: Text(busy ? 'Joining…' : 'Accept'),
                  ),
                ),
              ]);
            }),
          ]),
        ),
      ),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({required this.icon});
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(icon, style: const TextStyle(fontSize: 24)),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.net});
  final Room room;
  final int net;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = StatusColors.of(context);
    final people = '${room.memberIds.length} ${room.memberIds.length == 1 ? 'person' : 'people'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Get.toNamed(Routes.room(room.id)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              _RoomIcon(icon: room.icon),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(room.name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '$people · ${room.currency}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  net == 0 ? 'All settled' : (net < 0 ? 'You owe' : "You're owed"),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: net == 0 ? theme.colorScheme.onSurfaceVariant : (net < 0 ? c.owe : c.owed),
                  ),
                ),
                if (net != 0)
                  Text(
                    Money.format(net.abs(), room.currency),
                    style: theme.textTheme.titleSmall?.copyWith(color: net < 0 ? c.owe : c.owed),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NoRooms extends StatelessWidget {
  const _NoRooms();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Icon(Icons.meeting_room_outlined, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('No rooms yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Create a room for your flat, trip or team, or join one with a 6-character room code.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}
