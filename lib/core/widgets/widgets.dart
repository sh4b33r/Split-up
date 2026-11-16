import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../utils/money.dart';

/// A round avatar: the photo if there is one, otherwise initials on a colour
/// picked from the name.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.photoUrl, this.radius = 20});
  final String name;
  final String? photoUrl;
  final double radius;

  static const _palette = [
    Color(0xFF0B6E4F), Color(0xFF1D4E89), Color(0xFF8A4FFF), Color(0xFFB5179E),
    Color(0xFFC1440E), Color(0xFF2A7F9E), Color(0xFF6B705C), Color(0xFF9C6644),
  ];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = _palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
      child: Text(
        _initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.72),
      ),
    );
  }
}

/// Overlapping avatars with a "+3" bubble when there are more than [max].
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.members, this.max = 4, this.radius = 13});
  final List<Member> members;
  final int max;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final step = radius * 1.45;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      height: radius * 2 + 4,
      width: step * (count - 1) + radius * 2 + 4,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: i * step,
            child: CircleAvatar(
              radius: radius + 2,
              backgroundColor: scheme.surfaceContainerLowest,
              child: Avatar(name: shown[i].displayName, photoUrl: shown[i].photoUrl, radius: radius),
            ),
          ),
        if (extra > 0)
          Positioned(
            left: shown.length * step,
            child: CircleAvatar(
              radius: radius + 2,
              backgroundColor: scheme.surfaceContainerLowest,
              child: CircleAvatar(
                radius: radius,
                backgroundColor: scheme.surfaceContainerHighest,
                child: Text('+$extra', style: TextStyle(fontSize: radius * 0.72, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A small coloured pill. Use the named constructors for payment states.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, required this.background, this.icon});

  factory StatusChip.share(BuildContext context, ShareStatus status, {bool overdue = false}) {
    final c = StatusColors.of(context);
    switch (status) {
      case ShareStatus.paid:
        return StatusChip(label: 'Paid', color: c.owed, background: c.owedContainer, icon: Icons.check_circle);
      case ShareStatus.markedPaid:
        return StatusChip(label: 'Marked paid', color: c.pending, background: c.pendingContainer, icon: Icons.hourglass_top);
      case ShareStatus.unpaid:
        return overdue
            ? StatusChip(label: 'Overdue', color: c.owe, background: c.oweContainer, icon: Icons.error)
            : StatusChip(
                label: 'Unpaid',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                background: Theme.of(context).colorScheme.surfaceContainerHighest,
              );
    }
  }

  factory StatusChip.settled(BuildContext context) {
    final c = StatusColors.of(context);
    return StatusChip(label: 'Settled', color: c.owed, background: c.owedContainer, icon: Icons.check_circle);
  }

  factory StatusChip.overdue(BuildContext context) {
    final c = StatusColors.of(context);
    return StatusChip(label: 'Overdue', color: c.owe, background: c.oweContainer, icon: Icons.error);
  }

  factory StatusChip.neutral(BuildContext context, String label, {IconData? icon}) {
    final scheme = Theme.of(context).colorScheme;
    return StatusChip(label: label, color: scheme.onSurfaceVariant, background: scheme.surfaceContainerHighest, icon: icon);
  }

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: 18),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

/// A money text field: decimal keyboard, only as many decimals as the
/// currency has, and the currency code as a suffix.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    this.label,
    this.hint,
    this.onChanged,
    this.dense = false,
    this.autofocus = false,
    this.style,
  });
  final TextEditingController controller;
  final String currency;
  final String? label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool dense;
  final bool autofocus;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final decimals = Money.decimals(currency);
    final pattern = decimals == 0 ? RegExp(r'^\d{0,9}$') : RegExp('^\\d{0,9}(\\.\\d{0,$decimals})?\$');
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: style,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
      textAlign: dense ? TextAlign.end : TextAlign.start,
      inputFormatters: [
        TextInputFormatter.withFunction((oldValue, newValue) => pattern.hasMatch(newValue.text) ? newValue : oldValue),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint ?? (decimals == 0 ? '0' : '0.${'0' * decimals}'),
        suffixText: currency,
        isDense: dense,
        contentPadding: dense ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12) : null,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ?trailing,
      ]),
    );
  }
}

/// A full-width button that shows a spinner while [busy].
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Text(label),
              ]),
      ),
    );
  }
}

/// Keeps content readable on tablets and the web.
class Narrow extends StatelessWidget {
  const Narrow({super.key, required this.child, this.maxWidth = 640, this.shrink = false});
  final Widget child;
  final double maxWidth;

  /// Only as tall as [child], for bottom bars.
  final bool shrink;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: shrink ? 1 : null,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
