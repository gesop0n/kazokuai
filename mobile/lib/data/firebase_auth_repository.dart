import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:kazokuai/data/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  // currentUser は Firebase.initializeApp のあとすぐに読める。
  // ログインしたままの家族を、起動した直後からログインしているとみなせる
  FirebaseAuthRepository(this._auth)
    : _signedIn = ValueNotifier(_auth.currentUser != null),
      _account = ValueNotifier(
        _auth.currentUser == null ? null : _familyAccount(_auth.currentUser!),
      ) {
    // ログインの切り替わりに加え、表示名を保存したあとも届く
    _subscription = _auth.userChanges().listen((user) {
      _signedIn.value = user != null;
      _account.value = user == null ? null : _familyAccount(user);
    });
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
  final ValueNotifier<FamilyAccount?> _account;
  late final StreamSubscription<User?> _subscription;

  @override
  ValueListenable<bool> get signedIn => _signedIn;

  @override
  ValueListenable<FamilyAccount?> get account => _account;

  @override
  Future<void> signInWithGoogle() async {
    // 閉じたポップアップは、画面に何も出さない。
    // 新しいアカウントかどうかは、ここでは分けない。見守る方がいなければ L3 になる。
    try {
      await _auth.signInWithPopup(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user') return;
      throw const SignInException(SignInError.other);
    }
  }

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

  @override
  Future<void> updateName(String name) async {
    final user = _auth.currentUser;
    if (user == null) throw const UpdateNameException();
    try {
      await user.updateDisplayName(name);
      await user.reload();
    } on FirebaseAuthException {
      throw const UpdateNameException();
    }
    final refreshed = _auth.currentUser;
    if (refreshed != null) _account.value = _familyAccount(refreshed);
  }

  void dispose() {
    _subscription.cancel();
    _signedIn.dispose();
    _account.dispose();
  }
}

FamilyAccount _familyAccount(User user) => FamilyAccount(
  name: user.displayName ?? '',
  email: user.email ?? '',
  signInMethod: _signInMethod(user),
  registeredOn: user.metadata.creationTime,
);

// Google で入っているときは、それをログイン方法にする。なければメールアドレス
SignInMethod _signInMethod(User user) {
  for (final info in user.providerData) {
    if (info.providerId == 'google.com') return SignInMethod.google;
  }
  return SignInMethod.emailAndPassword;
}
