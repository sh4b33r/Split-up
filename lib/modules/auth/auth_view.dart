import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/widgets.dart';

/// Shown while Firebase works out whether someone is signed in.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AppMark(size: 84),
          const SizedBox(height: 20),
          Text(AppConfig.appName, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 28),
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: scheme.primary)),
        ]),
      ),
    );
  }
}

/// The app's mark: a rounded tile split in two.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(Icons.call_split_rounded, color: scheme.onPrimary, size: size * 0.56),
    );
  }
}

class AuthController extends GetxController {
  final AuthService _auth = Get.find();

  final email = TextEditingController();
  final password = TextEditingController();
  final isSignUp = false.obs;
  final busy = false.obs;
  final obscure = true.obs;

  bool get showApple =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> submit() async {
    final e = email.text.trim();
    if (!GetUtils.isEmail(e)) return Ui.toast('Enter your email address.', error: true);
    if (password.text.length < 6) return Ui.toast('Your password needs at least 6 characters.', error: true);
    await Ui.attempt(() => isSignUp.value ? _auth.signUp(e, password.text) : _auth.signIn(e, password.text), busy: busy);
  }

  Future<void> google() => Ui.attempt(_auth.signInWithGoogle, busy: busy);
  Future<void> apple() => Ui.attempt(_auth.signInWithApple, busy: busy);

  Future<void> forgot() async {
    final address = await Ui.prompt(
      title: 'Reset your password',
      message: "We'll email you a link to choose a new password.",
      hint: 'you@example.com',
      initial: email.text.trim(),
      confirmLabel: 'Send link',
      keyboardType: TextInputType.emailAddress,
    );
    if (address == null) return;
    await Ui.attempt(() => _auth.sendPasswordReset(address), success: 'Check your inbox for the reset link.');
  }

  @override
  void onClose() {
    email.dispose();
    password.dispose();
    super.onClose();
  }
}

class AuthView extends GetView<AuthController> {
  const AuthView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Narrow(
          maxWidth: 440,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            children: [
              const Align(alignment: Alignment.centerLeft, child: AppMark()),
              const SizedBox(height: 24),
              Text(AppConfig.appName, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(
                AppConfig.tagline,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              Obx(() => SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sign in')),
                      ButtonSegment(value: true, label: Text('Create account')),
                    ],
                    selected: {controller.isSignUp.value},
                    onSelectionChanged: (s) => controller.isSignUp.value = s.first,
                  )),
              const SizedBox(height: 18),
              TextField(
                controller: controller.email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 12),
              Obx(() => TextField(
                    controller: controller.password,
                    obscureText: controller.obscure.value,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => controller.submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: controller.obscure.value ? 'Show password' : 'Hide password',
                        icon: Icon(controller.obscure.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: controller.obscure.toggle,
                      ),
                    ),
                  )),
              const SizedBox(height: 18),
              Obx(() => BusyButton(
                    label: controller.isSignUp.value ? 'Create account' : 'Sign in',
                    busy: controller.busy.value,
                    onPressed: controller.submit,
                  )),
              Obx(() => controller.isSignUp.value
                  ? const SizedBox(height: 12)
                  : Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: controller.forgot, child: const Text('Forgot password?')),
                    )),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  const Expanded(child: Divider()),
                ]),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: controller.google,
                icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                label: const Text('Continue with Google'),
              ),
              if (controller.showApple) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: controller.apple,
                  icon: const Icon(Icons.apple),
                  label: const Text('Continue with Apple'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
