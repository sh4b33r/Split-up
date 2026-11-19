import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../../app/routes/app_routes.dart';
import '../utils/ui.dart';

/// Push notifications through Firebase Cloud Messaging.
///
/// In the background the system shows the notification itself. In the
/// foreground we show a short in-app message instead; the same event is
/// always in the in-app inbox as well.
class PushService extends GetxService {
  /// Push needs a real device and the real Firebase project.
  bool get supported =>
      !kIsWeb &&
      !AppConfig.useEmulator &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  String? _token;
  String? _uid;
  Map<String, dynamic>? _pendingOpen;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Registers this device for the signed-in user. Safe to call more than once.
  Future<void> start(String uid) async {
    if (!supported || _uid == uid) return;
    _uid = uid;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      // The server sends to FCM registration tokens (see functions/src/notify.ts),
      // so the token API is used here rather than the newer installation-id one.
      // ignore: deprecated_member_use
      await _save(await messaging.getToken());
      _subs
        // ignore: deprecated_member_use
        ..add(messaging.onTokenRefresh.listen(_save))
        ..add(
          FirebaseMessaging.onMessage.listen((m) {
            final n = m.notification;
            if (n != null) Ui.toast([n.title, n.body].whereType<String>().join('\n'));
          }),
        )
        ..add(FirebaseMessaging.onMessageOpenedApp.listen((m) => open(m.data)));
      final initial = await messaging.getInitialMessage();
      if (initial != null) open(initial.data);
    } catch (e) {
      debugPrint('push: could not start ($e)');
    }
  }

  Future<void> _save(String? token) async {
    final uid = _uid;
    if (token == null || uid == null) return;
    _token = token;
    await FirebaseFirestore.instance.doc('users/$uid').set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Removes this device's token on sign-out.
  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    final token = _token;
    _uid = null;
    _token = null;
    if (!supported || uid == null || token == null) return;
    try {
      await FirebaseFirestore.instance.doc('users/$uid').update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  /// Tapping a notification deep-links to the split (or room) it is about.
  void open(Map<String, dynamic> data) {
    if (Get.currentRoute != Routes.home && !Get.currentRoute.startsWith('/room')) {
      // Not on a signed-in screen yet: keep it until Home is showing.
      _pendingOpen = data;
      return;
    }
    openTarget(roomId: data['roomId'] as String?, splitId: data['splitId'] as String?);
  }

  /// Called by Home once it is on screen.
  void flushPending() {
    final data = _pendingOpen;
    _pendingOpen = null;
    if (data != null) openTarget(roomId: data['roomId'] as String?, splitId: data['splitId'] as String?);
  }

  static void openTarget({String? roomId, String? splitId}) {
    if (roomId == null || roomId.isEmpty) return;
    if (splitId != null && splitId.isNotEmpty) {
      Get.toNamed(Routes.split(roomId, splitId));
    } else {
      Get.toNamed(Routes.room(roomId));
    }
  }
}
