import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../data/models/models.dart';
import 'api.dart';
import 'push_service.dart';

enum AuthStatus { loading, signedOut, needsProfile, ready }

/// Who is signed in, their profile document, and where that puts them in the
/// app (sign-in screen, profile setup, or home).
class AuthService extends GetxService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Rxn<User> user = Rxn<User>();
  final Rxn<AppUser> profile = Rxn<AppUser>();
  final Rx<AuthStatus> status = AuthStatus.loading.obs;
  final RxBool emailVerified = false.obs;

  StreamSubscription<User?>? _userSub;
  StreamSubscription<Doc>? _profileSub;
  String? _watchingUid;
  bool _googleReady = false;

  /// The signed-in user's id. Only call on screens behind sign-in.
  String get uid => user.value!.uid;
  String? get email => user.value?.email?.toLowerCase();
  String get displayName => profile.value?.name ?? '';

  @override
  void onInit() {
    super.onInit();
    _userSub = _auth.userChanges().listen(_onUser);
  }

  @override
  void onClose() {
    _userSub?.cancel();
    _profileSub?.cancel();
    super.onClose();
  }

  void _onUser(User? u) {
    user.value = u;
    emailVerified.value = u?.emailVerified ?? false;
    if (u == null) {
      _watchingUid = null;
      _profileSub?.cancel();
      profile.value = null;
      status.value = AuthStatus.signedOut;
      return;
    }
    if (_watchingUid == u.uid) return;
    _watchingUid = u.uid;
    status.value = AuthStatus.loading;
    _profileSub?.cancel();
    _profileSub = FirebaseFirestore.instance.doc('users/${u.uid}').snapshots().listen(
      (doc) {
        // A cached "missing" result says nothing yet: wait for the server.
        if (!doc.exists && doc.metadata.isFromCache) return;
        final p = AppUser.fromDoc(doc);
        profile.value = p;
        status.value = p.name.trim().isEmpty ? AuthStatus.needsProfile : AuthStatus.ready;
      },
      onError: (_) => status.value = AuthStatus.needsProfile,
    );
  }

  // ---- sign in ---------------------------------------------------------------

  Future<void> signIn(String email, String password) =>
      _guard(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));

  Future<void> signUp(String email, String password) => _guard(() async {
        final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
        // Email invites are only shown to verified addresses.
        try {
          await cred.user?.sendEmailVerification();
        } catch (_) {}
      });

  Future<void> sendPasswordReset(String email) => _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  Future<void> signInWithGoogle() => _guard(() async {
        if (kIsWeb) {
          await _auth.signInWithPopup(GoogleAuthProvider());
          return;
        }
        if (!_googleReady) {
          await GoogleSignIn.instance.initialize();
          _googleReady = true;
        }
        final GoogleSignInAccount account;
        try {
          account = await GoogleSignIn.instance.authenticate();
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) return;
          throw const ApiException("Google sign-in didn't work. Please try again.");
        }
        final idToken = account.authentication.idToken;
        if (idToken == null) throw const ApiException("Google sign-in didn't work. Please try again.");
        await _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      });

  Future<void> signInWithApple() => _guard(() async {
        final provider = AppleAuthProvider()
          ..addScope('email')
          ..addScope('name');
        if (kIsWeb) {
          await _auth.signInWithPopup(provider);
        } else {
          await _auth.signInWithProvider(provider);
        }
      });

  Future<void> sendVerificationEmail() => _guard(() async => _auth.currentUser?.sendEmailVerification());

  /// Re-reads the account after the user says they tapped the verification link.
  Future<bool> refreshVerification() async {
    final u = _auth.currentUser;
    if (u == null) return false;
    try {
      await u.reload();
      await _auth.currentUser?.getIdToken(true); // the new token carries email_verified
    } catch (_) {}
    emailVerified.value = _auth.currentUser?.emailVerified ?? false;
    return emailVerified.value;
  }

  Future<void> signOut() async {
    // Two accounts on one phone must not share a push token.
    if (Get.isRegistered<PushService>()) await Get.find<PushService>().stop();
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw ApiException(_message(e));
    }
  }

  String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return "That email address doesn't look right.";
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Wrong email or password.';
      case 'email-already-in-use':
        return 'That email already has an account. Sign in instead.';
      case 'weak-password':
        return 'Choose a password with at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return "Couldn't reach the server. Check your connection and try again.";
      case 'account-exists-with-different-credential':
        return 'That email is already registered with a different sign-in method.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'canceled':
      case 'web-context-canceled':
        return 'Sign-in was cancelled.';
      default:
        return "Sign-in didn't work. Please try again.";
    }
  }
}
