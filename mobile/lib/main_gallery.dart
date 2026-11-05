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
import 'package:kazokuai/design/widgets/app_field.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/design/widgets/app_icon_circle.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';

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

// 部品がホームでどう並ぶかをモックと見比べられるように、文言と組み合わせをホームに揃える。
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        const AppAiTag(
          label: 'Geminiのまとめ',
          color: AppColors.nightTextSecondary,
        ),
        const SizedBox(height: 4),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          spacing: 8,
          children: [
            // 幅 360、文字倍率 1.3 では 1 行に収まらないので折り返す
            const Flexible(
              child: Text('AIに伝えてもらう', style: AppTextStyles.titleM),
            ),
            Text(
              '予約もできます',
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
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
