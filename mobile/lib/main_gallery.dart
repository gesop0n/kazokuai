import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/app_theme.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_avatar.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_chip.dart';
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/design/widgets/app_icon_circle.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

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
              const _SectionLabel('アバター、アイコンボタン(hhead)'),
              const _Header(),
              const _SectionLabel('夜のカード、AIのラベル、ボタン light(recentCard)'),
              const _RecentCard(),
              const _SectionLabel('カード、入力欄、ボタン record(askCard)'),
              const _AskCard(),
              const _SectionLabel('丸いアイコン枠、ピル(stateRow)'),
              const _StateRows(),
              const _SectionLabel('ボタン secondary(weekCard)'),
              AppButton(
                label: '通話記録を見る',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.m,
                trailingIcon: AppIcons.chevronRight,
                onTap: _noop,
              ),
              const _SectionLabel('入力欄の既定の高さ 56、AIのラベルの既定の色'),
              AppField(text: '話題を入力(例: 大相撲)', onTap: _noop),
              const AppAiTag(label: 'Geminiの言い方の案'),
              const _SectionLabel('チップ 高さ 36(callChips)'),
              Wrap(
                spacing: 8,
                children: [
                  for (final (index, label) in const [
                    '全部',
                    '体調',
                    '話し相手',
                    '操作案内',
                    '不在',
                  ].indexed)
                    AppChip(label: label, selected: index == 0, onTap: _noop),
                ],
              ),
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
              const _SectionLabel('チップ 高さ 32(voiceSetting)'),
              const Wrap(
                spacing: 6,
                children: [
                  AppChip(
                    label: 'ふつう',
                    selected: false,
                    size: AppChipSize.s,
                    onTap: _noop,
                  ),
                  AppChip(
                    label: 'ゆっくり',
                    selected: false,
                    size: AppChipSize.s,
                    onTap: _noop,
                  ),
                  AppChip(
                    label: 'カスタマイズ',
                    selected: true,
                    size: AppChipSize.s,
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
              const _SectionLabel('押せないボタン(disabledBtn)'),
              const AppButton(
                label: '現在通話中です',
                variant: AppButtonVariant.record,
                size: AppButtonSize.l,
                onTap: null,
              ),
              const _SectionLabel('濃い赤のカード、白いボタン(07b)'),
              const _MissedCard(),
              const _SectionLabel('テキスト入力 高さ 56(L7)'),
              const AppTextField(hintText: '話題を入力(例: 大相撲)'),
              const _SectionLabel('テキスト入力 複数行、高さ 60(01)'),
              const _FilledTextField(
                text: '金曜の通院、10時に迎えに行くと伝えて',
                minHeight: 60,
              ),
              const _SectionLabel('テキスト入力 複数行、高さ 72、文字 labelM(06)'),
              const _FilledTextField(
                text: '今日は通院の日です。10時に迎えに行くと伝えて',
                minHeight: 72,
                textStyle: AppTextStyles.labelM,
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
    return Row(
      spacing: 12,
      children: [
        const AppAvatar('ハ', color: AppColors.speakerParent),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('田中ハナさん', style: AppTextStyles.labelL),
              Text(
                '11月5日(木) 10:24 時点',
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        AppIconButton(
          AppIcons.bell,
          semanticLabel: '通知',
          onTap: GalleryScreen._noop,
        ),
      ],
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

class _AskCard extends StatelessWidget {
  const _AskCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        const Text('AIに伝えてもらう', style: AppTextStyles.titleM),
        AppField(text: '伝えたいことを入力', minHeight: 48, onTap: GalleryScreen._noop),
        AppButton(
          label: '通話',
          variant: AppButtonVariant.record,
          size: AppButtonSize.l,
          leadingIcon: AppIcons.phone,
          onTap: GalleryScreen._noop,
        ),
      ],
    );
  }
}

class _FilledTextField extends StatefulWidget {
  const _FilledTextField({
    required this.text,
    required this.minHeight,
    this.textStyle,
  });

  final String text;
  final double minHeight;
  final TextStyle? textStyle;

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
      textStyle: widget.textStyle,
    );
  }
}

class _MissedCard extends StatelessWidget {
  const _MissedCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.alert,
      children: [
        Row(
          spacing: 6,
          children: [
            const AppIcon(
              AppIcons.phoneMissed,
              size: 16,
              color: AppColors.onStateAlert,
            ),
            Expanded(
              child: Text(
                '確認をお願いします',
                style: AppTextStyles.labelM.copyWith(
                  color: AppColors.onStateAlert,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('朝の電話に出ていません', style: AppTextStyles.titleL),
        const SizedBox(height: 4),
        const Text(
          '9:00、9:10、9:20にかけましたが、応答がありません。',
          style: AppTextStyles.bodyM,
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'もう一度電話する',
          variant: AppButtonVariant.white,
          size: AppButtonSize.l,
          leadingIcon: AppIcons.phone,
          onTap: GalleryScreen._noop,
        ),
      ],
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
          quote: '「よく眠れたよ」',
        ),
        _StateRow(
          icon: AppIcons.heart,
          label: '体調',
          value: '膝が痛い。階段がつらい',
          quote: '「昨日の夕方から膝が痛くてね」',
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
