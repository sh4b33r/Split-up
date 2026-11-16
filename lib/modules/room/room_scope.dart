import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../app/routes/app_routes.dart';
import '../../core/services/api.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/live_controller.dart';
import '../../core/utils/ui.dart';
import '../../data/models/models.dart';
import '../../data/repositories/repositories.dart';

/// Owns one controller for as long as its screen is on the stack.
///
/// Room screens are opened with different ids (and sometimes the same room
/// twice, e.g. from a notification), so each screen gets its own controller
/// instead of sharing one through the global registry.
class Scoped<T extends GetxController> extends StatefulWidget {
  const Scoped({super.key, required this.create, required this.builder});
  final T Function() create;
  final Widget Function(BuildContext context, T controller) builder;

  @override
  State<Scoped<T>> createState() => _ScopedState<T>();
}

class _ScopedState<T extends GetxController> extends State<Scoped<T>> {
  late final T _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.create()..onStart();
  }

  @override
  void dispose() {
    _controller.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

/// Base for every screen inside a room: the live room document, its members,
/// and what the signed-in user is allowed to do there.
abstract class RoomScope extends LiveController {
  RoomScope(this.roomId);
  final String roomId;

  final AuthService auth = Get.find();
  final Api api = Get.find();

  final room = Rxn<Room>();
  final members = <Member>[].obs;
  final busy = false.obs;

  String get uid => auth.uid;
  String get currency => room.value?.currency ?? 'QAR';
  bool get isOwner => room.value?.ownerId == uid;

  /// Owner or admin.
  bool get isManager => room.value?.isManager(uid) ?? false;

  List<Member> get activeMembers {
    final list = members.where((m) => m.isActive).toList();
    // Me first, then alphabetical: also the order leftover cents are assigned in.
    list.sort((a, b) {
      if (a.uid == uid) return -1;
      if (b.uid == uid) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  Member member(String id) => members.firstWhereOrNull((m) => m.uid == id) ?? Member.unknown(id);

  /// "You" for the signed-in user, otherwise their display name.
  String nameOf(String id) => id == uid ? 'You' : member(id).displayName;

  @override
  void onInit() {
    super.onInit();
    final repo = Get.find<RoomRepo>();
    watch(repo.room(roomId), (r) {
      if (r == null || !r.memberIds.contains(uid)) return _gone();
      room.value = r;
    }, onError: (_) => _gone());
    watch(repo.members(roomId), members.assignAll);
  }

  /// The room was deleted, or we were removed from it.
  void _gone() {
    if (!Get.currentRoute.startsWith(Routes.room(roomId))) return;
    Get.offAllNamed(Routes.home);
    Ui.toast("You're no longer in that room.");
  }
}
