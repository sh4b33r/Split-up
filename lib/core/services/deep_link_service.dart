import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../app/app_config.dart';
import '../../app/routes/app_routes.dart';
import '../utils/ui.dart';
import 'auth_service.dart';

/// Invite links: `https://<host>/j/<token>` (Android App Links / iOS Universal
/// Links / the web app) and `splitup://j/<token>`.
///
/// A link opened before sign-in is remembered, so the app goes straight to the
/// room's join screen once the user is in.
class DeepLinkService extends GetxService {
  /// An invite token waiting for the user to be signed in.
  String? pendingToken;
  StreamSubscription<Uri>? _sub;

  @override
  void onInit() {
    super.onInit();
    if (kIsWeb) {
      pendingToken = tokenFrom(Uri.base);
      _maybeSignInLink(Uri.base);
      return;
    }
    try {
      final links = AppLinks();
      _sub = links.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (e) {
      debugPrint('deep links unavailable: $e');
    }
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  /// Extracts the invite token from a link, or null if it is not an invite.
  static String? tokenFrom(Uri uri) {
    final List<String> parts;
    if (uri.scheme == AppConfig.inviteScheme) {
      // splitup://j/<token>: "j" is parsed as the host
      parts = [uri.host, ...uri.pathSegments];
    } else {
      parts = uri.pathSegments;
    }
    final segments = parts.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments[0] == 'j' && RegExp(r'^[A-Za-z0-9_-]{6,64}$').hasMatch(segments[1])) {
      return segments[1];
    }
    return null;
  }

  /// A passwordless sign-in link from the email we sent.
  bool _maybeSignInLink(Uri uri) {
    final auth = Get.find<AuthService>();
    final link = uri.toString();
    if (!auth.isSignInLink(link)) return false;
    auth.completeSignInLink(link).catchError((Object e) => Ui.toast(Ui.messageOf(e), error: true));
    return true;
  }

  void _handle(Uri uri) {
    if (_maybeSignInLink(uri)) return;
    final token = tokenFrom(uri);
    if (token == null) return;
    if (Get.find<AuthService>().status.value == AuthStatus.ready) {
      Get.toNamed(Routes.join, arguments: token);
    } else {
      pendingToken = token;
    }
  }

  /// Called by Home once it is on screen.
  void flushPending() {
    final token = pendingToken;
    pendingToken = null;
    if (token != null) Get.toNamed(Routes.join, arguments: token);
  }
}
