import 'package:firebase_auth/firebase_auth.dart';

import 'package:kazokuai/data/backend.dart';
import 'package:kazokuai/data/sync_repository.dart';

// ログインした家族の ID トークンで、バックエンドの同期を呼ぶ
class FirebaseSyncRepository implements SyncRepository {
  FirebaseSyncRepository({required this._auth, required this._backend});

  final FirebaseAuth _auth;
  final Backend _backend;

  @override
  Future<void> start() async {
    await _backend.startSync(idToken: await _idToken());
  }

  @override
  Future<void> sendCode(String code) async {
    await _backend.sendSyncCode(idToken: await _idToken(), code: code);
  }

  Future<String> _idToken() async {
    final String? idToken;
    try {
      idToken = await _auth.currentUser?.getIdToken();
    } on FirebaseAuthException {
      throw const SyncFailedException();
    }
    if (idToken == null) throw const SyncFailedException();
    return idToken;
  }
}
