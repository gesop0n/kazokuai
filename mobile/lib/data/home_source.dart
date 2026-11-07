import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kazokuai/features/home/home_data.dart';

const _summaryMade = '作れた';
const _summaryNotMade = '作れなかった';
const _talked = '話した';
const _notTalked = '話していない';

// ログインした家族の見守る方と、その電話を読んで、ホームの型にする。
// 見守る方がいなければ null。電話の選び方は homeViewFrom と同じ
Future<HomeView?> readHome(
  FirebaseFirestore firestore, {
  required String uid,
  required DateTime now,
}) async {
  final people = await firestore
      .collection('watchedPersons')
      .where('familyUids', arrayContains: uid)
      .limit(1)
      .get();
  if (people.docs.isEmpty) return null;
  final person = people.docs.first;
  final calls = await person.reference.collection('calls').get();
  return homeViewFrom(
    person: person.data(),
    calls: [for (final call in calls.docs) call.data()],
    now: now,
  );
}

// Firestore の見守る方と電話のドキュメントを、ホームの型にする。
// 直近の電話は期間に関係なくいちばん新しいもの、今日の様子はその日の最後の電話、
// 7 日間は今日を含む 7 日で、電話がなかった日は棒も印も出さない
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
  final start = today.subtract(const Duration(days: 6));
  Call? todayCall;
  final totals = <DateTime, int>{};
  for (final call in parsed) {
    final day = _dateOnly(call.startedAt);
    if (day == today && todayCall == null) todayCall = call;
    if (day.isBefore(start) || day.isAfter(today)) continue;
    totals[day] = (totals[day] ?? 0) + call.duration.inMilliseconds;
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
    week: WeekCallRecords([
      for (var i = 0; i < 7; i++)
        _dayRecord(start.add(Duration(days: i)), totals),
    ]),
  );
}

DayCallRecord _dayRecord(DateTime date, Map<DateTime, int> totals) {
  final milliseconds = totals[date];
  if (milliseconds == null) return DayCallRecord.quiet(date: date);
  return DayCallRecord(
    date: date,
    talkedMinutes: Duration(milliseconds: milliseconds).inMinutes,
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
      quote: _quote(startedAt, summary, made: made),
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

Quote _quote(
  DateTime startedAt,
  Map<String, dynamic>? summary, {
  required bool made,
}) {
  if (!made) return Quote(text: '', spokenAt: startedAt);
  final quote = _map(summary?['quote']);
  return Quote(
    text: _string(quote?['text']),
    spokenAt: startedAt.add(Duration(milliseconds: _int(quote?['offsetMs']))),
  );
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
