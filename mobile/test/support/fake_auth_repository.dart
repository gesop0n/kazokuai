import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/auth_repository.dart';

// メールアドレスとパスワードの組を覚えておき、一致したときだけログインする
// モックの 08e と同じ、見本の家族
final sampleFamilyAccount = FamilyAccount(
  name: '田中 太郎',
  email: 'tanaka.taro@example.com',
  signInMethod: SignInMethod.emailAndPassword,
  registeredOn: DateTime(2026, 11, 5),
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    bool signedIn = false,
    Map<String, String> accounts = const {},
    this.unreachable = false,
    this.resetFailures = 0,
    this.nameUpdateFails = false,
    FamilyAccount? account,
  }) : signedIn = ValueNotifier(signedIn),
       account = ValueNotifier(account),
       accounts = Map<String, String>.of(accounts);

  @override
  final ValueNotifier<bool> signedIn;

  @override
  final ValueNotifier<FamilyAccount?> account;

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

  // true のときは、名前を保存できない
  bool nameUpdateFails;

  // テストが complete するまで、Google のポップアップを開いたままにする
  Completer<void>? pendingGoogleSignIn;

  // true のときは、ポップアップを閉じたことにする。ログインせず、失敗にもしない
  bool googlePopupClosed = false;

  // updateName に渡された、いちばん新しい名前。失敗したときも残る
  String? submittedName;

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
  Future<void> signInWithGoogle() async {
    final pending = pendingGoogleSignIn;
    if (pending != null) await pending.future;
    if (googlePopupClosed) return;
    if (unreachable) throw const SignInException(SignInError.other);
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
    account.value = null;
  }

  @override
  Future<void> updateName(String name) async {
    submittedName = name;
    if (nameUpdateFails) throw const UpdateNameException();
    final current = account.value;
    if (current == null) throw const UpdateNameException();
    account.value = FamilyAccount(
      name: name,
      email: current.email,
      signInMethod: current.signInMethod,
      registeredOn: current.registeredOn,
    );
  }
}

// ログインしている家族としてアプリを開く。08e の見本も入っている
Override signedInAuth() => authRepositoryProvider.overrideWithValue(
  FakeAuthRepository(signedIn: true, account: sampleFamilyAccount),
);
