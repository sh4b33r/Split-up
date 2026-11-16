import 'package:flutter/material.dart' hide Split;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../core/utils/split_calculator.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../room/room_scope.dart';

/// The result of running the calculator on what is currently typed.
class SplitPreview {
  const SplitPreview({this.amounts = const {}, this.error, this.participants = const [], this.totalMinor});
  final Map<String, int> amounts;
  final String? error;
  final List<ParticipantInput> participants;
  final int? totalMinor;
  bool get ok => error == null && totalMinor != null;
}

class SplitFormController extends RoomScope {
  SplitFormController(super.roomId, {this.splitId});

  /// Null when adding a new split.
  final String? splitId;
  bool get isEdit => splitId != null;

  final StorageService _storage = Get.find();

  final title = TextEditingController();
  final total = TextEditingController();
  final note = TextEditingController();
  final dueAfter = TextEditingController(text: '5');
  final Map<String, TextEditingController> _inputs = {};

  final paidBy = ''.obs;
  final type = SplitType.equal.obs;
  final selected = <String>{}.obs;
  final dueDate = RxnString();
  final receiptUrl = RxnString();
  final receiptFile = Rxn<XFile>();
  final repeat = false.obs;
  final repeatDay = 1.obs;
  final endPeriod = RxnString();
  final ready = false.obs;

  /// Bumped on every keystroke so the live preview recalculates.
  final tick = 0.obs;

  /// The split being edited, once loaded.
  Split? original;

  /// True when someone has already paid: only the title, due date, note and
  /// receipt can change then.
  bool get moneyLocked => original?.hasPayments ?? false;

  TextEditingController inputFor(String uid) => _inputs.putIfAbsent(uid, () {
        final c = TextEditingController();
        c.addListener(() => tick.value++);
        return c;
      });

  @override
  void onInit() {
    super.onInit();
    final today = DateTime.now();
    repeatDay.value = today.day > 28 ? -1 : today.day;
    total.addListener(() => tick.value++);
    if (isEdit) {
      Get.find<SplitRepo>().split(roomId, splitId!).first.then(_load);
    } else {
      paidBy.value = uid;
      // Everyone in the room takes part by default.
      if (members.isNotEmpty) _defaults();
      ever<List<Member>>(members, (_) => _defaults());
    }
  }

  void _defaults() {
    if (ready.value || members.isEmpty) return;
    selected.addAll(activeMembers.map((m) => m.uid));
    ready.value = true;
  }

  void _load(Split? s) {
    if (s == null) {
      Get.back();
      Ui.toast('That split no longer exists.', error: true);
      return;
    }
    original = s;
    title.text = s.title;
    total.text = Money.editable(s.totalMinor, s.currency);
    note.text = s.note ?? '';
    paidBy.value = s.paidBy;
    type.value = s.splitType;
    selected.addAll(s.participantIds);
    dueDate.value = s.dueDate;
    receiptUrl.value = s.receiptUrl;
    for (final e in s.inputs.entries) {
      final v = e.value;
      if (v == null) continue;
      inputFor(e.key).text = switch (s.splitType) {
        SplitType.exact => Money.editable(v, s.currency),
        SplitType.percentage => _percentText(v),
        _ => '$v',
      };
    }
    ready.value = true;
  }

  static String _percentText(int basisPoints) {
    final whole = basisPoints ~/ 100, frac = basisPoints % 100;
    return frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(2, '0')}'.replaceFirst(RegExp(r'0$'), '');
  }

  /// "33.33" -> 3333 basis points.
  static int? _parsePercent(String text) {
    final m = RegExp(r'^(\d{1,3})(?:\.(\d{0,2}))?$').firstMatch(text.trim());
    if (m == null) return null;
    return int.parse(m.group(1)!) * 100 + int.parse((m.group(2) ?? '').padRight(2, '0'));
  }

  /// Members in a stable order: the split's original order when editing,
  /// otherwise me first. Leftover cents go to the first people in this list.
  List<Member> get orderedMembers {
    final active = activeMembers;
    final o = original;
    if (o == null) return active;
    final first = [for (final id in o.participantIds) member(id)].where((m) => m.isActive || o.participantIds.contains(m.uid));
    final rest = active.where((m) => !o.participantIds.contains(m.uid));
    return [...first, ...rest];
  }

  SplitPreview get preview {
    tick.value; // recompute when any field changes
    final totalMinor = Money.parse(total.text, currency);
    final people = orderedMembers.where((m) => selected.contains(m.uid)).toList();
    final t = type.value;
    final inputs = <ParticipantInput>[];
    for (final m in people) {
      final text = inputFor(m.uid).text.trim();
      final int? value = switch (t) {
        SplitType.equal => null,
        SplitType.exact => Money.parse(text, currency),
        SplitType.percentage => _parsePercent(text),
        SplitType.shares => int.tryParse(text),
      };
      inputs.add(ParticipantInput(m.uid, value));
    }
    if (totalMinor == null || totalMinor <= 0) {
      return SplitPreview(error: 'Enter the total amount.', participants: inputs);
    }
    if (people.isEmpty) {
      return SplitPreview(error: 'Pick who takes part.', participants: inputs, totalMinor: totalMinor);
    }
    if (!people.any((m) => m.uid != paidBy.value)) {
      return SplitPreview(error: 'Add at least one person other than whoever paid.', participants: inputs, totalMinor: totalMinor);
    }

    // Friendlier messages than the calculator's for the two "must add up" types.
    if (t == SplitType.exact) {
      final sum = inputs.fold<int>(0, (s, p) => s + (p.value ?? 0));
      final partial = {for (final p in inputs) if (p.value != null) p.uid: p.value!};
      if (sum < totalMinor) {
        return SplitPreview(amounts: partial, participants: inputs, totalMinor: totalMinor,
            error: '${Money.format(totalMinor - sum, currency)} left to assign.');
      }
      if (sum > totalMinor) {
        return SplitPreview(amounts: partial, participants: inputs, totalMinor: totalMinor,
            error: '${Money.format(sum - totalMinor, currency)} over the total.');
      }
    }
    if (t == SplitType.percentage) {
      final sum = inputs.fold<int>(0, (s, p) => s + (p.value ?? 0));
      if (sum != SplitCalculator.percentScale) {
        final diff = (SplitCalculator.percentScale - sum).abs();
        return SplitPreview(participants: inputs, totalMinor: totalMinor,
            error: sum < SplitCalculator.percentScale
                ? '${_percentText(diff)}% left to assign.'
                : '${_percentText(diff)}% over 100%.');
      }
    }
    try {
      final result = SplitCalculator.compute(t, totalMinor, inputs);
      return SplitPreview(
        amounts: {for (final r in result) r.uid: r.amountMinor},
        participants: inputs,
        totalMinor: totalMinor,
      );
    } on SplitException catch (e) {
      return SplitPreview(error: e.message, participants: inputs, totalMinor: totalMinor);
    }
  }

  void toggle(String id, bool on) {
    if (moneyLocked) return;
    on ? selected.add(id) : selected.remove(id);
  }

  void setType(SplitType t) {
    if (moneyLocked || t == type.value) return;
    for (final c in _inputs.values) {
      c.clear();
    }
    type.value = t;
  }

  void setRepeat(bool on) {
    repeat.value = on;
    if (on && dueDate.value == null) _fillDueFromRule();
  }

  /// This month's due date for a monthly bill: the run day plus "due after".
  void _fillDueFromRule() {
    final days = int.tryParse(dueAfter.text) ?? 0;
    final run = Dates.runDate(Dates.period(DateTime.now()), repeatDay.value).add(Duration(days: days));
    final today = DateTime.now();
    final base = run.isBefore(DateTime(today.year, today.month, today.day)) ? today.add(Duration(days: days)) : run;
    dueDate.value = Dates.ymd(base);
  }

  Future<void> pickDue(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: dueDate.value == null ? now : Dates.parse(dueDate.value!),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3, 12, 31),
      helpText: 'Due date',
    );
    if (picked != null) dueDate.value = Dates.ymd(picked);
  }

  Future<void> pickEnd(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: endPeriod.value == null ? DateTime(now.year + 1, now.month) : Dates.parse(endPeriod.value!),
      firstDate: DateTime(now.year, now.month),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: 'Last month this bill repeats',
    );
    if (picked != null) endPeriod.value = Dates.period(picked);
  }

  Future<void> pickReceipt() async {
    final file = await Ui.attempt(() => _storage.pick());
    if (file != null) receiptFile.value = file;
  }

  void clearReceipt() {
    receiptFile.value = null;
    receiptUrl.value = null;
  }

  Future<void> save() async {
    final name = title.text.trim();
    if (name.isEmpty) return Ui.toast('Give the split a title, like "Rent".', error: true);
    final p = preview;
    if (!p.ok) return Ui.toast(p.error ?? 'Check the amounts.', error: true);
    final after = int.tryParse(dueAfter.text.trim()) ?? 0;
    if (repeat.value && (after < 0 || after > 60)) {
      return Ui.toast('"Due after" must be between 0 and 60 days.', error: true);
    }

    final done = await Ui.attempt(() async {
      var receipt = receiptUrl.value;
      final file = receiptFile.value;
      if (file != null) receipt = await _storage.uploadRoomPhoto(roomId, 'receipts', uid, file);
      final noteText = note.text.trim().isEmpty ? null : note.text.trim();
      if (isEdit) {
        await api.updateSplit(
          roomId: roomId, splitId: splitId!, title: name, totalMinor: p.totalMinor!, paidBy: paidBy.value,
          type: type.value, participants: p.participants, dueDate: dueDate.value, note: noteText, receiptUrl: receipt,
        );
      } else {
        await api.createSplit(
          roomId: roomId, title: name, totalMinor: p.totalMinor!, paidBy: paidBy.value, type: type.value,
          participants: p.participants, dueDate: dueDate.value, note: noteText, receiptUrl: receipt,
          repeatDayOfMonth: repeat.value ? repeatDay.value : null,
          repeatDueAfterDays: after,
          repeatEndPeriod: repeat.value ? endPeriod.value : null,
        );
      }
      return true;
    }, busy: busy);
    if (done == true) {
      Get.back();
      Ui.toast(isEdit ? 'Split updated' : 'Split added');
    }
  }

  @override
  void onClose() {
    title.dispose();
    total.dispose();
    note.dispose();
    dueAfter.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.onClose();
  }
}

class SplitFormView extends StatelessWidget {
  const SplitFormView({super.key, required this.roomId, this.splitId});
  final String roomId;
  final String? splitId;

  @override
  Widget build(BuildContext context) {
    return Scoped<SplitFormController>(
      create: () => SplitFormController(roomId, splitId: splitId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(title: Text(c.isEdit ? 'Edit split' : 'Add split')),
        body: SafeArea(
          child: Narrow(
            child: Obx(() {
              if (!c.ready.value || c.room.value == null) return const Center(child: CircularProgressIndicator());
              return _Form(c: c);
            }),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Narrow(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Obx(() => BusyButton(
                    label: c.isEdit ? 'Save changes' : 'Save split',
                    busy: c.busy.value,
                    onPressed: c.ready.value ? c.save : null,
                  )),
            ),
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.c});
  final SplitFormController c;

  @override
  Widget build(BuildContext context) => Obx(() => _content(context));

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final locked = c.moneyLocked;
    final members = c.orderedMembers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (locked)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors.pendingContainer, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(Icons.lock_outline, color: colors.pending),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Someone has already paid, so the amounts are locked. Undo the paid shares to change them.',
                  style: TextStyle(color: colors.pending, fontWeight: FontWeight.w500),
                ),
              ),
            ]),
          ),
        TextField(
          controller: c.title,
          autofocus: !c.isEdit,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Title', hintText: 'Rent, Internet, Groceries…', counterText: ''),
        ),
        const SizedBox(height: 12),
        IgnorePointer(
          ignoring: locked,
          child: Opacity(
            opacity: locked ? 0.55 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AmountField(
                controller: c.total,
                currency: c.currency,
                label: 'Total',
                style: theme.textTheme.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: members.any((m) => m.uid == c.paidBy.value) ? c.paidBy.value : null,
                decoration: const InputDecoration(labelText: 'Paid by'),
                items: [for (final m in members) DropdownMenuItem(value: m.uid, child: Text(c.nameOf(m.uid)))],
                onChanged: (v) => c.paidBy.value = v ?? c.paidBy.value,
              ),
              const SectionTitle('How to split'),
              SegmentedButton<SplitType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: SplitType.equal, label: Text('Equal')),
                  ButtonSegment(value: SplitType.exact, label: Text('Exact')),
                  ButtonSegment(value: SplitType.percentage, label: Text('%')),
                  ButtonSegment(value: SplitType.shares, label: Text('Shares')),
                ],
                selected: {c.type.value},
                onSelectionChanged: (s) => c.setType(s.first),
              ),
              const SizedBox(height: 12),
              _Participants(c: c, members: members),
            ]),
          ),
        ),
        const SectionTitle('Details'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(c.dueDate.value == null ? 'Add a due date' : 'Due ${Dates.short(c.dueDate.value!)}'),
              subtitle: c.dueDate.value == null ? const Text('Members get reminders before it') : null,
              trailing: c.dueDate.value == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(tooltip: 'Remove due date', icon: const Icon(Icons.close), onPressed: () => c.dueDate.value = null),
              onTap: () => c.pickDue(context),
            ),
            if (!c.isEdit) ...[
              const Divider(indent: 56),
              SwitchListTile(
                secondary: const Icon(Icons.event_repeat_outlined),
                title: const Text('Repeat monthly'),
                subtitle: const Text('Creates this bill again every month'),
                value: c.repeat.value,
                onChanged: c.setRepeat,
              ),
              if (c.repeat.value) _Repeat(c: c),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c.note,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
        ),
        const SizedBox(height: 12),
        _Receipt(c: c),
      ],
    );
  }
}

class _Participants extends StatelessWidget {
  const _Participants({required this.c, required this.members});
  final SplitFormController c;
  final List<Member> members;

  @override
  Widget build(BuildContext context) => Obx(() => _content(context));

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final preview = c.preview;
    final type = c.type.value;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (i, m) in members.indexed) ...[
          if (i > 0) const Divider(indent: 56),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
            child: Row(children: [
              Checkbox(
                value: c.selected.contains(m.uid),
                onChanged: (v) => c.toggle(m.uid, v ?? false),
                semanticLabel: 'Include ${m.displayName}',
              ),
              Avatar(name: m.displayName, photoUrl: m.photoUrl, radius: 15),
              const SizedBox(width: 10),
              Expanded(
                child: Text(c.nameOf(m.uid), style: theme.textTheme.bodyLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (c.selected.contains(m.uid)) ...[
                if (type == SplitType.exact)
                  SizedBox(width: 150, child: AmountField(controller: c.inputFor(m.uid), currency: c.currency, dense: true))
                else if (type != SplitType.equal) ...[
                  SizedBox(
                    width: 84,
                    child: TextField(
                      controller: c.inputFor(m.uid),
                      textAlign: TextAlign.end,
                      keyboardType: TextInputType.numberWithOptions(decimal: type == SplitType.percentage),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          type == SplitType.percentage ? RegExp(r'^\d{0,3}(\.\d{0,2})?') : RegExp(r'^\d{0,4}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: type == SplitType.percentage ? '0' : '1',
                        suffixText: type == SplitType.percentage ? '%' : '×',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (type != SplitType.exact)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 92),
                    child: Text(
                      preview.amounts[m.uid] == null ? '—' : Money.format(preview.amounts[m.uid]!, c.currency),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
              ],
            ]),
          ),
        ],
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: preview.ok ? colors.owedContainer : theme.colorScheme.surfaceContainerHighest,
          child: Row(children: [
            Icon(
              preview.ok ? Icons.check_circle : Icons.info_outline,
              size: 18,
              color: preview.ok ? colors.owed : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preview.ok ? 'Shares add up to ${Money.format(preview.totalMinor!, c.currency)}' : preview.error!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: preview.ok ? colors.owed : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Repeat extends StatelessWidget {
  const _Repeat({required this.c});
  final SplitFormController c;

  @override
  Widget build(BuildContext context) => Obx(() => _content(context));

  Widget _content(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: c.repeatDay.value,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Repeats on'),
              items: [
                for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('the ${Dates.ordinal(d)}')),
                const DropdownMenuItem(value: -1, child: Text('the last day')),
              ],
              onChanged: (v) => c.repeatDay.value = v ?? 1,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextField(
              controller: c.dueAfter,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              decoration: const InputDecoration(labelText: 'Due after', suffixText: 'days'),
            ),
          ),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(c.endPeriod.value == null ? 'No end date' : 'Ends after ${Dates.periodLabel(c.endPeriod.value!)}'),
          subtitle: c.endPeriod.value == null ? const Text('Repeats until you stop it') : null,
          trailing: c.endPeriod.value == null
              ? TextButton(onPressed: () => c.pickEnd(context), child: const Text('Set end'))
              : IconButton(tooltip: 'Remove end date', icon: const Icon(Icons.close), onPressed: () => c.endPeriod.value = null),
          onTap: () => c.pickEnd(context),
        ),
      ]),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.c});
  final SplitFormController c;

  @override
  Widget build(BuildContext context) => Obx(() => _content(context));

  Widget _content(BuildContext context) {
    final has = c.receiptFile.value != null || c.receiptUrl.value != null;
    if (!has) {
      return OutlinedButton.icon(
        onPressed: c.pickReceipt,
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Add receipt photo'),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(c.receiptFile.value != null ? c.receiptFile.value!.name : 'Receipt attached'),
        subtitle: Text(c.receiptFile.value != null ? 'Uploads when you save' : 'Saved with this split'),
        trailing: IconButton(tooltip: 'Remove receipt', icon: const Icon(Icons.close), onPressed: c.clearReceipt),
      ),
    );
  }
}
