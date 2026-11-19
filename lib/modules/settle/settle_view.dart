import 'package:flutter/material.dart' hide Split;
import 'package:get/get.dart';

import '../../app/theme/app_theme.dart';
import '../../core/utils/debts.dart';
import '../../core/utils/money.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../room/room_scope.dart';

class SettleController extends RoomScope {
  SettleController(super.roomId);

  final splits = <Split>[].obs;
  final loaded = false.obs;
  final busyWith = RxnString();

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<SplitRepo>().splits(roomId), (v) {
      splits.assignAll(v);
      loaded.value = true;
    }, onError: (_) => loaded.value = true);
  }

  List<PairBalance> get pairs => Debts.pairsFor(uid, splits);

  /// Fewest payments that settle the whole room, from everyone's balance.
  List<Transfer> get plan => Debts.simplify({for (final m in members) m.uid: m.netMinor});

  Future<void> settleWith(PairBalance p) async {
    final name = member(p.otherId).displayName;
    String? method = 'cash';
    if (p.net < 0) {
      method = await Get.bottomSheet<String>(_MethodSheet(name: name, amount: Money.format(-p.net, currency)));
      if (method == null) return;
    } else {
      final ok = await Ui.confirm(
        title: p.net > 0 ? 'Got ${Money.format(p.net, currency)} from $name?' : 'Clear everything with $name?',
        message: p.net > 0
            ? 'All ${p.bills} open bills between you are marked as settled. Anything you owe them is sent to them to confirm.'
            : 'What you owe each other cancels out, so no money changes hands.',
        confirmLabel: p.net > 0 ? 'Yes, received' : 'Settle up',
      );
      if (!ok) return;
    }
    busyWith.value = p.otherId;
    final net = await Ui.attempt(() => api.settleUp(roomId, p.otherId, method: method!));
    busyWith.value = null;
    if (net == null) return;
    if (net > 0) {
      Ui.toast('Sent! $name will confirm your ${Money.format(net, currency)}.');
    } else {
      Confetti.burst(Get.context!);
      Ui.toast('All square with $name');
    }
  }

  Future<void> confirmAll(PairBalance p) async {
    final name = member(p.otherId).displayName;
    busyWith.value = p.otherId;
    final n = await Ui.attempt(() => api.confirmAll(roomId, p.otherId));
    busyWith.value = null;
    if (n != null) {
      Confetti.burst(Get.context!);
      Ui.toast("Confirmed $name's payment${n == 1 ? '' : 's'}");
    }
  }
}

class SettleView extends StatelessWidget {
  const SettleView({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scoped<SettleController>(
      create: () => SettleController(roomId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(title: const Text('Settle up')),
        body: SafeArea(
          child: Narrow(
            child: Obx(() {
              c.members.length;
              if (!c.loaded.value) return const SkeletonList(count: 3);
              final pairs = c.pairs;
              final plan = c.plan;
              final myNet = c.member(c.uid).netMinor;
              var i = 0;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                children: [
                  _Summary(c: c, net: myNet).enter(context, index: i++),
                  if (pairs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        children: [
                          FloatingIcon(
                            child: Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                gradient: Brand.hero(context),
                                shape: BoxShape.circle,
                                boxShadow: Brand.glow(context),
                              ),
                              child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
                            ),
                          ).pop(context),
                          const SizedBox(height: 16),
                          Text("You're all square", style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text(
                            'Nobody in this room owes you, and you owe nobody.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const SectionTitle('Between you and…'),
                    for (final p in pairs) _PairCard(c: c, p: p).enter(context, index: i++),
                  ],
                  if (plan.isNotEmpty) ...[
                    const SectionTitle('Fewest payments for everyone'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (final (k, t) in plan.indexed) _TransferRow(c: c, t: t).enter(context, index: i + k),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                      child: Text(
                        '${plan.length == 1 ? 'If this one payment were made' : 'If everyone made these ${plan.length} payments'}, '
                        'the whole room would be settled. Settle up above to record what you pay or receive.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.c, required this.net});
  final SettleController c;
  final int net;

  @override
  Widget build(BuildContext context) {
    return HeroPanel(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
            child: const Icon(Icons.handshake_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  net == 0 ? 'Your balance' : (net > 0 ? 'In total you get back' : 'In total you owe'),
                  style: TextStyle(color: Brand.onHeroMuted, fontWeight: FontWeight.w600),
                ),
                MoneyCountUp(
                  minor: net,
                  currency: c.currency,
                  absolute: true,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                  currencyStyle: TextStyle(color: Brand.onHeroMuted, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({required this.c, required this.p});
  final SettleController c;
  final PairBalance p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final m = c.member(p.otherId);
    final cur = c.currency;
    final net = p.net;
    final color = net == 0 ? theme.colorScheme.onSurfaceVariant : (net > 0 ? colors.owed : colors.owe);
    final headline = net == 0
        ? 'You and ${m.displayName} are even'
        : (net > 0 ? '${m.displayName} owes you' : 'You owe ${m.displayName}');
    final details = [
      '${p.bills} open bill${p.bills == 1 ? '' : 's'}',
      if (p.iOwe > 0 && p.theyOwe > 0) 'you owe ${Money.format(p.iOwe, cur)}, they owe ${Money.format(p.theyOwe, cur)}',
      if (p.waiting > 0) '${Money.format(p.waiting, cur)} waiting for them to confirm',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(name: m.displayName, photoUrl: m.photoUrl, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(headline, style: theme.textTheme.titleSmall),
                        if (net != 0)
                          MoneyCountUp(
                            minor: net.abs(),
                            currency: cur,
                            style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(details, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Obx(() {
                final busy = c.busyWith.value == p.otherId;
                final fullyWaiting = net < 0 && p.waiting == p.iOwe && p.theyOwe == 0;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (p.toConfirm > 0)
                      PressScale(
                        child: FilledButton.tonalIcon(
                          onPressed: busy ? null : () => c.confirmAll(p),
                          icon: const Icon(Icons.done_all_rounded, size: 18),
                          label: Text('Confirm ${Money.format(p.toConfirm, cur)}'),
                        ),
                      ),
                    if (!fullyWaiting)
                      PressScale(
                        child: FilledButton.icon(
                          onPressed: busy ? null : () => c.settleWith(p),
                          icon: busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Icon(net < 0 ? Icons.send_rounded : Icons.handshake_rounded, size: 18),
                          label: Text(
                            net < 0 ? 'Pay ${Money.format(-net, cur)}' : (net > 0 ? 'Mark as received' : 'Clear bills'),
                          ),
                        ),
                      )
                    else
                      StatusChip(
                        label: 'Waiting for ${m.displayName}',
                        color: colors.pending,
                        background: colors.pendingContainer,
                        icon: Icons.hourglass_top_rounded,
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

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.c, required this.t});
  final SettleController c;
  final Transfer t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = c.member(t.from), to = c.member(t.to);
    final involvesMe = t.from == c.uid || t.to == c.uid;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Avatar(name: from.displayName, photoUrl: from.photoUrl, radius: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  Text(
                    Money.format(t.amountMinor, c.currency),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: involvesMe ? theme.colorScheme.primary : null,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(child: Container(height: 2, color: theme.colorScheme.outlineVariant)),
                      Icon(Icons.arrow_forward_rounded, size: 16, color: theme.colorScheme.outline),
                    ],
                  ),
                  Text(
                    '${c.nameOf(t.from)} → ${c.nameOf(t.to)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Avatar(name: to.displayName, photoUrl: to.photoUrl, radius: 16),
        ],
      ),
    );
  }
}

class _MethodSheet extends StatefulWidget {
  const _MethodSheet({required this.name, required this.amount});
  final String name;
  final String amount;

  @override
  State<_MethodSheet> createState() => _MethodSheetState();
}

class _MethodSheetState extends State<_MethodSheet> {
  static const _methods = {
    'cash': ('Cash', Icons.payments_rounded),
    'bank_transfer': ('Bank transfer', Icons.account_balance_rounded),
    'other': ('Other', Icons.more_horiz_rounded),
  };
  String _method = 'bank_transfer';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay ${widget.name} ${widget.amount}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Clears every open bill between you. ${widget.name} confirms when the money arrives.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            for (final e in _methods.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _MethodTile(
                  icon: e.value.$2,
                  label: e.value.$1,
                  selected: _method == e.key,
                  onTap: () => setState(() => _method = e.key),
                ),
              ),
            const SizedBox(height: 8),
            BusyButton(
              label: "I've paid ${widget.amount}",
              icon: Icons.send_rounded,
              onPressed: () => Get.back(result: _method),
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable row with an animated border, used for payment methods.
class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer.withValues(alpha: 0.6) : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              AnimatedScale(
                scale: selected ? 1 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Icon(Icons.check_circle_rounded, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
