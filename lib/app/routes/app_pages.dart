import 'package:get/get.dart';

import '../../modules/activity/activity_view.dart';
import '../../modules/auth/auth_view.dart';
import '../../modules/home/home_view.dart';
import '../../modules/join_room/join_room_view.dart';
import '../../modules/notifications/notifications_view.dart';
import '../../modules/profile/profile_view.dart';
import '../../modules/recurring/recurring_view.dart';
import '../../modules/room/create_room_view.dart';
import '../../modules/room/room_view.dart';
import '../../modules/room_settings/room_settings_view.dart';
import '../../modules/split_detail/split_detail_view.dart';
import '../../modules/split_form/split_form_view.dart';
import '../bindings/initial_binding.dart';
import 'app_routes.dart';

class AppPages {
  AppPages._();

  static final _guard = [AuthGuard()];
  static String get _room => Get.parameters['roomId'] ?? '';
  static String get _split => Get.parameters['splitId'] ?? '';

  static final pages = <GetPage<dynamic>>[
    GetPage(name: Routes.splash, page: () => const SplashView(), transition: Transition.fadeIn),
    GetPage(
      name: Routes.auth,
      page: () => const AuthView(),
      binding: BindingsBuilder(() => Get.lazyPut(() => AuthController())),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: Routes.profileSetup,
      page: () => const ProfileView(setup: true),
      binding: BindingsBuilder(() => Get.lazyPut(() => ProfileController())),
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: Routes.profile,
      page: () => const ProfileView(),
      binding: BindingsBuilder(() => Get.lazyPut(() => ProfileController())),
      middlewares: _guard,
    ),
    GetPage(
      name: Routes.home,
      page: () => const HomeView(),
      binding: BindingsBuilder(() => Get.lazyPut(() => HomeController())),
      middlewares: _guard,
      transition: Transition.fadeIn,
    ),
    GetPage(
      name: Routes.createRoom,
      page: () => const CreateRoomView(),
      binding: BindingsBuilder(() => Get.lazyPut(() => CreateRoomController())),
      middlewares: _guard,
    ),
    GetPage(
      name: Routes.join,
      page: () => const JoinRoomView(),
      binding: BindingsBuilder(() => Get.lazyPut(() => JoinRoomController())),
      middlewares: _guard,
    ),
    GetPage(
      name: Routes.notifications,
      page: () => const NotificationsView(),
      binding: BindingsBuilder(() => Get.lazyPut(() => NotificationsController())),
      middlewares: _guard,
    ),
    // Room screens create their own controller (see Scoped), so the same
    // screen can be open for two rooms at once.
    GetPage(name: Routes.roomPattern, page: () => RoomView(roomId: _room), middlewares: _guard),
    GetPage(name: Routes.roomSettingsPattern, page: () => RoomSettingsView(roomId: _room), middlewares: _guard),
    GetPage(name: Routes.recurringPattern, page: () => RecurringView(roomId: _room), middlewares: _guard),
    GetPage(name: Routes.activityPattern, page: () => ActivityView(roomId: _room), middlewares: _guard),
    GetPage(name: Routes.splitNewPattern, page: () => SplitFormView(roomId: _room), middlewares: _guard),
    GetPage(
      name: Routes.splitPattern,
      page: () => SplitDetailView(roomId: _room, splitId: _split),
      middlewares: _guard,
    ),
    GetPage(
      name: Routes.splitEditPattern,
      page: () => SplitFormView(roomId: _room, splitId: _split),
      middlewares: _guard,
    ),
  ];
}
