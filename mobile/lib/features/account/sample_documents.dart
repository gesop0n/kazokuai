// 新規登録で読ませる見本の文。利用規約の条文はモックの L2c のとおり。
// モックはプライバシーポリシーの条文を書かず、画面構成だけ同じとしている。
// 条文は利用規約に書いてあることだけを、見本だと分かる形で言い換える。
class SampleArticle {
  const SampleArticle(this.heading, this.body);

  final String heading;
  final String body;
}

class SampleDocument {
  const SampleDocument({
    required this.title,
    required this.notice,
    required this.articles,
  });

  final String title;
  final String notice;
  final List<SampleArticle> articles;
}

const termsDocument = SampleDocument(
  title: '利用規約',
  notice: 'モック用の見本です。実際の規約ではありません。',
  articles: [
    SampleArticle('第1条 サービスの内容', 'AIが見守る方の固定電話に電話をかけ、話した内容をまとめて、ご家族のアプリに届けます。'),
    SampleArticle(
      '第2条 見守る方の同意',
      '最初の電話で、AIであることと、会話を文字にしてご家族に共有することを説明します。同意がない場合は共有しません。',
    ),
    SampleArticle('第3条 医療上の判断', 'まとめはご本人の話をAIが整理したものです。診断や受診の判断には使えません。'),
    SampleArticle(
      '第4条 緊急のとき',
      '電話に出ないときの通知は、安否を保証するものではありません。緊急のときは、ご家族から直接連絡してください。',
    ),
    SampleArticle(
      '第5条 アカウントの管理',
      'メールアドレスとパスワードは、ご自身で管理してください。第三者に知られた場合は、すぐに変更してください。',
    ),
    SampleArticle('第6条 サービスの変更', 'サービスの内容は、事前にお知らせしたうえで変更または停止することがあります。'),
  ],
);

const privacyDocument = SampleDocument(
  title: 'プライバシーポリシー',
  notice: 'モック用の見本です。実際のプライバシーポリシーではありません。',
  articles: [
    SampleArticle('第1条 扱う情報', 'アカウントのメールアドレスとパスワード、それに電話で話した内容を文字にしたものです。'),
    SampleArticle('第2条 何に使うか', '文字にした会話からまとめを作り、ご家族のアプリに届けます。'),
    SampleArticle(
      '第3条 見守る方の同意',
      '最初の電話で、AIであることと、会話を文字にしてご家族に共有することを説明します。同意がない場合は共有しません。',
    ),
    SampleArticle('第4条 判断に使わないこと', 'まとめはご本人の話をAIが整理したものです。診断や受診の判断には使えません。'),
    SampleArticle(
      '第5条 アカウントの管理',
      'メールアドレスとパスワードは、ご自身で管理してください。第三者に知られた場合は、すぐに変更してください。',
    ),
    SampleArticle('第6条 見本であること', 'この文章はモック用の見本です。実際のプライバシーポリシーではありません。'),
  ],
);
