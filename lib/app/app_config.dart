/// App-wide settings. Values with `fromEnvironment` can be overridden at build
/// time with `--dart-define=NAME=value`.
class AppConfig {
  AppConfig._();

  static const appName = 'SplitRoom';
  static const tagline = 'Share a room. Split the bills. See who owes whom.';

  /// Run against the local Firebase emulators instead of the real project:
  /// `flutter run --dart-define=USE_EMULATOR=true`
  static const useEmulator = bool.fromEnvironment('USE_EMULATOR');

  /// Host of the emulators. Leave empty for the default
  /// (10.0.2.2 on an Android emulator, localhost elsewhere).
  static const emulatorHost = String.fromEnvironment('EMULATOR_HOST');

  /// Must match REGION in functions/src/config.ts.
  static const functionsRegion = 'us-central1';

  /// Host that serves invite links (Firebase Hosting for the project).
  static const inviteHost = String.fromEnvironment(
    'INVITE_HOST',
    defaultValue: 'split-up-cd996.web.app',
  );

  /// Custom URL scheme that also opens the app: `splitup://j/<token>`
  static const inviteScheme = 'splitup';

  static String inviteLink(String token) => 'https://$inviteHost/j/$token';

  static const defaultCurrency = 'QAR';
}
