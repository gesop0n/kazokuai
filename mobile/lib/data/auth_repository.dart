import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/firebase_auth_repository.dart';

// 新規登録の画面に出す文字数。Firebase の既定より長くして、モックの案内に合わせる
const minPasswordLength = 8;

// 家族自身のアカウント。08e が出す。
// 名前は Firebase Auth の表示名。メールアドレス、ログイン方法、登録日も Auth が持つ。
class FamilyAccount {
  const FamilyAccount({
    required this.name,
    required this.email,
    required this.signInMethod,
    required this.registeredOn,
  });

  // あなたのお名前。まだ付けていないときは空
  final String name;
  final String email;
  final SignInMethod signInMethod;

  // アカウントを作った日。取れないときは null
  final DateTime? registeredOn;
}

enum SignInMethod {
  emailAndPassword('メールアドレスとパスワード'),
  google('Google');

  const SignInMethod(this.label);

  // 08e の「ログイン方法」に出す文
  final String label;
}

// あなたのお名前を保存できなかった
class UpdateNameException implements Exception {
  const UpdateNameException();

  @override
  String toString() => 'UpdateNameException';
}

// 家族のアカウント。画面はこれだけを使い、Firebase の型には触れない
abstract interface class AuthRepository {
  // 家族がログインしているかどうか。起動した直後から正しい値を持つ
  ValueListenable<bool> get signedIn;

  // ログインしている家族のアカウント。ログアウトしているときは null。
  // 名前を保存したあとも、ここが新しい名前になる
  ValueListenable<FamilyAccount?> get account;

  // ログインできなかったときは SignInException を投げる
  Future<void> signIn({required String email, required String password});

  // Web の Google のポップアップでログインする。
  // ポップアップを閉じたときは、ログインせずに戻る。
  // それ以外で失敗したときは SignInException(SignInError.other) を投げる。
  // ログインできると、メールアドレスのログインと同じく signedIn が true になる。
  // 新しいアカウントも、すでにあるアカウントも、ここはログインするだけ。
  // 見守る方がいなければルーターが L3 を、いればメールアドレスのログインのあとと同じ画面を開く。
  Future<void> signInWithGoogle();

  // アカウントを作る。作れるとログインした状態になる。
  // 作れなかったときは CreateAccountException を投げる
  Future<void> createAccount({required String email, required String password});

  // 再設定のメールを送る。送れなかったときは、理由を分けずに PasswordResetException を投げる
  Future<void> sendPasswordResetEmail({required String email});

  // ログアウトする。L6 の「もどる」が、ようこそ(L1)に戻るときに使う
  Future<void> signOut();

  // あなたのお名前を保存する。保存できなかったときは UpdateNameException を投げる
  Future<void> updateName(String name);
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

// 再設定のメールを送れなかった。画面は理由を分けない
class PasswordResetException implements Exception {
  const PasswordResetException();

  @override
  String toString() => 'PasswordResetException';
}

// Web だけ Google のポップアップを使う。iOS と Android は「準備中です」のまま。
// テストは true に差し替えて、Web の流れを確かめる。
final googleSignInOnWebProvider = Provider<bool>((ref) => kIsWeb);

// テストでは偽物に差し替える
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repository = FirebaseAuthRepository(FirebaseAuth.instance);
  ref.onDispose(repository.dispose);
  return repository;
});
