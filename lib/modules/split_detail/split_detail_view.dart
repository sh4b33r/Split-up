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
import '../../core/widgets/motion.dart';
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
  final comments = <Comment>[].obs;
  final loaded = false.obs;
  final sending = false.obs;
  final commentText = TextEditingController();
  bool _closing = false;
  bool? _wasSettled;

  /// Called by the screen when the last share gets paid while it is open.
  VoidCallback? onSettled;

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
      if (s != null && _wasSettled == false && s.settled) onSettled?.call();
      _wasSettled = s?.settled;
      split.value = s;
    });
    watch(Get.find<SplitRepo>().comments(roomId, splitId), comments.assignAll);
    watch(Get.find<ShareRepo>().shares(roomId, splitId), shares.assignAll);
    watch(Get.find<RoomRepo>().activity(roomId, splitId: splitId, limit: 50), history.assignAll);
  }

  @override
  void onClose() {
    commentText.dispose();
    super.onClose();
  }

  Future<void> sendComment() async {
    final text = commentText.text.trim();
    if (text.isEmpty) return;
    final ok = await Ui.attempt(() async {
      await api.addComment(roomId, splitId, text);
      return true;
    }, busy: sending);
    if (ok == true) commentText.clear();
  }

  bool canDeleteComment(Comment c) => c.authorId == uid || isManager;

  Future<void> deleteComment(Comment c) async {
    final ok = await Ui.confirm(
      title: 'Delete this comment?',
      message: '“${c.text}”',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok) await Ui.attempt(() => api.deleteComment(roomId, splitId, c.id));
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
        : switch (s.status) {
            ShareStatus.markedPaid => 1,
            ShareStatus.unpaid => 2,
            ShareStatus.paid => 3,
          };
    return shares.toList()..sort((a, b) {
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
      message:
          'Use this when they have paid ${Money.format(s.amountMinor, s.currency)} in person, for example in cash.',
      confirmLabel: 'Mark paid',
    );
    if (!ok) return;
    await Ui.attempt(() => api.markPaidDirect(roomId, splitId, s.userId), busy: busy, success: "$name's share is paid");
  }

  Future<void> undo(Share s) async {
    final name = member(s.userId).displayName;
    final ok = await Ui.confirm(
      title: 'Undo this payment?',
      message: "$name's share goes back to unpaid and they are notified.",
      confirmLabel: 'Undo',
      destructive: true,
    );
    if (!ok) return;
    await Ui.attempt(() => api.undoPaid(roomId, splitId, s.userId), busy: busy, success: 'Moved back to unpaid');
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
      builder: (context, c) {
        c.onSettled ??= () {
          final ctx = Get.context;
          if (ctx != null) Confetti.burst(ctx);
        };
        return Scaffold(
          appBar: AppBar(
            title: const Text('Split'),
            actions: [
              Obx(
                () => c.canEdit
                    ? IconButton(
                        tooltip: 'Edit split',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Get.toNamed(Routes.splitEdit(roomId, splitId)),
                      )
                    : const SizedBox.shrink(),
              ),
              Obx(
                () => c.canDelete
                    ? IconButton(tooltip: 'Delete split', icon: const Icon(Icons.delete_outline), onPressed: c.delete)
                    : const SizedBox.shrink(),
              ),
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
                      ? const EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Split not found',
                          message: 'It may have been deleted.',
                        )
                      : const SkeletonList(count: 2, height: 160);
                }
                final mine = c.shares.firstWhereOrNull((x) => x.userId == c.uid);
                final iOwe = mine != null && !mine.isPayerShare && mine.status == ShareStatus.unpaid;
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _Header(c: c, split: s).enter(context),
                          const SectionTitle('Who owes what'),
                          Card(
                            clipBehavior: Clip.antiAlias,
                            child: AnimatedSize(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: Column(
                                children: [
                                  for (final (i, share) in c.ordered.indexed) ...[
                                    if (i > 0) const Divider(indent: 16, endIndent: 16),
                                    _ShareRow(
                                      key: ValueKey(share.userId),
                                      c: c,
                                      split: s,
                                      share: share,
                                    ).enter(context, index: i + 1),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SectionTitle('Comments', trailing: c.comments.isEmpty ? null : Text('${c.comments.length}')),
                          _Comments(c: c),
                          if (c.history.isNotEmpty) ...[
                            const SectionTitle('History'),
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  for (final a in c.history)
                                    ActivityTile(activity: a, currency: s.currency, withSplit: false),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _BottomBar(c: c, split: s, mine: iOwe ? mine : null),
                  ],
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

/// Comment box, plus "I've paid" when the user still owes on this bill.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.c, required this.split, required this.mine});
  final SplitDetailController c;
  final Split split;
  final Share? mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: c.commentText,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => c.sendComment(),
                  decoration: const InputDecoration(
                    hintText: 'Add a comment',
                    counterText: '',
                    isDense: true,
                    prefixIcon: Icon(Icons.chat_bubble_outline_rounded, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Obx(
                () => IconButton.filledTonal(
                  tooltip: 'Send comment',
                  onPressed: c.sending.value ? null : c.sendComment,
                  icon: c.sending.value
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
          if (mine != null) ...[
            const SizedBox(height: 10),
            BusyButton(
              label: "I've paid ${Money.format(mine!.amountMinor, split.currency)}",
              icon: Icons.check_rounded,
              busy: c.busy.value,
              onPressed: c.iPaid,
            ).enter(context, dy: 0.3),
          ],
        ],
      ),
    );
  }
}

class _Comments extends StatelessWidget {
  const _Comments({required this.c});
  final SplitDetailController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (c.comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'No comments yet. Ask a question or leave a note for everyone on this bill.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      );
    }
    return Column(
      children: [
        for (final (i, cm) in c.comments.indexed)
          Padding(
            key: ValueKey(cm.id),
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: cm.authorId == c.uid ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Avatar(name: cm.authorName, photoUrl: c.member(cm.authorId).photoUrl, radius: 15),
                const SizedBox(width: 8),
                Flexible(
                  child: GestureDetector(
                    onLongPress: c.canDeleteComment(cm) ? () => c.deleteComment(cm) : null,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
                      decoration: BoxDecoration(
                        color: cm.authorId == c.uid
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${cm.authorId == c.uid ? 'You' : cm.authorName} · ${Dates.ago(cm.createdAt)}',
                            style: theme.textTheme.labelSmall?.copyWith(color: muted, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(cm.text, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
                if (c.canDeleteComment(cm))
                  IconButton(
                    tooltip: 'Delete comment',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: () => c.deleteComment(cm),
                    icon: Icon(Icons.close_rounded, color: muted),
                  ),
              ],
            ),
          ).enter(context, index: i, dx: cm.authorId == c.uid ? 0.06 : -0.06, dy: 0),
      ],
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (split.settled)
                  StatusChip.settled(context)
                else if (split.isOverdue)
                  StatusChip.overdue(context)
                else
                  StatusChip.neutral(context, '${split.paidCount} of $total paid'),
                if (split.dueDate != null && !split.settled)
                  StatusChip.neutral(context, 'Due ${Dates.short(split.dueDate!)}', icon: Icons.event),
                if (split.isRecurring) StatusChip.neutral(context, 'Monthly', icon: Icons.event_repeat),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(split.label, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Hero(
                        tag: 'split-amount-${split.id}',
                        child: Material(
                          type: MaterialType.transparency,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: Money.number(split.totalMinor, split.currency),
                                    style: theme.textTheme.displaySmall?.copyWith(
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${split.currency}',
                                    style: theme.textTheme.titleMedium?.copyWith(color: muted),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  label: '${split.paidCount} of $total shares paid',
                  child: ProgressRing(
                    value: total == 0 ? 0 : split.paidCount / total,
                    color: StatusColors.of(context).owed,
                    size: 70,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: split.settled
                          ? Icon(
                              Icons.check_rounded,
                              key: const ValueKey('done'),
                              color: StatusColors.of(context).owed,
                              size: 32,
                            )
                          : Text(
                              '${split.paidCount}/$total',
                              key: ValueKey(split.paidCount),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Avatar(name: payer.displayName, photoUrl: payer.photoUrl, radius: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${c.nameOf(split.paidBy)} paid · split ${split.splitType == SplitType.equal ? 'equally' : 'by ${split.splitType.label.toLowerCase()}'}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
            if (split.note != null && split.note!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
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
          ],
        ),
      ),
    );
  }
}

/// Opens a receipt or payment-proof photo full screen.
void showPhoto(String url, String title) {
  Get.dialog<void>(
    Dialog(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text(title, style: Get.textTheme.titleMedium)),
                IconButton(tooltip: 'Close', onPressed: () => Get.back<void>(), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Flexible(
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                semanticLabel: title,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()),
                errorBuilder: (_, _, _) =>
                    const Padding(padding: EdgeInsets.all(32), child: Text("Couldn't load the photo.")),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({super.key, required this.c, required this.split, required this.share});
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(name: m.displayName, photoUrl: m.photoUrl, radius: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (c, a) => ScaleTransition(
                  scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                  child: c,
                ),
                child: KeyedSubtree(
                  key: ValueKey('${share.status}-${share.isOverdue}'),
                  child: share.isPayerShare
                      ? StatusChip.neutral(context, 'Payer')
                      : StatusChip.share(context, share.status, overdue: share.isOverdue),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: actions.isEmpty
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
                    ),
                  ),
          ),
        ],
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mark as paid', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${Money.format(widget.share.amountMinor, widget.share.currency)} to ${widget.payerName} for ${widget.share.label}',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Text('How did you pay?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _methods.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _method == e.key,
                    onSelected: (_) => setState(() => _method = e.key),
                  ),
              ],
            ),
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
          ],
        ),
      ),
    );
  }
}
