import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/app_theme.dart';
import 'package:kazokuai/design/widgets/app_agree_box.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/design/widgets/app_icon_circle.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_header.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';

// flutter run -t lib/main_gallery.dart で開く部品一覧画面。main.dart からは読み込まない。
void main() {
  runApp(const GalleryApp());
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'かぞくAI 部品一覧',
      theme: appTheme,
      themeMode: ThemeMode.light,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
      home: const GalleryScreen(),
    );
  }
}

// 部品がどう並ぶかをモックと見比べられるように、文言と組み合わせを使う画面に揃える。
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: AppTabBar(currentIndex: 0, onSelected: (_) {}),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              const _SectionLabel('ヘッダー(hhead)'),
              _Header(),
              const _SectionLabel('夜のカード、AIのラベル、ボタン light(recentCard)'),
              const _RecentCard(),
              const _SectionLabel('AIに伝えてもらう(askCard)'),
              AskCard(onOpenAsk: _noop),
              const _SectionLabel('丸いアイコン枠、ピル(stateRow)'),
              const _StateRows(),
              const _SectionLabel('ボタン secondary'),
              AppButton(
                label: '通話記録を見る',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.m,
                trailingIcon: AppIcons.chevronRight,
                onTap: _noop,
              ),
              const _SectionLabel('ボタン alert(08d、08e)'),
              AppButton(
                label: 'ログアウトする',
                variant: AppButtonVariant.alert,
                size: AppButtonSize.l,
                onTap: _noop,
              ),
              AppButton(
                label: 'ログアウト',
                variant: AppButtonVariant.alertSecondary,
                size: AppButtonSize.l,
                leadingIcon: AppIcons.logOut,
                onTap: _noop,
              ),
              const _SectionLabel('入力欄の既定の高さ 56、AIのラベルの既定の色'),
              AppField(text: '話題を入力(例: 大相撲)', onTap: _noop),
              const AppAiTag(label: '通話内容'),
              const _SectionLabel('チップ 高さ 36、アイコンあり(topic)'),
              const Wrap(
                spacing: 8,
                children: [
                  AppChip(
                    label: 'お孫さん',
                    selected: true,
                    icon: AppIcons.check,
                    onTap: _noop,
                  ),
                  AppChip(
                    label: '大相撲',
                    selected: false,
                    icon: AppIcons.plus,
                    onTap: _noop,
                  ),
                ],
              ),
              const _SectionLabel('ボタン primary(07)'),
              AppButton(
                label: 'このルールで保存',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                onTap: _noop,
              ),
              const _SectionLabel('ボタン ghost(L4)'),
              AppButton(
                label: 'うまくいかないときの連絡先',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.m,
                onTap: _noop,
              ),
              const _SectionLabel('ボタン ghost、小さいもの(01、05)'),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'なおす',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.s,
                  leadingIcon: AppIcons.pencil,
                  onTap: _noop,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  label: 'まとめの間違いを直す',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sFlush,
                  leadingIcon: AppIcons.pencil,
                  onTap: _noop,
                ),
              ),
              const _SectionLabel('下線の付いたリンク(L2)'),
              Center(
                child: AppButton(
                  label: 'パスワードを忘れた場合',
                  variant: AppButtonVariant.ghostInk,
                  size: AppButtonSize.m,
                  underlined: true,
                  onTap: _noop,
                ),
              ),
              AppButton(
                label: 'はじめての方は新規登録',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.m,
                underlined: true,
                onTap: _noop,
              ),
              const _SectionLabel('チェックボックス(agreebox)'),
              const Row(
                spacing: 8,
                children: [
                  AppAgreeBox(
                    checked: false,
                    semanticLabel: 'チェックなし',
                    onTap: GalleryScreen._noop,
                  ),
                  AppAgreeBox(
                    checked: true,
                    semanticLabel: 'チェックあり',
                    onTap: GalleryScreen._noop,
                  ),
                  AppAgreeBox(
                    checked: false,
                    semanticLabel: '押せない',
                    onTap: null,
                  ),
                ],
              ),
              const _SectionLabel('押せないボタン(disabledBtn)'),
              const AppButton(
                label: 'この日時で予約する',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                leadingIcon: AppIcons.calendarClock,
                onTap: null,
              ),
              const AppButton(
                label: '今すぐ通話',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.m,
                leadingIcon: AppIcons.phone,
                onTap: null,
              ),
              const _SectionLabel('電話に出なかったとき(07b)'),
              MissedCallView(
                missedCall: MissedCall(
                  attemptedAt: [
                    DateTime(2026, 11, 5, 9),
                    DateTime(2026, 11, 5, 9, 15),
                    DateTime(2026, 11, 5, 9, 30),
                  ],
                ),
                onOpenAsk: _noop,
              ),
              const _SectionLabel('テキスト入力 高さ 56(L7)'),
              const AppTextField(hintText: '話題を入力(例: 大相撲)'),
              const _SectionLabel('テキスト入力 複数行、高さ 60(01)'),
              const _FilledTextField(
                text: '金曜の通院、10時に迎えに行くと伝えて',
                minHeight: 60,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: AppTextStyles.labelS.copyWith(color: AppColors.inkSecondary),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return HomeHeader(
      person: const WatchedPerson(name: '田中ハナ', callName: 'ハナさん', initial: 'ハ'),
      now: DateTime(2026, 11, 5, 10, 24),
      onOpenSettings: GalleryScreen._noop,
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.night,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('直近の電話', style: AppTextStyles.labelM),
            Text(
              '今日 9:02 ・ 6分',
              style: AppTextStyles.monoS.copyWith(
                color: AppColors.nightTextSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '朝ごはんを食べ、薬も飲んだそうです。膝の痛みを少し気にしています。',
          style: AppTextStyles.titleM,
        ),
        const SizedBox(height: 16),
        AppButton(
          label: '会話を見る',
          variant: AppButtonVariant.light,
          size: AppButtonSize.m,
          trailingIcon: AppIcons.chevronRight,
          onTap: GalleryScreen._noop,
        ),
      ],
    );
  }
}

class _FilledTextField extends StatefulWidget {
  const _FilledTextField({required this.text, required this.minHeight});

  final String text;
  final double minHeight;

  @override
  State<_FilledTextField> createState() => _FilledTextFieldState();
}

class _FilledTextFieldState extends State<_FilledTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      minHeight: widget.minHeight,
      maxLines: null,
    );
  }
}

class _StateRows extends StatelessWidget {
  const _StateRows();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      variant: AppCardVariant.paper,
      children: [
        _StateRow(
          icon: AppIcons.moon,
          label: '睡眠',
          value: 'よく眠れた',
          quote: 'よく眠れたよ',
        ),
        _StateRow(
          icon: AppIcons.heart,
          label: '体調',
          value: '膝が痛い。階段がつらい',
          quote: '昨日の夕方から膝が痛くてね',
          flagged: true,
        ),
      ],
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.quote,
    this.flagged = false,
  });

  final AppIcons icon;
  final String label;
  final String value;
  final String quote;
  final bool flagged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        AppIconCircle(icon),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                spacing: 8,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.labelS.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  if (flagged)
                    const AppPill(
                      variant: AppPillVariant.care,
                      icon: AppIcons.alert,
                      label: '気になる話',
                    ),
                ],
              ),
              Text(value, style: AppTextStyles.labelL),
              Text(
                quote,
                style: AppTextStyles.capS.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
