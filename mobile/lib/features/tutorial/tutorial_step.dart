// 使い方の 9 段階。文言はモックの T1〜T9。呼び方だけ、その見守る方のものに替える
enum TutorialPart {
  recent,
  ask,
  today,
  calendar,
  callRow,
  summary,
  booked,
  newBooking,
  retryRule,
}

enum TutorialPlace { home, calls, callDetail, booking }

class TutorialStep {
  const TutorialStep({
    required this.part,
    required this.place,
    required this.title,
    required this.body,
    this.alignTop = false,
  });

  final TutorialPart part;
  final TutorialPlace place;
  final String title;
  final String body;

  // 今日の様子は、見えていても上に寄せる
  final bool alignTop;
}

List<TutorialStep> tutorialStepsFor(String callName) => [
  TutorialStep(
    part: TutorialPart.recent,
    place: TutorialPlace.home,
    title: '直近の電話',
    body: 'AIが$callNameにかけた電話の内容を短くまとめてここに届けます。「会話を見る」で全文も読めます。',
  ),
  TutorialStep(
    part: TutorialPart.ask,
    place: TutorialPlace.home,
    title: 'AIに伝えてもらう',
    body: '伝えたいことを入力するとAIが電話で$callNameに伝えます。日時を決めて予約もできます。',
  ),
  TutorialStep(
    part: TutorialPart.today,
    place: TutorialPlace.home,
    title: '今日の様子',
    body: '食事、睡眠、体調の3つを$callNameの言葉と一緒にまとめます。気になる話には印が付きます。下には7日間の様子も出ます。',
    alignTop: true,
  ),
  const TutorialStep(
    part: TutorialPart.calendar,
    place: TutorialPlace.calls,
    title: '通話記録 日付を選ぶ',
    body: '「過去7日間」は横にスクロールすると前の日も見られます。電話に出た日は点、出なかった日は×で示します。押すとカレンダーが開き、もっと前の日付も選べます。',
  ),
  const TutorialStep(
    part: TutorialPart.callRow,
    place: TutorialPlace.calls,
    title: '通話記録 記録を読む',
    body: '電話ごとに話した内容を一言でまとめ、話題の種類と通話時間を並べます。出なかった電話も残します。記録を押すと詳しい内容が開きます。',
  ),
  const TutorialStep(
    part: TutorialPart.summary,
    place: TutorialPlace.callDetail,
    title: '通話記録 詳しい内容',
    body: '上のAIのまとめを押すと、その時刻の会話の全文を下に表示します。',
  ),
  const TutorialStep(
    part: TutorialPart.booked,
    place: TutorialPlace.booking,
    title: '予約電話 予約を確かめる',
    body: '決まった時間にかける予定を並べます。押すと、伝える内容と日時を変えられます。「今すぐ通話」もできます。',
  ),
  const TutorialStep(
    part: TutorialPart.newBooking,
    place: TutorialPlace.booking,
    title: '予約電話 新しい予約',
    body: '「AIに伝えてもらう」と同じ画面で、伝えたいことと日時を決めて予約します。',
  ),
  TutorialStep(
    part: TutorialPart.retryRule,
    place: TutorialPlace.booking,
    title: '予約電話 かけなおしのルール',
    body: '$callNameが電話に出ないとき、何分おきに何回かけなおすかを決めます。それでも出ないときは、家族に通知が届きます。',
  ),
];
