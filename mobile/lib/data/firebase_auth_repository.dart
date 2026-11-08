import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:kazokuai/data/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  // currentUser は Firebase.initializeApp のあとすぐに読める。
  // ログインしたままの家族を、起動した直後からログインしているとみなせる
  FirebaseAuthRepository(this._auth)
    : _signedIn = ValueNotifier(_auth.currentUser != null) {
    _subscription = _auth.authStateChanges().listen(
      (user) => _signedIn.value = user != null,
    );
  }

  // メールアドレスの列挙を防ぐ設定のプロジェクトでは、どちらが違っても invalid-credential が返る
  static const _wrongCredentialsCodes = {
    'invalid-credential',
    'invalid-email',
    'user-not-found',
    'wrong-password',
  };

  final FirebaseAuth _auth;
  final ValueNotifier<bool> _signedIn;
  late final StreamSubscription<User?> _subscription;

  @override
  ValueListenable<bool> get signedIn => _signedIn;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw SignInException(
        _wrongCredentialsCodes.contains(e.code)
            ? SignInError.wrongCredentials
            : SignInError.other,
      );
    }
  }

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    // 短いパスワードはエミュレーターへ送らず、画面の案内と同じ理由で断る
    if (password.length < minPasswordLength) {
      throw const CreateAccountException(CreateAccountError.weakPassword);
    }
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw CreateAccountException(switch (e.code) {
        'email-already-in-use' => CreateAccountError.emailInUse,
        'weak-password' => CreateAccountError.weakPassword,
        _ => CreateAccountError.other,
      });
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException {
      throw const PasswordResetException();
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  void dispose() {
    _subscription.cancel();
    _signedIn.dispose();
  }
}
