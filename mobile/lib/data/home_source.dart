import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kazokuai/features/home/home_data.dart';

const _summaryMade = '作れた';
const _summaryNotMade = '作れなかった';
const _talked = '話した';
const _notTalked = '話していない';

// Firestore の見守る方と電話のドキュメントを、ホームの型にする。
// 直近の電話は期間に関係なくいちばん新しいもの、今日の様子はその日の最後の電話。
// 返答は、まとめを作れた電話のうちいちばん新しいもの。作れなかった電話では前の返答を残す。
HomeView homeViewFrom({
  required Map<String, dynamic> person,
  required List<Map<String, dynamic>> calls,
  required DateTime now,
}) {
  final name = _string(person['name']);
  final callName = _string(person['callName']);
  final parsed = <_ParsedCall>[];
  for (final data in calls) {
    final call = _callFrom(data);
    if (call != null) parsed.add(call);
  }
  parsed.sort((a, b) => b.call.startedAt.compareTo(a.call.startedAt));

  final today = _dateOnly(now);
  Call? todayCall;
  for (final call in parsed) {
    if (_dateOnly(call.call.startedAt) == today) {
      todayCall = call.call;
      break;
    }
  }

  return HomeView(
    person: WatchedPerson(
      name: name,
      callName: callName,
      initial: _initial(callName, name),
      hasPhone: _linkedPhone(person),
    ),
    now: now,
    latestCall: parsed.isEmpty ? null : parsed.first.call,
    todayCall: todayCall,
    reply: _replyUntilLaterSummary(parsed),
  );
}

// phoneId が空白だけ、または無いときは、電話機が結び付いていない
bool _linkedPhone(Map<String, dynamic> person) {
  final id = person['phoneId'];
  return id is String && id.trim().isNotEmpty;
}

// 返答のある電話のうち最新のものを、それより新しい電話のまとめが作れたときまで出す。
// 新しい順に見て、まとめが作れた最初の電話に返答がなければ出さない。
// 作れなかった電話はまとめが届いていないので飛ばす。
Reply? _replyUntilLaterSummary(List<_ParsedCall> calls) {
  for (final call in calls) {
    if (!call.summaryArrived) continue;
    return call.reply;
  }
  return null;
}

class _ParsedCall {
  const _ParsedCall({
    required this.call,
    required this.summaryArrived,
    required this.reply,
  });

  final Call call;
  final bool summaryArrived;
  final Reply? reply;
}

_ParsedCall? _callFrom(Map<String, dynamic> data) {
  final startedAt = _date(data['startedAt']);
  if (startedAt == null) return null;
  final state = _string(data['summaryState']);
  final made = state == _summaryMade;
  final summary = _map(data['summary']);
  final id = _string(data['id']);
  return _ParsedCall(
    call: Call(
      id: id.isEmpty ? null : id,
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
    ),
    summaryArrived: made,
    reply: made ? _replyFrom(summary, startedAt) : null,
  );
}

// 作れた電話の返答。文がなければ null。時刻は受話器を上げてからの経過
Reply? _replyFrom(Map<String, dynamic>? summary, DateTime startedAt) {
  final reply = _map(summary?['reply']);
  final text = _string(reply?['text']);
  if (text.trim().isEmpty) return null;
  return Reply(
    told: _string(summary?['told']),
    text: text,
    saidAt: startedAt.add(Duration(milliseconds: _int(reply?['offsetMs']))),
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
