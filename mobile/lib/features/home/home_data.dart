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
  const DayCallRecord({required this.date, this.talkedMinutes});

  final DateTime date;

  // 電話に出なかった日は null
  final int? talkedMinutes;
}

class WeekCallRecords {
  const WeekCallRecords(this.days);

  final List<DayCallRecord> days;

  int get answeredDays => days.where((day) => day.talkedMinutes != null).length;

  int get totalTalkedMinutes =>
      days.fold(0, (total, day) => total + (day.talkedMinutes ?? 0));
}

class HomeData {
  const HomeData({
    required this.now,
    required this.person,
    required this.latestCall,
    required this.week,
  });

  final DateTime now;
  final WatchedPerson person;
  final Call latestCall;
  final WeekCallRecords week;
}
