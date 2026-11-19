import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_config.dart';
import '../../app/routes/app_routes.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';
import '../room/create_room_view.dart' show roomIcons;
import '../room/room_scope.dart';

class RoomSettingsController extends RoomScope {
  RoomSettingsController(super.roomId);

  final requests = <JoinRequest>[].obs;
  final invites = <Invite>[].obs;
  final email = TextEditingController();
  final inviting = false.obs;

  @override
  void onInit() {
    super.onInit();
    watch(Get.find<RoomRepo>().joinRequests(roomId), requests.assignAll);
    watch(Get.find<InviteRepo>().pendingForRoom(roomId), invites.assignAll);
  }

  @override
  void onClose() {
    email.dispose();
    super.onClose();
  }

  String get link => AppConfig.inviteLink(room.value?.inviteToken ?? '');

  Future<void> copyCode() async {
    await Clipboard.setData(ClipboardData(text: room.value?.code ?? ''));
    Ui.toast('Room code copied');
  }

  Future<void> shareLink() async {
    final r = room.value;
    if (r == null) return;
    final text =
        'Join "${r.name}" on ${AppConfig.appName} to split bills with me:\n$link\n\n'
        'Or open the app and enter room code ${r.code}';
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: 'Join ${r.name}'));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      Ui.toast('Invite copied');
    }
  }

  Future<void> invite() async {
    final address = email.text.trim();
    if (!GetUtils.isEmail(address)) return Ui.toast('Enter a valid email address.', error: true);
    final registered = await Ui.attempt(() => api.inviteByEmail(roomId, address), busy: inviting);
    if (registered == null) return;
    email.clear();
    Ui.toast(
      registered ? 'Invite sent. They will see it in the app.' : 'Invite emailed. It will wait until they sign up.',
    );
  }

  Future<void> cancelInvite(Invite i) => Ui.attempt(() => api.cancelInvite(i.id), success: 'Invite cancelled');

  Future<void> resetInvite() async {
    final ok = await Ui.confirm(
      title: 'Reset code and link?',
      message: 'The current room code and invite link will stop working. People already in the room are not affected.',
      confirmLabel: 'Reset',
    );
    if (ok) await Ui.attempt(() => api.resetInvite(roomId), busy: busy, success: 'New code and link created');
  }

  Future<void> setApproval(bool value) => Ui.attempt(() => api.updateRoom(roomId, requireApproval: value), busy: busy);

  Future<void> rename() async {
    final name = await Ui.prompt(title: 'Rename room', initial: room.value?.name, maxLength: 40);
    if (name != null) await Ui.attempt(() => api.updateRoom(roomId, name: name), busy: busy);
  }

  Future<void> setIcon(String icon) => Ui.attempt(() => api.updateRoom(roomId, icon: icon), busy: busy);

  Future<void> respond(JoinRequest r, bool approve) => Ui.attempt(
    () => api.respondJoinRequest(roomId, r.uid, approve: approve),
    busy: busy,
    success: approve ? '${r.displayName} joined the room' : 'Request declined',
  );

  Future<void> setRole(Member m, String role) => Ui.attempt(
    () => api.setRole(roomId, m.uid, role),
    busy: busy,
    success: role == 'admin' ? '${m.displayName} is now an admin' : '${m.displayName} is no longer an admin',
  );

  Future<void> transfer(Member m) async {
    final ok = await Ui.confirm(
      title: 'Make ${m.displayName} the owner?',
      message: 'They will be able to manage the room and its members. You will stay in the room as an admin.',
      confirmLabel: 'Transfer',
    );
    if (!ok) return;
    await Ui.attempt(
      () => api.transferOwnership(roomId, m.uid),
      busy: busy,
      success: '${m.displayName} now owns the room',
    );
  }

  Future<void> remove(Member m) async {
    final ok = await Ui.confirm(
      title: 'Remove ${m.displayName}?',
      message: 'They will lose access to this room. Their past bills stay in the history.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    await Ui.attempt(() => api.removeMember(roomId, m.uid), busy: busy, success: '${m.displayName} was removed');
  }

  Future<void> leave() async {
    final ok = await Ui.confirm(
      title: 'Leave this room?',
      message: "You won't see its bills any more. You can rejoin later with the room code.",
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!ok) return;
    final done = await Ui.attempt(() async {
      await api.leaveRoom(roomId);
      return true;
    }, busy: busy);
    if (done == true) {
      Get.offAllNamed(Routes.home);
      Ui.toast('You left the room');
    }
  }
}

class RoomSettingsView extends StatelessWidget {
  const RoomSettingsView({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scoped<RoomSettingsController>(
      create: () => RoomSettingsController(roomId),
      builder: (context, c) => Scaffold(
        appBar: AppBar(title: const Text('Room & members')),
        body: SafeArea(
          child: Narrow(
            child: Obx(() {
              final room = c.room.value;
              if (room == null) return const Center(child: CircularProgressIndicator());
              final manager = c.isManager;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  _Header(c: c, room: room).enter(context),
                  if (manager) ...[
                    const SectionTitle('Invite people'),
                    _InviteCard(c: c, room: room).enter(context, index: 1),
                    if (c.requests.isNotEmpty) ...[
                      const SectionTitle('Waiting for approval'),
                      for (final r in c.requests) _RequestTile(c: c, request: r).enter(context, index: 2),
                    ],
                  ],
                  SectionTitle('Members', trailing: Text('${c.activeMembers.length}')),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, m) in c.activeMembers.indexed) ...[
                          if (i > 0) const Divider(indent: 68),
                          _MemberTile(c: c, room: room, member: m),
                        ],
                      ],
                    ),
                  ),
                  if (!manager)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                      child: Text(
                        'Only ${c.member(room.ownerId).displayName} (the owner) can invite or remove people.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 28),
                  if (c.isOwner)
                    Text(
                      'To leave this room, first make someone else the owner.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    )
                  else
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                      onPressed: c.leave,
                      icon: const Icon(Icons.logout),
                      label: const Text('Leave room'),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c, required this.room});
  final RoomSettingsController c;
  final Room room;

  Future<void> _pickIcon(BuildContext context) async {
    final icon = await Get.bottomSheet<String>(
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final i in roomIcons)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Get.back(result: i),
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: Center(child: Text(i, style: const TextStyle(fontSize: 28))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (icon != null) await c.setIcon(icon);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: c.isManager ? () => _pickIcon(context) : null,
              child: Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(room.icon, style: const TextStyle(fontSize: 30)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room.name, style: theme.textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    'Bills in ${room.currency}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (c.isManager)
              IconButton(tooltip: 'Rename room', onPressed: c.rename, icon: const Icon(Icons.edit_outlined)),
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.c, required this.room});
  final RoomSettingsController c;
  final Room room;

  @override
  Widget build(BuildContext context) => Obx(() => _content(context));

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room code', style: theme.textTheme.labelLarge?.copyWith(color: muted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    room.code,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      letterSpacing: 6,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Copy code',
                  onPressed: c.copyCode,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.shareLink,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share invite link'),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: c.email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onSubmitted: (_) => c.invite(),
                    decoration: const InputDecoration(labelText: 'Invite by email', hintText: 'friend@example.com'),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Obx(
                    () => IconButton.filled(
                      tooltip: 'Send invite',
                      onPressed: c.inviting.value ? null : c.invite,
                      icon: c.inviting.value
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ),
              ],
            ),
            for (final i in c.invites)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.schedule_send_outlined, color: muted),
                title: Text(i.emailLower),
                subtitle: const Text('Invite pending'),
                trailing: IconButton(
                  tooltip: 'Cancel invite',
                  onPressed: () => c.cancelInvite(i),
                  icon: const Icon(Icons.close),
                ),
              ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: room.requireApproval,
              onChanged: c.setApproval,
              title: const Text('Approve new members'),
              subtitle: const Text('People who use the code or link wait for your OK'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: c.resetInvite,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reset code and link'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.c, required this.request});
  final RoomSettingsController c;
  final JoinRequest request;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Avatar(name: request.displayName, photoUrl: request.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.displayName, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      'Wants to join · used the ${request.via == 'link' ? 'invite link' : 'room code'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(tooltip: 'Decline', onPressed: () => c.respond(request, false), icon: const Icon(Icons.close)),
              IconButton.filled(
                tooltip: 'Approve',
                onPressed: () => c.respond(request, true),
                icon: const Icon(Icons.check),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.c, required this.room, required this.member});
  final RoomSettingsController c;
  final Room room;
  final Member member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StatusColors.of(context);
    final isOwner = member.uid == room.ownerId;
    final isAdmin = room.adminIds.contains(member.uid);
    final net = member.netMinor;
    final me = member.uid == c.uid;

    final actions = <PopupMenuEntry<String>>[
      if (c.isOwner && !isOwner && !isAdmin) const PopupMenuItem(value: 'admin', child: Text('Make admin')),
      if (c.isOwner && isAdmin) const PopupMenuItem(value: 'member', child: Text('Remove as admin')),
      if (c.isOwner && !isOwner) const PopupMenuItem(value: 'transfer', child: Text('Make owner')),
      if (c.isManager && !isOwner && !me && (c.isOwner || !isAdmin))
        const PopupMenuItem(value: 'remove', child: Text('Remove from room')),
    ];

    return ListTile(
      leading: Avatar(name: member.displayName, photoUrl: member.photoUrl),
      title: Row(
        children: [
          Flexible(
            child: Text(me ? '${member.displayName} (you)' : member.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (isOwner || isAdmin) ...[
            const SizedBox(width: 8),
            StatusChip(
              label: isOwner ? 'Owner' : 'Admin',
              color: theme.colorScheme.onPrimaryContainer,
              background: theme.colorScheme.primaryContainer,
            ),
          ],
        ],
      ),
      subtitle: Text(
        net == 0
            ? 'Settled up'
            : (net > 0 ? 'Gets back ${Money.format(net, room.currency)}' : 'Owes ${Money.format(-net, room.currency)}'),
        style: TextStyle(color: net == 0 ? theme.colorScheme.onSurfaceVariant : (net > 0 ? colors.owed : colors.owe)),
      ),
      trailing: actions.isEmpty
          ? null
          : PopupMenuButton<String>(
              tooltip: 'Options for ${member.displayName}',
              itemBuilder: (_) => actions,
              onSelected: (v) => switch (v) {
                'admin' => c.setRole(member, 'admin'),
                'member' => c.setRole(member, 'member'),
                'transfer' => c.transfer(member),
                _ => c.remove(member),
              },
            ),
    );
  }
}
