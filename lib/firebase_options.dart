// PLACEHOLDER - this file is replaced by the FlutterFire CLI.
//
// Connect the app to the Firebase project by running, from the project root:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=split-up-cd996
//
// That command registers the Android / iOS / web apps in the project and
// overwrites this file with the real keys. Until then the app only runs
// against the local emulators (--dart-define=USE_EMULATOR=true).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase is not configured yet. Run '
      '"flutterfire configure --project=split-up-cd996" to generate '
      'lib/firebase_options.dart, or start the app with '
      '--dart-define=USE_EMULATOR=true to use the local emulators.',
    );
  }
}
