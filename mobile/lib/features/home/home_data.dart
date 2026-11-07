class WatchedPerson {
  const WatchedPerson({
    required this.name,
    required this.callName,
    required this.initial,
  });

  final String name;
  final String callName;
  final String initial;
}

class Quote {
  const Quote({required this.text, required this.spokenAt});

  final String text;
  final DateTime spokenAt;
}

enum ConditionKind { meal, sleep, health }

class Condition {
  const Condition({
    required this.kind,
    required this.value,
    required this.quote,
    this.needsAttention = false,
  });

  final ConditionKind kind;
  final String value;
  final String quote;
  final bool needsAttention;
}

class CallSummary {
  const CallSummary({
    required this.headline,
    required this.quote,
    required this.conditions,
  });

  final String headline;
  final Quote quote;
  final List<Condition> conditions;
}

class Call {
  const Call({
    required this.startedAt,
    required this.duration,
    required this.summary,
  });

  final DateTime startedAt;
  final Duration duration;
  final CallSummary summary;
}

class DayCallRecord {
  const DayCallRecord({required this.date, this.talkedMinutes}) : quiet = false;

  // 電話がなかった日。棒も、出なかった印も出さない
  const DayCallRecord.quiet({required this.date})
    : talkedMinutes = null,
      quiet = true;

  final DateTime date;

  // 電話がなかった日と、出なかった日は null。0 分でも電話があれば 0
  final int? talkedMinutes;

  // true の日は、電話が一度もなかった日。false で分数がない日は、出なかった日
  final bool quiet;
}

// ホームが Firestore から読む、見守る方と電話。まだ読めないときはリポジトリが null を出す
class HomeView {
  const HomeView({
    required this.person,
    required this.now,
    required this.latestCall,
    required this.todayCall,
    required this.week,
  });

  final WatchedPerson person;
  final DateTime now;

  // いちばん新しい電話。1 件もなければ null
  final Call? latestCall;

  // 今日の最後の電話。今日の電話がなければ null で、今日の様子は話していない
  final Call? todayCall;
  final WeekCallRecords week;
}

class WeekCallRecords {
  const WeekCallRecords(this.days);

  final List<DayCallRecord> days;

  int get answeredDays => days.where((day) => day.talkedMinutes != null).length;

  int get totalTalkedMinutes =>
      days.fold(0, (total, day) => total + (day.talkedMinutes ?? 0));
}

class LastTalk {
  const LastTalk({
    required this.startedAt,
    required this.duration,
    required this.quote,
  });

  final DateTime startedAt;
  final Duration duration;
  final String quote;
}

class MissedCall {
  const MissedCall({required this.attemptedAt, required this.lastTalk});

  // 古い順
  final List<DateTime> attemptedAt;
  final LastTalk lastTalk;
}

class HomeData {
  const HomeData({
    required this.now,
    required this.person,
    required this.latestCall,
    required this.week,
    required this.missedCall,
  });

  final DateTime now;
  final WatchedPerson person;
  final Call latestCall;
  final WeekCallRecords week;
  final MissedCall missedCall;
}
