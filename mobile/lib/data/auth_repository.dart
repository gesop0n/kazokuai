import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_auth_repository.dart';

// 新規登録の画面に出す文字数。Firebase の既定より長くして、モックの案内に合わせる
const minPasswordLength = 8;

// 家族のアカウント。画面はこれだけを使い、Firebase の型には触れない
abstract interface class AuthRepository {
  // 家族がログインしているかどうか。起動した直後から正しい値を持つ
  ValueListenable<bool> get signedIn;

  // ログインできなかったときは SignInException を投げる
  Future<void> signIn({required String email, required String password});

  // アカウントを作る。作れるとログインした状態になる。
  // 作れなかったときは CreateAccountException を投げる
  Future<void> createAccount({required String email, required String password});
}

enum SignInError {
  // メールアドレスかパスワードが違う
  wrongCredentials,
  // 通信できないときなど、それ以外の理由
  other,
}

class SignInException implements Exception {
  const SignInException(this.error);

  final SignInError error;

  @override
  String toString() => 'SignInException($error)';
}

enum CreateAccountError {
  // そのメールアドレスのアカウントがすでにある
  emailInUse,
  // パスワードが minPasswordLength より短い、または Firebase が弱いと判断した
  weakPassword,
  // 通信できないときなど、それ以外の理由
  other,
}

class CreateAccountException implements Exception {
  const CreateAccountException(this.error);

  final CreateAccountError error;

  @override
  String toString() => 'CreateAccountException($error)';
}

// テストでは偽物に差し替える
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = FirebaseAuthRepository(FirebaseAuth.instance);
  ref.onDispose(repository.dispose);
  return repository;
});
