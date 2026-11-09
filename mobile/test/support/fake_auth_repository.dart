import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/auth_repository.dart';

// メールアドレスとパスワードの組を覚えておき、一致したときだけログインする
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    bool signedIn = false,
    Map<String, String> accounts = const {},
    this.unreachable = false,
    this.resetFailures = 0,
  }) : signedIn = ValueNotifier(signedIn),
       accounts = Map<String, String>.of(accounts);

  @override
  final ValueNotifier<bool> signedIn;

  // メールアドレスからパスワードを引く。登録すると増える
  final Map<String, String> accounts;

  // true のときは、どのアカウントでも通信できずに失敗する
  final bool unreachable;

  // createAccount に渡された、いちばん新しいメールアドレスとパスワード
  String? submittedEmail;
  String? submittedPassword;

  // sendPasswordResetEmail に渡されたメールアドレス。失敗したときも残る
  final List<String> resetEmails = [];

  // 0 より大きいあいだ、再設定のメールは送れない。送ろうとするたびに 1 減る
  int resetFailures;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (unreachable) {
      throw const SignInException(SignInError.other);
    }
    if (accounts[email] != password) {
      throw const SignInException(SignInError.wrongCredentials);
    }
    signedIn.value = true;
  }

  @override
  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    submittedEmail = email;
    submittedPassword = password;
    if (password.length < minPasswordLength) {
      throw const CreateAccountException(CreateAccountError.weakPassword);
    }
    if (unreachable) {
      throw const CreateAccountException(CreateAccountError.other);
    }
    if (accounts.containsKey(email)) {
      throw const CreateAccountException(CreateAccountError.emailInUse);
    }
    accounts[email] = password;
    signedIn.value = true;
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    resetEmails.add(email);
    if (unreachable || resetFailures > 0) {
      if (resetFailures > 0) resetFailures -= 1;
      throw const PasswordResetException();
    }
  }

  @override
  Future<void> signOut() async {
    signedIn.value = false;
  }
}

// ログインしている家族としてアプリを開く
Override signedInAuth() => authRepositoryProvider.overrideWithValue(
  FakeAuthRepository(signedIn: true),
);
