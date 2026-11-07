import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/auth_repository.dart';

// メールアドレスとパスワードの組を覚えておき、一致したときだけログインする
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    bool signedIn = false,
    this.accounts = const {},
    this.unreachable = false,
  }) : signedIn = ValueNotifier(signedIn);

  @override
  final ValueNotifier<bool> signedIn;

  // メールアドレスからパスワードを引く
  final Map<String, String> accounts;

  // true のときは、どのアカウントでも通信できずに失敗する
  final bool unreachable;

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
}

// ログインしている家族としてアプリを開く
Override signedInAuth() => authRepositoryProvider.overrideWithValue(
  FakeAuthRepository(signedIn: true),
);
