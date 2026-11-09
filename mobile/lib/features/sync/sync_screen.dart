import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/data/sync_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/sync/phone_illustration.dart';

enum _Page { start, waiting, code, help }

enum _Issue { wrong, ended, unsent }

enum _StartIssue { failed, limited }

// L3、L3w、L3k、L3+。
// 新規登録では「もどる」がログアウトする。設定から開いたときは、設定へ戻る。
// 認証コードを受け付けると L5 を開く。
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key, this.fromSettings = false});

  // 設定(08)から開いた同期。もどる先と、完了のボタンが違う
  final bool fromSettings;

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  _Page _page = _Page.start;
  String _digits = '';
  _Issue? _issue;
  _StartIssue? _startIssue;
  bool _starting = false;
  bool _sending = false;

  bool get _canSend => !_sending && _digits.length == 6;

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _startIssue = null;
    });
    try {
      await ref.read(syncRepositoryProvider).start();
      if (mounted) setState(() => _page = _Page.waiting);
    } on SyncPrepLimitedException {
      if (mounted) setState(() => _startIssue = _StartIssue.limited);
    } on SyncFailedException {
      if (mounted) setState(() => _startIssue = _StartIssue.failed);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    // 送り終わる前に見守る方ができて、この画面が捨てられても L5 を開く。
    final router = GoRouter.of(context);
    final watched = ref.read(watchedPersonRepositoryProvider);
    final sync = ref.read(syncRepositoryProvider);
    final home = ref.read(homeRepositoryProvider);
    final fromSettings = widget.fromSettings;
    setState(() {
      _sending = true;
      _issue = null;
    });
    try {
      await sync.sendCode(_digits);
      watched.noteLinkedWithoutName();
      if (fromSettings) home.notePhoneLinked();
      router.goNamed(
        fromSettings ? AppRoutes.settingsSyncDone : AppRoutes.syncDone,
      );
    } on SyncCodeWrongException {
      if (mounted) setState(() => _issue = _Issue.wrong);
    } on SyncPrepEndedException {
      if (mounted) setState(() => _issue = _Issue.ended);
    } on SyncFailedException {
      if (mounted) setState(() => _issue = _Issue.unsent);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // モックは、違うと出ているあいだに数字キーを押すと、入れ直しにする。
  void _press(String key) {
    setState(() {
      if (_issue == _Issue.wrong) {
        _issue = null;
        _digits = '';
      }
      if (key == 'del') {
        if (_digits.isNotEmpty) {
          _digits = _digits.substring(0, _digits.length - 1);
        }
      } else if (_digits.length < 6) {
        _digits += key;
      }
    });
  }

  void _restart() {
    setState(() {
      _page = _Page.start;
      _digits = '';
      _issue = null;
      _startIssue = null;
    });
  }

  void _showCode() => setState(() => _page = _Page.code);

  void _showHelp() => setState(() => _page = _Page.help);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _nav(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _body(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _foot(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nav() {
    return switch (_page) {
      _Page.start => AppNavBar(
        title: '電話機と同期',
        onLeadingTap: widget.fromSettings
            ? () => popOrGoToParent(context)
            : () => ref.read(authRepositoryProvider).signOut(),
      ),
      _Page.waiting => AppNavBar(
        title: '電話機と同期',
        onLeadingTap: () => setState(() => _page = _Page.start),
      ),
      _Page.code => AppNavBar(
        title: '認証コードの入力',
        onLeadingTap: () => setState(() => _page = _Page.waiting),
      ),
      // モックの L3+ は、開いた元が L3w でも L3k に戻る
      _Page.help => AppNavBar(title: '認証コードが聞こえないとき', onLeadingTap: _showCode),
    };
  }

  Widget _body() {
    return switch (_page) {
      _Page.start => _StartBody(issue: _startIssue),
      _Page.waiting => const _WaitingBody(),
      _Page.code => _CodeBody(
        digits: _digits,
        issue: _issue,
        onHelp: _showHelp,
      ),
      _Page.help => const _HelpBody(),
    };
  }

  Widget _foot() {
    return switch (_page) {
      _Page.start => AppButton(
        label: '同期を始める',
        variant: AppButtonVariant.primary,
        size: AppButtonSize.l,
        onTap: _starting ? null : _start,
      ),
      _Page.waiting => Column(
        spacing: 4,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: '認証コードを入力する',
            variant: AppButtonVariant.primary,
            size: AppButtonSize.l,
            onTap: _showCode,
          ),
          AppButton(
            label: '認証コードが聞こえないとき',
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.m,
            underlined: true,
            onTap: _showHelp,
          ),
        ],
      ),
      _Page.code => Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_issue == _Issue.ended)
            AppButton(
              label: '同期を始めるからやり直す',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.l,
              onTap: _restart,
            )
          else
            AppButton(
              label: '送信',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.l,
              onTap: _canSend ? _send : null,
            ),
          if (_issue != _Issue.ended) _Keypad(onKey: _press),
        ],
      ),
      _Page.help => AppButton(
        label: '認証コードを入力する',
        variant: AppButtonVariant.primary,
        size: AppButtonSize.l,
        onTap: _showCode,
      ),
    };
  }
}

// L5。認証コードを受け付けたあとに開く。
// 新規登録では閉じるも進むも名前の入力へ行く。設定から来たときは、どちらも設定へ戻る。
class SyncDoneScreen extends ConsumerWidget {
  const SyncDoneScreen({super.key, this.fromSettings = false});

  final bool fromSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leave = fromSettings
        ? () => context.goNamed(AppRoutes.settings)
        : () => _openName(context, ref);
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(
              title: '電話機と同期',
              leadingIcon: AppIcons.x,
              leadingLabel: '閉じる',
              onLeadingTap: leave,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 20,
                  children: [
                    PhoneIllustration(showHash: false),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 4,
                      children: [
                        Text('同期が完了しました！', style: AppTextStyles.titleL),
                        Text('以下の電話機からAIが電話できるようになりました。', style: _mutedBody),
                      ],
                    ),
                    _PhoneCard(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppButton(
                label: fromSettings ? '設定にもどる' : 'セットアップへ進む',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                onTap: leave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openName(BuildContext context, WidgetRef ref) {
  ref.read(watchedPersonRepositoryProvider).noteLinkedWithoutName();
  context.goNamed(AppRoutes.watchedPersonName);
}

class _StartBody extends StatelessWidget {
  const _StartBody({required this.issue});

  final _StartIssue? issue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        const PhoneIllustration(showHash: true),
        const Text('電話機との同期を始めます。', style: AppTextStyles.titleL),
        if (issue == _StartIssue.failed) const _Notice(title: '同期を始められませんでした'),
        if (issue == _StartIssue.limited)
          const _Notice(title: 'しばらくしてから、もう一度お試しください'),
      ],
    );
  }
}

class _WaitingBody extends StatelessWidget {
  const _WaitingBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        PhoneIllustration(showHash: true),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text('電話機の受話器を上げて\n「＃」を押してください', style: AppTextStyles.titleL),
            Text('受話器から6桁の認証コードが流れます。', style: _mutedBody),
          ],
        ),
        Text('準備は10分で切れます。切れたときは、もう一度「同期を始める」から始めます。', style: _mutedNote),
      ],
    );
  }
}

class _CodeBody extends StatelessWidget {
  const _CodeBody({
    required this.digits,
    required this.issue,
    required this.onHelp,
  });

  final String digits;
  final _Issue? issue;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        const Text('受話器から聞こえた\n6桁の数字を入力してください', style: AppTextStyles.titleL),
        _CodeBoxes(digits: digits, wrong: issue == _Issue.wrong),
        if (issue == null)
          const Text('聞きのがしたときは、電話機の「＃」をもう一度押します。', style: _mutedNote)
        else
          _notice(issue!),
        AppButton(
          label: '認証コードが聞こえないとき',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.m,
          underlined: true,
          onTap: onHelp,
        ),
      ],
    );
  }

  Widget _notice(_Issue issue) {
    return switch (issue) {
      _Issue.wrong => const _Notice(
        title: '認証コードが違います',
        body: '電話機の「＃」をもう一度押すと、\n認証コードがもう一度流れます。',
      ),
      _Issue.ended => const _Notice(
        title: '同期の準備が終わりました',
        body: '「同期を始める」から、もう一度始めてください。',
      ),
      _Issue.unsent => const _Notice(title: '送信できませんでした'),
    };
  }
}

class _HelpBody extends StatelessWidget {
  const _HelpBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        PhoneIllustration(showHash: true),
        Column(
          spacing: 12,
          children: [
            _Step(
              number: '1',
              title: '受話器を耳にしっかり当てる',
              detail: '認証コードは受話器から流れます。周りが静かなところで聞きます',
            ),
            _Step(
              number: '2',
              title: 'もう一度「＃」を押す',
              detail: '準備が切れるまでは、何度でも聞き直せます',
            ),
            _Step(
              number: '3',
              title: '電源とインターネットを確かめる',
              detail: '抜けていないか確かめてから、「同期を始める」からやり直します',
            ),
          ],
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.inkPrimary,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: AppTextStyles.labelM.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.paperRaised,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AppTextStyles.labelL),
              Text(detail, style: _mutedNote),
            ],
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.title, this.body});

  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          const AppIcon(AppIcons.alert, size: 20, color: AppColors.stateAlert),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: AppTextStyles.labelL.copyWith(
                    color: AppColors.stateAlert,
                  ),
                ),
                if (body != null) Text(body, style: _mutedNote),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.digits, required this.wrong});

  final String digits;
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: digits.isEmpty ? '6桁の認証コード' : '6桁の認証コード、$digits',
      child: ExcludeSemantics(
        child: Row(
          spacing: 8,
          children: [
            for (var i = 0; i < 6; i++)
              Expanded(
                child: _box(
                  i < digits.length ? digits[i] : '',
                  current: !wrong && i == digits.length,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _box(String digit, {required bool current}) {
    final border = wrong
        ? AppColors.stateAlert
        : current
        ? AppColors.inkPrimary
        : AppColors.lineStrong;
    return SizedBox(
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: wrong ? AppColors.stateAlertSoft : AppColors.paperRaised,
          borderRadius: AppRadius.borderRadius,
          border: Border.all(color: border, width: wrong || current ? 2 : 1.5),
        ),
        child: Center(child: Text(digit, style: _digitStyle)),
      ),
    );
  }
}

// モックの数字キー。角は 12 で、ほかの部品の AppRadius とは違う。
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final ValueChanged<String> onKey;

  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '',
    '0',
    'del',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        for (var row = 0; row < 4; row++)
          Row(
            spacing: 8,
            children: [
              for (var column = 0; column < 3; column++)
                Expanded(child: _key(_keys[row * 3 + column])),
            ],
          ),
      ],
    );
  }

  Widget _key(String key) {
    if (key.isEmpty) return const SizedBox(height: 48);
    final delete = key == 'del';
    return AppPressable(
      onTap: () => onKey(delete ? 'del' : key),
      semanticLabel: delete ? '1文字消す' : null,
      foregroundColor: AppColors.inkPrimary,
      backgroundColor: AppColors.paperRaised,
      minHeight: 48,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.line),
      ),
      child: Center(
        child: delete
            ? const AppIcon(AppIcons.delete)
            : Text(key, style: _keyStyle),
      ),
    );
  }
}

class _PhoneCard extends StatelessWidget {
  const _PhoneCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: AppColors.line),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          spacing: 12,
          children: [
            _PhoneIcon(),
            Text('かぞくAIの電話機', style: AppTextStyles.labelL),
          ],
        ),
      ),
    );
  }
}

class _PhoneIcon extends StatelessWidget {
  const _PhoneIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.paperSunken,
        shape: BoxShape.circle,
      ),
      child: const AppIcon(AppIcons.phone, size: 20),
    );
  }
}

const _mutedBody = TextStyle(
  fontFamily: 'BIZUDPGothic',
  fontWeight: FontWeight.w400,
  fontSize: 15,
  height: 24 / 15,
  letterSpacing: .02 * 15,
  leadingDistribution: TextLeadingDistribution.even,
  color: AppColors.inkSecondary,
);

const _mutedNote = TextStyle(
  fontFamily: 'BIZUDPGothic',
  fontWeight: FontWeight.w400,
  fontSize: 13,
  height: 20 / 13,
  letterSpacing: .02 * 13,
  leadingDistribution: TextLeadingDistribution.even,
  color: AppColors.inkSecondary,
);

const _digitStyle = TextStyle(
  fontFamily: 'BIZUDPGothic',
  fontWeight: FontWeight.w700,
  fontSize: 28,
  height: 36 / 28,
  leadingDistribution: TextLeadingDistribution.even,
);

// モックの 500 は、同梱している太さでは 400
const _keyStyle = TextStyle(
  fontFamily: 'BIZUDPGothic',
  fontWeight: FontWeight.w400,
  fontSize: 24,
  height: 32 / 24,
  leadingDistribution: TextLeadingDistribution.even,
);
