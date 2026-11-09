import 'package:firebase_auth/firebase_auth.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/immediate_call_repository.dart';

// ログインした家族の ID トークンで、バックエンドの今すぐ通話を呼ぶ
class FirebaseImmediateCallRepository implements ImmediateCallRepository {
  FirebaseImmediateCallRepository({
    required this._auth,
    required this._backend,
  });

  final FirebaseAuth _auth;
  final Backend _backend;

  @override
  Future<void> start({required String message, required String script}) async {
    final String? idToken;
    try {
      idToken = await _auth.currentUser?.getIdToken();
    } on FirebaseAuthException {
      throw const ImmediateCallException();
    }
    if (idToken == null) throw const ImmediateCallException();
    await _backend.startImmediateCall(
      idToken: idToken,
      message: message,
      script: script,
    );
  }
}
