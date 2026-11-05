enum CallTopic {
  health('体調'),
  companion('話し相手'),
  guidance('操作案内');

  const CallTopic(this.label);

  final String label;
}

sealed class CallLogEntry {
  const CallLogEntry({required this.startedAt, required this.text});

  final DateTime startedAt;
  final String text;
}

class AnsweredCallEntry extends CallLogEntry {
  const AnsweredCallEntry({
    required super.startedAt,
    required super.text,
    required this.duration,
    required this.topic,
  });

  final Duration duration;
  final CallTopic topic;
}

class MissedCallEntry extends CallLogEntry {
  const MissedCallEntry({required super.startedAt, required super.text});
}

enum CallFilter {
  all('全部'),
  health('体調'),
  companion('話し相手'),
  guidance('操作案内'),
  missed('不在');

  const CallFilter(this.label);

  final String label;

  bool matches(CallLogEntry entry) => switch (this) {
    CallFilter.all => true,
    CallFilter.health => _hasTopic(entry, CallTopic.health),
    CallFilter.companion => _hasTopic(entry, CallTopic.companion),
    CallFilter.guidance => _hasTopic(entry, CallTopic.guidance),
    CallFilter.missed => entry is MissedCallEntry,
  };

  static bool _hasTopic(CallLogEntry entry, CallTopic topic) =>
      entry is AnsweredCallEntry && entry.topic == topic;
}

class CallLogDay {
  const CallLogDay({required this.date, required this.entries});

  final DateTime date;

  // 新しい順
  final List<CallLogEntry> entries;

  Iterable<AnsweredCallEntry> get answeredEntries =>
      entries.whereType<AnsweredCallEntry>();

  List<CallLogEntry> entriesMatching(CallFilter filter) =>
      entries.where(filter.matches).toList();
}

enum DayMark { answered, missed }

class CallLog {
  const CallLog({
    required this.today,
    required this.days,
    this.answeredDaysWithoutRecord = const {},
  });

  // 時刻は 0 時にそろえる。ほかの日付も同じ
  final DateTime today;

  // 新しい順
  final List<CallLogDay> days;

  // 電話に出た印はあるが、一覧に行がない日
  final Set<DateTime> answeredDaysWithoutRecord;

  List<CallLogDay> daysMatching(CallFilter filter) =>
      days.where((day) => day.entries.any(filter.matches)).toList();

  bool hasRecord(DateTime date) => days.any((day) => day.date == date);

  DayMark? markOf(DateTime date) {
    if (answeredDaysWithoutRecord.contains(date)) return DayMark.answered;
    for (final day in days) {
      if (day.date == date) {
        return day.answeredEntries.isEmpty ? DayMark.missed : DayMark.answered;
      }
    }
    return null;
  }
}

class SummaryPoint {
  const SummaryPoint({required this.text, required this.at});

  final String text;

  // 根拠の発言の時刻。通話の始まりからの経過時間
  final Duration at;
}

enum Speaker { ai, parent }

class Utterance {
  const Utterance({
    required this.at,
    required this.speaker,
    required this.text,
    this.needsAttention = false,
  });

  // 通話の始まりからの経過時間
  final Duration at;
  final Speaker speaker;
  final String text;
  final bool needsAttention;
}

class CallDetail {
  const CallDetail({
    required this.title,
    required this.startedAt,
    required this.duration,
    required this.parentCallName,
    required this.points,
    required this.utterances,
  });

  final String title;
  final DateTime startedAt;
  final Duration duration;
  final String parentCallName;
  final List<SummaryPoint> points;
  final List<Utterance> utterances;
}
