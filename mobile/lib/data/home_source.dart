import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kazokuai/features/home/home_data.dart';

const _summaryMade = '作れた';
const _summaryNotMade = '作れなかった';
const _talked = '話した';
const _notTalked = '話していない';

// Firestore の見守る方と電話のドキュメントを、ホームの型にする。
// 直近の電話は期間に関係なくいちばん新しいもの、今日の様子はその日の最後の電話。
HomeView homeViewFrom({
  required Map<String, dynamic> person,
  required List<Map<String, dynamic>> calls,
  required DateTime now,
}) {
  final name = _string(person['name']);
  final callName = _string(person['callName']);
  final parsed = <Call>[];
  for (final data in calls) {
    final call = _callFrom(data);
    if (call != null) parsed.add(call);
  }
  parsed.sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final today = _dateOnly(now);
  Call? todayCall;
  for (final call in parsed) {
    if (_dateOnly(call.startedAt) == today) {
      todayCall = call;
      break;
    }
  }

  return HomeView(
    person: WatchedPerson(
      name: name,
      callName: callName,
      initial: _initial(callName, name),
    ),
    now: now,
    latestCall: parsed.isEmpty ? null : parsed.first,
    todayCall: todayCall,
  );
}

Call? _callFrom(Map<String, dynamic> data) {
  final startedAt = _date(data['startedAt']);
  if (startedAt == null) return null;
  final state = _string(data['summaryState']);
  final made = state == _summaryMade;
  final summary = _map(data['summary']);
  return Call(
    startedAt: startedAt,
    duration: Duration(milliseconds: _int(data['durationMs'])),
    summary: CallSummary(
      headline: _headline(summary, state),
      conditions: [
        _condition(ConditionKind.meal, summary?['meal'], made: made),
        _condition(ConditionKind.sleep, summary?['sleep'], made: made),
        _condition(ConditionKind.health, summary?['health'], made: made),
      ],
    ),
  );
}

// 作れなかった電話は、ドキュメントにまとめが残っていても使わない
String _headline(Map<String, dynamic>? summary, String state) {
  if (state == _summaryNotMade) return 'まとめを作れませんでした';
  if (state != _summaryMade) return '';
  return _string(summary?['headline']);
}

Condition _condition(ConditionKind kind, Object? raw, {required bool made}) {
  final item = _map(raw);
  if (!made || item == null || item['status'] != _talked) {
    return Condition(kind: kind, value: _notTalked, quote: '');
  }
  return Condition(
    kind: kind,
    value: _string(item['said']),
    quote: _string(item['quote']),
    needsAttention: item['concerning'] == true,
  );
}

// 呼び方の先頭の文字。呼び方が空のときは名前の先頭
String _initial(String callName, String name) {
  final source = callName.trim().isNotEmpty ? callName.trim() : name.trim();
  if (source.isEmpty) return '';
  return String.fromCharCodes(source.runes.take(1));
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

String _string(Object? value) => value is String ? value : '';

int _int(Object? value) => value is num ? value.toInt() : 0;
