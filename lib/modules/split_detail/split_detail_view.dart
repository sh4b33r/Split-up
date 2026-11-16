import 'package:flutter/material.dart' hide Split;
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/routes/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/utils/split_calculator.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../activity/activity_view.dart';
import '../room/room_scope.dart';

class SplitDetailController extends RoomScope {
  SplitDetailController(super.roomId, this.splitId);
  final String splitId;

  final split = Rxn<Split>();
  final shares = <Share>[].obs;
  final history = <Activity>[].obs;
  final loaded = false.obs;
  bool _closing = false;

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<SplitRepo>().split(roomId, splitId), (s) {
      loaded.value = true;
      if (s == null && !_closing) {
        // Deleted while we were looking at it.
        _closing = true;
        if (Get.currentRoute == Routes.split(roomId, splitId)) Get.back();
        return;
      }
      split.value = s;
    });
    watch(Get.find<ShareRepo>().shares(roomId, splitId), shares.assignAll);
    watch(Get.find<RoomRepo>().activity(roomId, splitId: splitId, limit: 50), history.assignAll);
  }

  // ---- what the signed-in user may do (the server checks all of it again) ----

  /// Owner, admin, split creator or payer: confirm, reject, mark paid directly.
  bool get canSettle {
    final s = split.value;
    return s != null && (isManager || s.createdBy == uid || s.paidBy == uid);
  }

  /// Owner, admin or split creator: undo a Paid share.
  bool get canUndo {
    final s = split.value;
    return s != null && (isManager || s.createdBy == uid);
  }

  bool get canEdit {
    final s = split.value;
    if (s == null) return false;
    return s.hasPayments ? isManager : (isManager || s.createdBy == uid);
  }

  bool get canDelete {
    final s = split.value;
    return s != null && !s.hasPayments && (isManager || s.createdBy == uid);
  }

  /// Payer first, then people who still owe, then the rest.
  List<Share> get ordered {
    final payer = split.value?.paidBy;
    int rank(Share s) => s.userId == payer
        ? 0
        : switch (s.status) { ShareStatus.markedPaid => 1, ShareStatus.unpaid => 2, ShareStatus.paid => 3 };
    return shares.toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : member(a.userId).displayName.compareTo(member(b.userId).displayName);
      });
  }

  // ---- actions ---------------------------------------------------------------

  Future<void> iPaid() async {
    final s = split.value;
    final mine = shares.firstWhereOrNull((x) => x.userId == uid);
    if (s == null || mine == null) return;
    await Get.bottomSheet<void>(
      MarkPaidSheet(c: this, share: mine, payerName: member(s.paidBy).displayName),
      isScrollControlled: true,
    );
  }

  Future<void> confirm(Share s) => Ui.attempt(
        () => api.confirmShare(roomId, splitId, s.userId),
        busy: busy,
        success: "Confirmed ${member(s.userId).displayName}'s payment",
      );

  Future<void> reject(Share s) async {
    final reason = await Ui.prompt(
      title: 'Reject this payment?',
      message: "${member(s.userId).displayName}'s share goes back to unpaid and they are told why.",
      hint: 'e.g. Not received yet',
      confirmLabel: 'Reject',
    );
    if (reason == null) return;
    await Ui.attempt(() => api.rejectShare(roomId, splitId, s.userId, reason), busy: busy, success: 'Payment rejected');
  }

  Future<void> markDirect(Share s) async {
    final name = member(s.userId).displayName;
    final ok = await Ui.confirm(
      title: "Mark $name's share as paid?",
      message: 'Use this when they have paid ${Money.format(s.amountMinor, s.currency)} in person, for example in cash.',
      confirmLabel: 'Mark paid',
    );
    if (ok) await Ui.attempt(() => api.markPaidDirect(roomId, splitId, s.userId), busy: busy, success: "$name's share is paid");
  }

  Future<void> undo(Share s) async {
    final name = member(s.userId).displayName;
    final ok = await Ui.confirm(
      title: 'Undo this payment?',
      message: "$name's share goes back to unpaid and they are notified.",
      confirmLabel: 'Undo',
      destructive: true,
    );
    if (ok) await Ui.attempt(() => api.undoPaid(roomId, splitId, s.userId), busy: busy, success: 'Moved back to unpaid');
  }

  Future<void> delete() async {
    final s = split.value;
    if (s == null) return;
    final ok = await Ui.confirm(
      title: 'Delete "${s.label}"?',
      message: 'Everyone on this split is notified and nobody owes anything for it any more.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    _closing = true;
    final done = await Ui.attempt(() async {
      await api.deleteSplit(roomId, splitId);
      return true;
    }, busy: busy);
    if (done == true) {
      Get.back();
      Ui.toast('Split deleted');
    } else {
      _closing = false;
    }
  }
}

class SplitDetailView extends StatelessWidget {
  const SplitDetailView({super.key, required this.roomId, required this.splitId});
  final String roomId;
  final String splitId;

  @override
  Widget build(BuildContext context) {
    return Scoped<SplitDetailController>(
      create: () => SplitDetailController(roomId, splitId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(
          title: const Text('Split'),
          actions: [
            Obx(() => c.canEdit
                ? IconButton(
                    tooltip: 'Edit split',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Get.toNamed(Routes.splitEdit(roomId, splitId)),
                  )
                : const SizedBox.shrink()),
            Obx(() => c.canDelete
                ? IconButton(tooltip: 'Delete split', icon: const Icon(Icons.delete_outline), onPressed: c.delete)
                : const SizedBox.shrink()),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Narrow(
            child: Obx(() {
              final s = c.split.value;
              c.members.length; // names update when members load
              c.room.value;
              if (s == null) {
                return c.loaded.value
                    ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Split not found', message: 'It may have been deleted.')
                    : const Center(child: CircularProgressIndicator());
              }
              final mine = c.shares.firstWhereOrNull((x) => x.userId == c.uid);
              final iOwe = mine != null && !mine.isPayerShare && mine.status == ShareStatus.unpaid;
              return Column(children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _Header(c: c, split: s),
                      const SectionTitle('Who owes what'),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (final (i, share) in c.ordered.indexed) ...[
                            if (i > 0) const Divider(indent: 16, endIndent: 16),
                            _ShareRow(c: c, split: s, share: share),
                          ],
                        ]),
                      ),
                      if (c.history.isNotEmpty) ...[
                        const SectionTitle('History'),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(children: [
                            for (final a in c.history) ActivityTile(activity: a, currency: s.currency, withSplit: false),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
                if (iOwe)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: BusyButton(
                      label: "I've paid ${Money.format(mine.amountMinor, s.currency)}",
                      icon: Icons.check_rounded,
                      busy: c.busy.value,
                      onPressed: c.iPaid,
                    ),
                  ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c, required this.split});
  final SplitDetailController c;
  final Split split;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final payer = c.member(split.paidBy);
    final total = split.shareSummary.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (split.settled)
              StatusChip.settled(context)
            else if (split.isOverdue)
              StatusChip.overdue(context)
            else
              StatusChip.neutral(context, '${split.paidCount} of $total paid'),
            if (split.dueDate != null && !split.settled)
              StatusChip.neutral(context, 'Due ${Dates.short(split.dueDate!)}', icon: Icons.event),
            if (split.isRecurring) StatusChip.neutral(context, 'Monthly', icon: Icons.event_repeat),
          ]),
          const SizedBox(height: 12),
          Text(split.label, style: theme.textTheme.titleLarge),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: [
            TextSpan(
              text: Money.number(split.totalMinor, split.currency),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            TextSpan(text: ' ${split.currency}', style: theme.textTheme.titleMedium?.copyWith(color: muted)),
          ])),
          const SizedBox(height: 12),
          Row(children: [
            Avatar(name: payer.displayName, photoUrl: payer.photoUrl, radius: 14),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${c.nameOf(split.paidBy)} paid · split ${split.splitType == SplitType.equal ? 'equally' : 'by ${split.splitType.label.toLowerCase()}'}',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
          ]),
          if (split.note != null && split.note!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              child: Text(split.note!),
            ),
          ],
          if (split.receiptUrl != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => showPhoto(split.receiptUrl!, 'Receipt'),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View receipt'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Opens a receipt or payment-proof photo full screen.
void showPhoto(String url, String title) {
  Get.dialog<void>(Dialog(
    clipBehavior: Clip.antiAlias,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Get.textTheme.titleMedium)),
          IconButton(tooltip: 'Close', onPressed: () => Get.back<void>(), icon: const Icon(Icons.close)),
        ]),
      ),
      Flexible(
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            semanticLabel: title,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
            errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(32), child: Text("Couldn't load the photo.")),
          ),
        ),
      ),
    ]),
  ));
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.c, required this.split, required this.share});
  final SplitDetailController c;
  final Split split;
  final Share share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final m = c.member(share.userId);
    final mine = share.userId == c.uid;
    final amount = Money.format(share.amountMinor, share.currency);
    final payerName = c.nameOf(split.paidBy) == 'You' ? 'you' : c.nameOf(split.paidBy);
    final who = mine ? 'You' : m.displayName;

    // "Rahul owes Aj 1,000 QAR", "Aj paid the bill", ...
    final String line;
    if (share.isPayerShare) {
      line = '${mine ? 'You' : m.displayName} paid the bill · own share $amount';
    } else {
      line = switch (share.status) {
        ShareStatus.unpaid => '$who ${mine ? 'owe' : 'owes'} $payerName $amount',
        ShareStatus.markedPaid => '$who ${mine ? 'say you' : 'says they'} paid $payerName $amount',
        ShareStatus.paid => '$who paid $payerName $amount',
      };
    }
    final method = share.methodLabel;
    final details = [
      if (!share.isPayerShare && share.status != ShareStatus.unpaid && method.isNotEmpty) method,
      if (share.status == ShareStatus.markedPaid && share.markedAt != null) Dates.ago(share.markedAt),
      if (share.status != ShareStatus.unpaid && (share.note ?? '').isNotEmpty) '“${share.note}”',
    ].join(' · ');

    final actions = <Widget>[
      if (share.proofUrl != null && share.status != ShareStatus.unpaid)
        TextButton(onPressed: () => showPhoto(share.proofUrl!, 'Payment proof'), child: const Text('View proof')),
      if (!share.isPayerShare && share.status == ShareStatus.markedPaid && c.canSettle) ...[
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () => c.reject(share),
          child: const Text('Reject'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () => c.confirm(share),
          child: const Text('Confirm'),
        ),
      ],
      if (!share.isPayerShare && share.status == ShareStatus.unpaid && c.canSettle && !mine)
        TextButton(onPressed: () => c.markDirect(share), child: const Text('Mark paid')),
      if (!share.isPayerShare && share.status == ShareStatus.paid && c.canUndo)
        TextButton(onPressed: () => c.undo(share), child: const Text('Undo')),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, actions.isEmpty ? 12 : 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(name: m.displayName, photoUrl: m.photoUrl, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
              if (details.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(details, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ),
              if (share.status == ShareStatus.unpaid && (share.rejectReason ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Rejected: “${share.rejectReason}”',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.owe, fontWeight: FontWeight.w600),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          share.isPayerShare
              ? StatusChip.neutral(context, 'Payer')
              : StatusChip.share(context, share.status, overdue: share.isOverdue),
        ]),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
            ),
          ),
      ]),
    );
  }
}

/// "I've paid": how, an optional note and an optional screenshot.
class MarkPaidSheet extends StatefulWidget {
  const MarkPaidSheet({super.key, required this.c, required this.share, required this.payerName});
  final SplitDetailController c;
  final Share share;
  final String payerName;

  @override
  State<MarkPaidSheet> createState() => _MarkPaidSheetState();
}

class _MarkPaidSheetState extends State<MarkPaidSheet> {
  static const _methods = {'cash': 'Cash', 'bank_transfer': 'Bank transfer', 'other': 'Other'};

  final _note = TextEditingController();
  String _method = 'cash';
  XFile? _proof;
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await Ui.attempt(() => Get.find<StorageService>().pick());
    if (file != null) setState(() => _proof = file);
  }

  Future<void> _submit() async {
    final c = widget.c;
    setState(() => _busy = true);
    final done = await Ui.attempt(() async {
      String? proofUrl;
      if (_proof != null) {
        proofUrl = await Get.find<StorageService>().uploadRoomPhoto(c.roomId, 'proofs', c.uid, _proof!);
      }
      await c.api.markPaid(
        c.roomId,
        c.splitId,
        method: _method,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        proofUrl: proofUrl,
      );
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (done == true) {
      Get.back<void>();
      Ui.toast('Marked as paid. ${widget.payerName} will confirm it.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Mark as paid', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${Money.format(widget.share.amountMinor, widget.share.currency)} to ${widget.payerName} for ${widget.share.label}',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Text('How did you pay?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final e in _methods.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _method == e.key,
                onSelected: (_) => setState(() => _method = e.key),
              ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
          ),
          const SizedBox(height: 10),
          _proof == null
              ? TextButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add a screenshot or photo'),
                )
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: Text(_proof!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Remove photo',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _proof = null),
                  ),
                ),
          const SizedBox(height: 10),
          BusyButton(label: "I've paid", busy: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
