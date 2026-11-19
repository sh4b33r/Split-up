import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../../app/routes/app_routes.dart';
import '../../core/services/api.dart';
import '../../core/utils/money.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/widgets.dart';

const roomIcons = ['🏠', '🏢', '🏖️', '✈️', '🍽️', '🚗', '🎉', '💼', '🎓', '⚽', '🛒', '💡'];

class CreateRoomController extends GetxController {
  final Api _api = Get.find();
  final name = TextEditingController();
  final currency = AppConfig.defaultCurrency.obs;
  final icon = roomIcons.first.obs;
  final busy = false.obs;

  Future<void> create() async {
    final n = name.text.trim();
    if (n.isEmpty) return Ui.toast('Give the room a name.', error: true);
    final roomId = await Ui.attempt(
      () => _api.createRoom(name: n, currency: currency.value, icon: icon.value),
      busy: busy,
    );
    // Open the room with its settings on top, so the code is ready to share.
    if (roomId != null) {
      Get.offNamed(Routes.room(roomId));
      Get.toNamed(Routes.roomSettings(roomId));
    }
  }

  @override
  void onClose() {
    name.dispose();
    super.onClose();
  }
}

class CreateRoomView extends GetView<CreateRoomController> {
  const CreateRoomView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New room')),
      body: SafeArea(
        child: Narrow(
          maxWidth: 520,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Obx(
                  () => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (c, a) => ScaleTransition(
                      scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                      child: c,
                    ),
                    child: Container(
                      key: ValueKey(controller.icon.value),
                      width: 88,
                      height: 88,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Text(controller.icon.value, style: const TextStyle(fontSize: 44)),
                    ),
                  ),
                ),
              ).enter(context),
              const SizedBox(height: 20),
              TextField(
                controller: controller.name,
                autofocus: true,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Room name', hintText: 'Flat 12', counterText: ''),
              ),
              const SizedBox(height: 14),
              Obx(
                () => DropdownButtonFormField<String>(
                  initialValue: controller.currency.value,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [for (final c in Money.currencies.keys) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => controller.currency.value = v ?? controller.currency.value,
                ),
              ),
              const SectionTitle('Icon'),
              Obx(
                () => Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final i in roomIcons)
                      Semantics(
                        button: true,
                        selected: controller.icon.value == i,
                        label: 'Icon $i',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => controller.icon.value = i,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 54,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: controller.icon.value == i
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: controller.icon.value == i
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                width: controller.icon.value == i ? 2 : 1,
                              ),
                            ),
                            child: ExcludeSemantics(
                              child: AnimatedScale(
                                scale: controller.icon.value == i ? 1.18 : 1,
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutBack,
                                child: Text(i, style: const TextStyle(fontSize: 26)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Obx(() => BusyButton(label: 'Create room', busy: controller.busy.value, onPressed: controller.create)),
              const SizedBox(height: 12),
              Text(
                "You'll get a 6-character room code and an invite link to share.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
