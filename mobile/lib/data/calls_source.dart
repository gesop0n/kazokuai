import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:kazokuai/features/calls/calls_data.dart';
import 'package:kazokuai/features/calls/calls_format.dart';

const _summaryMade = '作れた';
const _summaryNotMade = '作れなかった';
const _summaryCouldNotBeMade = 'まとめを作れませんでした';

// Firestore の電話 1 件。ID はドキュメントの ID で、フィールドには入っていない
class CallDocument {
  const CallDocument({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

// 電話のドキュメントを、通話記録の型にする。
// 日付ごとに新しい順。出なかった電話の記録はまだないので、不在の日は作らない
CallLog callLogFrom({
  required List<CallDocument> calls,
  required DateTime now,
}) {
  final entries = <AnsweredCallEntry>[];
  for (final call in calls) {
    final entry = _entryFrom(call);
    if (entry != null) entries.add(entry);
  }
  entries.sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final days = <CallLogDay>[];
  for (final entry in entries) {
    final date = _dateOnly(entry.startedAt);
    if (days.isEmpty || days.last.date != date) {
      days.add(CallLogDay(date: date, entries: [entry]));
      continue;
    }
    days.last = CallLogDay(date: date, entries: [...days.last.entries, entry]);
  }

  return CallLog(today: _dateOnly(now), days: days);
}

// 電話と発話のドキュメントを、詳細の型にする。始まりの時刻がなければ null
CallDetail? callDetailFrom({
  required String callName,
  required Map<String, dynamic> call,
  required List<Map<String, dynamic>> utterances,
}) {
  final startedAt = _date(call['startedAt']);
  if (startedAt == null) return null;
  final state = _string(call['summaryState']);
  final summary = state == _summaryMade ? _map(call['summary']) : null;
  final ordered = [...utterances]
    ..sort((a, b) => _int(a['index']).compareTo(_int(b['index'])));

  return CallDetail(
    title: callDetailTitle(startedAt),
    startedAt: startedAt,
    duration: Duration(milliseconds: _int(call['durationMs'])),
    parentCallName: callName,
    points: _points(summary),
    utterances: [for (final utterance in ordered) _utteranceFrom(utterance)]
        .whereType<Utterance>()
        .toList(),
    summaryFailure: state == _summaryNotMade ? _summaryCouldNotBeMade : null,
  );
}

AnsweredCallEntry? _entryFrom(CallDocument call) {
  final data = call.data;
  final startedAt = _date(data['startedAt']);
  if (startedAt == null) return null;
  final state = _string(data['summaryState']);
  final summary = state == _summaryMade ? _map(data['summary']) : null;
  return AnsweredCallEntry(
    id: call.id,
    startedAt: startedAt,
    text: _headline(summary, state),
    duration: Duration(milliseconds: _int(data['durationMs'])),
    topic: _topic(summary),
  );
}

String _headline(Map<String, dynamic>? summary, String state) {
  if (state == _summaryNotMade) return _summaryCouldNotBeMade;
  if (state != _summaryMade) return '';
  return _string(summary?['headline']);
}

CallTopic? _topic(Map<String, dynamic>? summary) => switch (summary?['topic']) {
  '体調' => CallTopic.health,
  '話し相手' => CallTopic.companion,
  '操作案内' => CallTopic.guidance,
  _ => null,
};

List<SummaryPoint> _points(Map<String, dynamic>? summary) {
  final raw = summary?['points'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (_map(item) case final point?)
        SummaryPoint(
          text: _string(point['text']),
          at: Duration(milliseconds: _int(point['offsetMs'])),
        ),
  ];
}

Utterance? _utteranceFrom(Map<String, dynamic> data) {
  final speaker = switch (data['speaker']) {
    'AI' => Speaker.ai,
    '見守る方' => Speaker.parent,
    _ => null,
  };
  if (speaker == null) return null;
  return Utterance(
    at: Duration(milliseconds: _int(data['offsetMs'])),
    speaker: speaker,
    text: _string(data['text']),
  );
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
