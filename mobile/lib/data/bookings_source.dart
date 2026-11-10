import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kazokuai/features/booking/booking_data.dart';

// Firestore の予約 1 件を、画面の型にする。時刻か文がなければ null。
// 伝えたいことと通話内容の前後の空白は除く。
BookedCall? bookedCallFrom(String id, Map<String, dynamic> data) {
  final at = _date(data['at']);
  if (at == null) return null;
  final message = _string(data['message']).trim();
  final script = _string(data['script']).trim();
  if (message.isEmpty || script.isEmpty) return null;
  return BookedCall(
    id: id,
    at: at,
    message: message,
    script: script,
    called: data['called'] == true,
  );
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

String _string(Object? value) => value is String ? value : '';
