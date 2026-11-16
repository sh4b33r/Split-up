import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../core/services/api.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/widgets.dart';

/// One join screen for all three ways in: a typed room code, an invite link
/// (the token arrives as the route argument) and, from Home, an email invite.
class JoinRoomController extends GetxController {
  final Api _api = Get.find();

  final code = TextEditingController();
  final preview = Rxn<Map<String, dynamic>>();
  final busy = false.obs;
  final requested = false.obs;
  String? _codeOrToken;

  bool get fromLink => Get.arguments is String;

  @override
  void onInit() {
    super.onInit();
    final arg = Get.arguments;
    if (arg is String && arg.isNotEmpty) _find(arg);
  }

  Future<void> findByCode() async {
    final c = code.text.trim().toUpperCase();
    if (c.length != 6) return Ui.toast('Room codes have 6 characters.', error: true);
    await _find(c);
  }

  Future<void> _find(String codeOrToken) async {
    final result = await Ui.attempt(() => _api.previewRoom(codeOrToken), busy: busy);
    if (result == null) return;
    _codeOrToken = codeOrToken;
    preview.value = result;
    requested.value = result['requested'] == true;
  }

  Future<void> join() async {
    final p = preview.value;
    if (p == null) return;
    if (p['alreadyMember'] == true) return Get.offNamed(Routes.room(p['roomId'] as String));
    final result = await Ui.attempt(() => _api.joinRoom(_codeOrToken!), busy: busy);
    if (result == null) return;
    if (result['status'] == 'requested') {
      requested.value = true;
    } else {
      Ui.toast('You joined ${p['name']}');
      Get.offNamed(Routes.room(result['roomId'] as String));
    }
  }

  void reset() {
    preview.value = null;
    requested.value = false;
  }

  @override
  void onClose() {
    code.dispose();
    super.onClose();
  }
}

class JoinRoomView extends GetView<JoinRoomController> {
  const JoinRoomView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a room')),
      body: SafeArea(
        child: Narrow(
          maxWidth: 480,
          child: Obx(() {
            final p = controller.preview.value;
            if (p != null) return _Preview(p: p);
            if (controller.fromLink && controller.busy.value) {
              return const Center(child: CircularProgressIndicator());
            }
            return _CodeEntry();
          }),
        ),
      ),
    );
  }
}

class _CodeEntry extends GetView<JoinRoomController> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Enter the room code', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Ask the room owner for the 6-character code, or open the invite link they sent you.',
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller.code,
          autofocus: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 10, fontFeatures: const [FontFeature.tabularFigures()]),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
          ],
          decoration: const InputDecoration(hintText: 'K7P2QX', counterText: '', labelText: 'Room code'),
          onSubmitted: (_) => controller.findByCode(),
        ),
        const SizedBox(height: 18),
        Obx(() => BusyButton(label: 'Find room', busy: controller.busy.value, onPressed: controller.findByCode)),
      ],
    );
  }
}

class _Preview extends GetView<JoinRoomController> {
  const _Preview({required this.p});
  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final count = (p['memberCount'] as num?)?.toInt() ?? 0;
    final already = p['alreadyMember'] == true;
    final approval = p['requireApproval'] == true;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
                child: Text('${p['icon'] ?? '🏠'}', style: const TextStyle(fontSize: 42)),
              ),
              const SizedBox(height: 16),
              Text('${p['name']}', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Owned by ${p['ownerName']}', style: muted),
              const SizedBox(height: 2),
              Text('$count ${count == 1 ? 'member' : 'members'} · ${p['currency']}', style: muted),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Obx(() {
          if (controller.requested.value) {
            return Column(children: [
              Icon(Icons.hourglass_top, color: theme.colorScheme.primary, size: 32),
              const SizedBox(height: 10),
              Text('Request sent', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                "${p['ownerName']} needs to approve it. You'll get a notification when you're in.",
                textAlign: TextAlign.center,
                style: muted,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: () => Get.offAllNamed(Routes.home), child: const Text('Back to home')),
              ),
            ]);
          }
          return Column(children: [
            BusyButton(
              label: already ? 'Open room' : (approval ? 'Request to join' : 'Join room'),
              busy: controller.busy.value,
              onPressed: controller.join,
            ),
            if (approval && !already)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('The owner approves new members in this room.', style: muted, textAlign: TextAlign.center),
              ),
            if (!controller.fromLink)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton(onPressed: controller.reset, child: const Text('Try a different code')),
              ),
          ]);
        }),
      ],
    );
  }
}
