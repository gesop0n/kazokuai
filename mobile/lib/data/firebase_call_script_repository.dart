import 'package:firebase_auth/firebase_auth.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/call_script_repository.dart';

// ログインした家族の ID トークンで、バックエンドに通話内容の案を頼む
class FirebaseCallScriptRepository implements CallScriptRepository {
  FirebaseCallScriptRepository({required this._auth, required this._backend});

  final FirebaseAuth _auth;
  final Backend _backend;

  @override
  Future<String> draft({required String message}) async {
    final String? idToken;
    try {
      idToken = await _auth.currentUser?.getIdToken();
    } on FirebaseAuthException {
      throw const CallScriptException();
    }
    if (idToken == null) throw const CallScriptException();
    return _backend.draftCallScript(idToken: idToken, message: message);
  }
}
