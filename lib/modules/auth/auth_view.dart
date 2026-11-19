import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../../app/theme/app_theme.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/ui.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/widgets.dart';

/// Shown while Firebase works out whether someone is signed in.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: DriftingBlobs()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppMark(size: 88).pop(context),
                const SizedBox(height: 20),
                Text(
                  AppConfig.appName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ).enter(context, delay: const Duration(milliseconds: 150)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The app's mark: a gradient tile with the split arrow.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 64});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: Brand.hero(context),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: Brand.glow(context),
      ),
      child: Icon(Icons.call_split_rounded, color: Colors.white, size: size * 0.56),
    );
  }
}

enum AuthStage { start, password, sent, finish }

class AuthController extends GetxController {
  final AuthService _auth = Get.find();

  final email = TextEditingController();
  final password = TextEditingController();
  final stage = AuthStage.start.obs;
  final isSignUp = false.obs;
  final busy = false.obs;
  final googleBusy = false.obs;
  final obscure = true.obs;
  final resendIn = 0.obs;
  Timer? _timer;
  Worker? _linkWorker;

  bool get showApple =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void onInit() {
    super.onInit();
    // A sign-in link was opened on a device that doesn't know the email.
    void check(String? link) {
      if (link != null) stage.value = AuthStage.finish;
    }

    check(_auth.pendingEmailLink.value);
    _linkWorker = ever<String?>(_auth.pendingEmailLink, check);
  }

  bool _validEmail() {
    if (GetUtils.isEmail(email.text.trim())) return true;
    Ui.toast('Enter your email address.', error: true);
    return false;
  }

  /// Passwordless: send a one-tap sign-in link.
  Future<void> sendLink() async {
    if (!_validEmail()) return;
    final ok = await Ui.attempt(() async {
      await _auth.sendSignInLink(email.text);
      return true;
    }, busy: busy);
    if (ok == true) {
      stage.value = AuthStage.sent;
      _startCooldown();
    }
  }

  void _startCooldown() {
    resendIn.value = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      resendIn.value--;
      if (resendIn.value <= 0) t.cancel();
    });
  }

  Future<void> finishLink() async {
    final link = _auth.pendingEmailLink.value;
    if (link == null || !_validEmail()) return;
    await Ui.attempt(() => _auth.completeSignInLink(link, email: email.text), busy: busy);
  }

  Future<void> submitPassword() async {
    if (!_validEmail()) return;
    if (password.text.length < 6) return Ui.toast('Your password needs at least 6 characters.', error: true);
    final e = email.text.trim();
    await Ui.attempt(
      () => isSignUp.value ? _auth.signUp(e, password.text) : _auth.signIn(e, password.text),
      busy: busy,
    );
  }

  Future<void> google() => Ui.attempt(_auth.signInWithGoogle, busy: googleBusy);
  Future<void> apple() => Ui.attempt(_auth.signInWithApple, busy: googleBusy);

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

  void back() => stage.value = AuthStage.start;

  @override
  void onClose() {
    _timer?.cancel();
    _linkWorker?.dispose();
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
      body: Stack(
        children: [
          const Positioned.fill(child: DriftingBlobs()),
          SafeArea(
            child: Narrow(
              maxWidth: 460,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                children: [
                  const Align(alignment: Alignment.centerLeft, child: AppMark(size: 58)).pop(context),
                  const SizedBox(height: 22),
                  Text(
                    'Split bills,\nnot friendships.',
                    style: theme.textTheme.headlineLarge?.copyWith(height: 1.08),
                  ).enter(context, index: 1),
                  const SizedBox(height: 10),
                  Text(
                    AppConfig.tagline,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
                  ).enter(context, index: 2),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Feature(icon: Icons.meeting_room_outlined, label: 'Rooms by code'),
                      _Feature(icon: Icons.bolt_rounded, label: 'Live balances'),
                      _Feature(icon: Icons.event_repeat_rounded, label: 'Monthly bills'),
                    ],
                  ).enter(context, index: 3),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      boxShadow: Brand.soft(context),
                    ),
                    child: Obx(
                      () => AnimatedSize(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a),
                              child: child,
                            ),
                          ),
                          child: switch (controller.stage.value) {
                            AuthStage.start => const _Start(key: ValueKey('start')),
                            AuthStage.password => const _Password(key: ValueKey('password')),
                            AuthStage.sent => const _Sent(key: ValueKey('sent')),
                            AuthStage.finish => const _Finish(key: ValueKey('finish')),
                          },
                        ),
                      ),
                    ),
                  ).enter(context, index: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Google's four-colour "G", drawn so no image asset is needed.
class GoogleG extends StatelessWidget {
  const GoogleG({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => const SweepGradient(
        colors: [Color(0xFFEA4335), Color(0xFFFBBC05), Color(0xFF34A853), Color(0xFF4285F4), Color(0xFFEA4335)],
        stops: [0.0, 0.3, 0.55, 0.8, 1.0],
      ).createShader(r),
      child: Text(
        'G',
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.white, height: 1),
      ),
    );
  }
}

class _Start extends GetView<AuthController> {
  const _Start({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => PressScale(
            child: FilledButton.tonal(
              onPressed: controller.googleBusy.value ? null : controller.google,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerLowest,
                foregroundColor: theme.colorScheme.onSurface,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GoogleG(),
                  const SizedBox(width: 12),
                  Text(controller.googleBusy.value ? 'Connecting…' : 'Continue with Google'),
                ],
              ),
            ),
          ),
        ),
        if (controller.showApple) ...[
          const SizedBox(height: 10),
          PressScale(
            child: FilledButton.icon(
              onPressed: controller.apple,
              style: FilledButton.styleFrom(
                backgroundColor: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
              ),
              icon: const Icon(Icons.apple, size: 22),
              label: const Text('Continue with Apple'),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or with email', style: theme.textTheme.labelMedium?.copyWith(color: muted)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
        ),
        TextField(
          controller: controller.email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          onSubmitted: (_) => controller.sendLink(),
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        ),
        const SizedBox(height: 12),
        Obx(
          () => BusyButton(
            label: 'Email me a sign-in link',
            icon: Icons.auto_awesome_rounded,
            busy: controller.busy.value,
            onPressed: controller.sendLink,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_open_rounded, size: 14, color: muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'No password needed. Works for new and existing accounts.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => controller.stage.value = AuthStage.password,
          child: const Text('Use a password instead'),
        ),
      ],
    );
  }
}

class _Password extends GetView<AuthController> {
  const _Password({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(tooltip: 'Back', onPressed: controller.back, icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 4),
            Text('Use a password', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        Obx(
          () => SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Sign in')),
              ButtonSegment(value: true, label: Text('Create account')),
            ],
            selected: {controller.isSignUp.value},
            onSelectionChanged: (s) => controller.isSignUp.value = s.first,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller.email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        ),
        const SizedBox(height: 12),
        Obx(
          () => TextField(
            controller: controller.password,
            obscureText: controller.obscure.value,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => controller.submitPassword(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: controller.obscure.value ? 'Show password' : 'Hide password',
                icon: Icon(controller.obscure.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: controller.obscure.toggle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Obx(
          () => BusyButton(
            label: controller.isSignUp.value ? 'Create account' : 'Sign in',
            busy: controller.busy.value,
            onPressed: controller.submitPassword,
          ),
        ),
        Obx(
          () => controller.isSignUp.value
              ? const SizedBox(height: 8)
              : TextButton(onPressed: controller.forgot, child: const Text('Forgot password?')),
        ),
      ],
    );
  }
}

class _Sent extends GetView<AuthController> {
  const _Sent({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        const SizedBox(height: 6),
        FloatingIcon(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: Brand.hero(context),
              shape: BoxShape.circle,
              boxShadow: Brand.glow(context),
            ),
            child: const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 40),
          ),
        ).pop(context),
        const SizedBox(height: 18),
        Text('Check your inbox', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'We sent a sign-in link to '),
              TextSpan(
                text: controller.email.text.trim(),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '. Open it on this device and you\'re in.'),
            ],
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.45),
        ),
        const SizedBox(height: 18),
        Obx(
          () => SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: controller.resendIn.value > 0 || controller.busy.value ? null : controller.sendLink,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(controller.resendIn.value > 0 ? 'Resend in ${controller.resendIn.value}s' : 'Resend link'),
            ),
          ),
        ),
        TextButton(onPressed: controller.back, child: const Text('Use a different email')),
      ],
    );
  }
}

class _Finish extends GetView<AuthController> {
  const _Finish({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Confirm your email', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          'You opened a sign-in link on a different device. Enter the email it was sent to.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: controller.email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => controller.finishLink(),
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
        ),
        const SizedBox(height: 14),
        Obx(() => BusyButton(label: 'Sign in', busy: controller.busy.value, onPressed: controller.finishLink)),
      ],
    );
  }
}
