import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/services/api.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/deep_link_service.dart';
import '../../core/services/push_service.dart';
import '../../core/services/storage_service.dart';
import '../../data/repositories/repositories.dart';
import '../routes/app_routes.dart';

/// App-wide services and repositories, created once at start-up.
class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(Api(), permanent: true);
    Get.put(StorageService(), permanent: true);
    Get.put(PushService(), permanent: true);
    Get.put(RoomRepo(), permanent: true);
    Get.put(SplitRepo(), permanent: true);
    Get.put(ShareRepo(), permanent: true);
    Get.put(InviteRepo(), permanent: true);
    Get.put(NotificationRepo(), permanent: true);
    Get.put(AuthService(), permanent: true);
    Get.put(DeepLinkService(), permanent: true);
    Get.put(SessionController(), permanent: true);
  }
}

/// Moves the user between the sign-in screen, profile setup and home as
/// their sign-in state changes.
class SessionController extends GetxController {
  final AuthService _auth = Get.find();

  static const _entryRoutes = {Routes.splash, Routes.auth, Routes.profileSetup};

  @override
  void onReady() {
    super.onReady();
    ever<AuthStatus>(_auth.status, _route);
    _route(_auth.status.value);
  }

  void _route(AuthStatus status) {
    final current = Get.currentRoute;
    switch (status) {
      case AuthStatus.loading:
        break;
      case AuthStatus.signedOut:
        if (current != Routes.auth) Get.offAllNamed(Routes.auth);
      case AuthStatus.needsProfile:
        if (current != Routes.profileSetup) Get.offAllNamed(Routes.profileSetup);
      case AuthStatus.ready:
        Get.find<PushService>().start(_auth.uid);
        if (_entryRoutes.contains(current) || current.isEmpty) Get.offAllNamed(Routes.home);
    }
  }
}

/// Sends anyone who is not signed in (for example after a browser refresh on
/// a deep page) back through the splash screen.
class AuthGuard extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    final ready = Get.isRegistered<AuthService>() && Get.find<AuthService>().status.value == AuthStatus.ready;
    return ready ? null : const RouteSettings(name: Routes.splash);
  }
}
