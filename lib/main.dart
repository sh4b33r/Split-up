import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:get/get.dart';

import 'app/app_config.dart';
import 'app/bindings/initial_binding.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'app/theme/app_theme.dart';
import 'firebase_options.dart';

/// Options for the local emulators. No real project or keys are involved.
const _emulatorOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:web:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-splitup',
  storageBucket: 'demo-splitup.appspot.com',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (AppConfig.useEmulator) {
      await Firebase.initializeApp(options: _emulatorOptions);
      final host = AppConfig.emulatorHost.isNotEmpty
          ? AppConfig.emulatorHost
          : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost');
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion).useFunctionsEmulator(host, 5001);
      await FirebaseStorage.instance.useStorageEmulator(host, 9199);
    } else {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } on UnsupportedError catch (e) {
    runApp(SetupNeededApp(message: e.message ?? 'Firebase is not configured for this platform.'));
    return;
  }
  // Lets browser automation and screen readers see the web app straight away.
  if (kIsWeb && const bool.fromEnvironment('FORCE_SEMANTICS')) {
    SemanticsBinding.instance.ensureSemantics();
  }
  runApp(const SplitRoomApp());
}

class SplitRoomApp extends StatelessWidget {
  const SplitRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialBinding: InitialBinding(),
      initialRoute: Routes.splash,
      getPages: AppPages.pages,
      defaultTransition: Transition.cupertino,
    );
  }
}

/// Shown when the app is started before `flutterfire configure` has been run.
class SetupNeededApp extends StatelessWidget {
  const SetupNeededApp({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.build_circle_outlined, size: 56),
                  const SizedBox(height: 16),
                  Text('One more setup step', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
