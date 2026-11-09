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
  const CallSummary({required this.headline, required this.conditions});

  final String headline;
  final List<Condition> conditions;
}

class Call {
  const Call({
    this.id,
    required this.startedAt,
    required this.duration,
    required this.summary,
  });

  // Firestore の電話の ID。見本の電話にはない
  final String? id;
  final DateTime startedAt;
  final Duration duration;
  final CallSummary summary;
}

// ホームが Firestore から読む、見守る方と電話。まだ読めないときはリポジトリが null を出す
class HomeView {
  const HomeView({
    required this.person,
    required this.now,
    required this.latestCall,
    required this.todayCall,
  });

  final WatchedPerson person;
  final DateTime now;

  // いちばん新しい電話。1 件もなければ null
  final Call? latestCall;

  // 今日の最後の電話。今日の電話がなければ null で、今日の様子は話していない
  final Call? todayCall;
}

class MissedCall {
  const MissedCall({required this.attemptedAt});

  // 古い順
  final List<DateTime> attemptedAt;
}

class HomeData {
  const HomeData({
    required this.now,
    required this.person,
    required this.latestCall,
    required this.missedCall,
  });

  final DateTime now;
  final WatchedPerson person;
  final Call latestCall;
  final MissedCall missedCall;
}
