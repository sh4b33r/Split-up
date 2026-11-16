import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/api.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/widgets.dart';

class ProfileController extends GetxController {
  final AuthService auth = Get.find();
  final Api _api = Get.find();
  final StorageService _storage = Get.find();

  final name = TextEditingController();
  final phone = TextEditingController();
  final photoUrl = RxnString();
  final busy = false.obs;
  final uploading = false.obs;

  @override
  void onInit() {
    super.onInit();
    final p = auth.profile.value;
    final u = auth.user.value;
    name.text = (p?.name.isNotEmpty ?? false) ? p!.name : (u?.displayName ?? '');
    phone.text = p?.phone ?? '';
    photoUrl.value = p?.photoUrl ?? u?.photoURL;
  }

  Future<void> pickPhoto() async {
    await Ui.attempt(() async {
      final XFile? file = await _storage.pick();
      if (file == null) return;
      photoUrl.value = await _storage.uploadAvatar(auth.uid, file);
    }, busy: uploading);
  }

  /// Returns true when the profile was saved.
  Future<bool> save() async {
    final n = name.text.trim();
    if (n.isEmpty) {
      Ui.toast('Enter your name so others know who you are.', error: true);
      return false;
    }
    final ok = await Ui.attempt(() async {
      await _api.updateProfile(name: n, phone: phone.text.trim(), photoUrl: photoUrl.value);
      return true;
    }, busy: busy);
    return ok == true;
  }

  Future<void> signOut() async {
    if (await Ui.confirm(title: 'Sign out?', message: "You'll need to sign in again to see your rooms.", confirmLabel: 'Sign out')) {
      await auth.signOut();
    }
  }

  @override
  void onClose() {
    name.dispose();
    phone.dispose();
    super.onClose();
  }
}

/// Profile setup after the first sign-in, and "edit profile" later on.
class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key, this.setup = false});

  /// True right after sign-up, when the user must enter a name to continue.
  final bool setup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(setup ? 'Set up your profile' : 'Your profile'),
        automaticallyImplyLeading: !setup,
        actions: [
          if (setup) TextButton(onPressed: controller.auth.signOut, child: const Text('Sign out')),
        ],
      ),
      body: SafeArea(
        child: Narrow(
          maxWidth: 480,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (setup)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'This is how you appear to the people you split bills with.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              Center(
                child: Obx(() => Stack(children: [
                      Avatar(
                        name: controller.name.text.isEmpty ? '?' : controller.name.text,
                        photoUrl: controller.photoUrl.value,
                        radius: 48,
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: IconButton.filled(
                          tooltip: 'Change photo',
                          onPressed: controller.uploading.value ? null : controller.pickPhoto,
                          icon: controller.uploading.value
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.photo_camera_outlined, size: 20),
                        ),
                      ),
                    ])),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: controller.name,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Name', counterText: '', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller.phone,
                keyboardType: TextInputType.phone,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  counterText: '',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              if (!setup && controller.auth.email != null) ...[
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.mail_outline),
                  title: Text(controller.auth.email!),
                  subtitle: Obx(() => Text(controller.auth.emailVerified.value ? 'Verified' : 'Not verified yet')),
                ),
              ],
              const SizedBox(height: 20),
              Obx(() => BusyButton(
                    label: setup ? 'Continue' : 'Save',
                    busy: controller.busy.value,
                    onPressed: () async {
                      final saved = await controller.save();
                      if (saved && !setup) {
                        Get.back();
                        Ui.toast('Profile saved');
                      }
                    },
                  )),
              if (!setup) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
