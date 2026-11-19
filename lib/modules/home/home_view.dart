import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../../app/routes/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/widgets/motion.dart';
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

  /// The currency to headline: the one with the most money moving.
  String get mainCurrency {
    final all = {...oweTotals.keys, ...owedTotals.keys};
    if (all.isEmpty) return rooms.isNotEmpty ? rooms.first.currency : AppConfig.defaultCurrency;
    return all.reduce(
      (a, b) => ((oweTotals[a] ?? 0) + (owedTotals[a] ?? 0)) >= ((oweTotals[b] ?? 0) + (owedTotals[b] ?? 0)) ? a : b,
    );
  }

  int get mainNet => (owedTotals[mainCurrency] ?? 0) - (oweTotals[mainCurrency] ?? 0);

  /// Other currencies with money moving, e.g. "+ 120 USD".
  List<String> get otherCurrencyLines => [
    for (final c in {...oweTotals.keys, ...owedTotals.keys})
      if (c != mainCurrency) Money.format((owedTotals[c] ?? 0) - (oweTotals[c] ?? 0), c),
  ];

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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Narrow(
          child: Obx(() {
            final rooms = controller.rooms;
            final name = controller.auth.displayName.split(' ').first;
            var i = 0;
            return ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(),
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          Text(
                            'Hi $name 👋',
                            style: theme.textTheme.headlineSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () => Get.toNamed(Routes.notifications),
                      icon: Badge(
                        isLabelVisible: controller.unread.value > 0,
                        label: Text('${controller.unread.value}'),
                        child: const Icon(Icons.notifications_none_rounded, size: 26),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      button: true,
                      label: 'Your profile',
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Get.toNamed(Routes.profile),
                        child: Hero(
                          tag: 'me-avatar',
                          child: Avatar(
                            name: controller.auth.displayName,
                            photoUrl: controller.auth.profile.value?.photoUrl,
                            radius: 21,
                          ),
                        ),
                      ),
                    ),
                  ],
                ).enter(context, index: i++),
                const SizedBox(height: 18),
                _BalanceCard(c: controller).enter(context, index: i++),
                if (controller.needsVerification) ...[
                  const SizedBox(height: 14),
                  const _VerifyBanner().enter(context, index: i++),
                ],
                if (controller.toConfirm.isNotEmpty) ...[
                  SectionTitle(
                    'Waiting for your confirmation',
                    trailing: StatusChip.neutral(context, '${controller.toConfirm.length}').pop(context),
                  ),
                  for (final s in controller.toConfirm) _ConfirmTile(share: s).enter(context, index: i++),
                ],
                if (controller.invites.isNotEmpty) ...[
                  const SectionTitle('Invites'),
                  for (final inv in controller.invites) _InviteCard(invite: inv).enter(context, index: i++),
                ],
                SectionTitle('Your rooms', trailing: rooms.isEmpty ? null : Text('${rooms.length}')),
                if (!controller.roomsLoaded.value)
                  for (var k = 0; k < 3; k++)
                    const Padding(padding: EdgeInsets.only(bottom: 10), child: SkeletonCard(height: 80))
                else if (rooms.isEmpty)
                  const _NoRooms().enter(context, index: i++)
                else
                  for (final r in rooms) _RoomTile(room: r, net: controller.netIn(r.id)).enter(context, index: i++),
              ],
            );
          }),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Narrow(
          shrink: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: PressScale(
                    child: FilledButton.tonalIcon(
                      onPressed: () => Get.toNamed(Routes.join),
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('Join room'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressScale(
                    child: FilledButton.icon(
                      onPressed: () => Get.toNamed(Routes.createRoom),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New room'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).enter(context, dy: 0.4, delay: const Duration(milliseconds: 200)),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.c});
  final HomeController c;

  @override
  Widget build(BuildContext context) {
    final net = c.mainNet;
    final cur = c.mainCurrency;
    final label = net == 0 ? "You're all square" : (net > 0 ? 'Overall, you get back' : 'Overall, you owe');
    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                color: Brand.onHeroMuted,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(color: Brand.onHeroMuted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MoneyCountUp(
            minor: net,
            currency: cur,
            absolute: true,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              height: 1.1,
            ),
            currencyStyle: TextStyle(color: Brand.onHeroMuted, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (c.otherCurrencyLines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'and ${c.otherCurrencyLines.join(' · ')}',
                style: TextStyle(color: Brand.onHeroMuted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: HeroPill(
                  icon: Icons.north_east_rounded,
                  label: 'You owe',
                  value: MoneyCountUp(minor: c.oweTotals[cur] ?? 0, currency: cur),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: HeroPill(
                  icon: Icons.south_west_rounded,
                  label: "You're owed",
                  value: MoneyCountUp(minor: c.owedTotals[cur] ?? 0, currency: cur),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerifyBanner extends GetView<HomeController> {
  const _VerifyBanner();

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      decoration: BoxDecoration(color: c.pendingContainer, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mark_email_unread_outlined, color: c.pending),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Verify ${controller.auth.email} to receive room invites sent to your email.',
                  style: TextStyle(color: c.pending, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: controller.resendVerification, child: const Text('Resend email')),
              Obx(
                () => TextButton(
                  onPressed: controller.verifying.value ? null : controller.checkVerification,
                  child: const Text("I've verified"),
                ),
              ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: TapCard(
        onTap: () => Get.toNamed(Routes.split(share.roomId, share.splitId)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: c.pendingContainer,
            child: Icon(Icons.hourglass_top_rounded, color: c.pending, size: 20),
          ),
          title: Text(
            share.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text('${Money.format(share.amountMinor, share.currency)} marked as paid · tap to confirm'),
          trailing: const Icon(Icons.chevron_right_rounded),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RoomIcon(icon: invite.roomIcon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(invite.roomName, style: theme.textTheme.titleMedium),
                        Text(
                          '${invite.invitedByName} invited you',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Obx(() {
                final busy = controller.busyInvite.value == invite.id;
                return Row(
                  children: [
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
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// A room's emoji on a soft tile. Give [heroTag] to fly it between screens.
class RoomIcon extends StatelessWidget {
  const RoomIcon({super.key, required this.icon, this.size = 50, this.heroTag});
  final String icon;
  final double size;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.primaryContainer.withValues(alpha: 0.55)],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(icon, style: TextStyle(fontSize: size * 0.5)),
    );
    if (heroTag == null) return tile;
    return Hero(
      tag: heroTag!,
      child: Material(type: MaterialType.transparency, child: tile),
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
    final color = net == 0 ? theme.colorScheme.onSurfaceVariant : (net < 0 ? c.owe : c.owed);
    final bg = net == 0 ? theme.colorScheme.surfaceContainerHighest : (net < 0 ? c.oweContainer : c.owedContainer);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapCard(
        onTap: () => Get.toNamed(Routes.room(room.id)),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            RoomIcon(icon: room.icon, heroTag: 'room-icon-${room.id}'),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.group_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        '$people · ${room.currency}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    net == 0 ? 'All settled' : (net < 0 ? 'You owe' : "You're owed"),
                    style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                  ),
                  if (net != 0)
                    MoneyCountUp(
                      minor: net.abs(),
                      currency: room.currency,
                      style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
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

class _NoRooms extends StatelessWidget {
  const _NoRooms();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
        child: Column(
          children: [
            FloatingIcon(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: Brand.hero(context),
                  shape: BoxShape.circle,
                  boxShadow: Brand.glow(context),
                ),
                child: const Icon(Icons.meeting_room_rounded, size: 34, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),
            Text('No rooms yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Create a room for your flat, trip or team, or join one with a 6-character room code.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
