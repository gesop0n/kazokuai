import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/ask/voice_setting.dart';

class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMessage = _messageController.text.trim().isNotEmpty;
    return Scaffold(
      body: SafeArea(
        // キーボードが出るとホームバーの余白がなくなるので、ボタンがキーボードに付かないようにする
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppNavBar(title: 'AIに伝えてもらう'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    _MessageField(
                      controller: _messageController,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (hasMessage) const _SuggestionCard(),
                    const _VoiceSettings(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _AskActions(
                onCall: hasMessage ? () => showComingSoon(context) : null,
                onBook: () => context.goNamed(AppRoutes.booking),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageField extends StatelessWidget {
  const _MessageField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        // 入力欄の読み上げと重ならないようにする
        const ExcludeSemantics(
          child: Text('伝えたいこと', style: AppTextStyles.labelM),
        ),
        AppTextField(
          controller: controller,
          semanticLabel: '伝えたいこと',
          minHeight: 60,
          maxLines: null,
          autofocus: true,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// 文は ADR 0002 のとおり固定で、入力の内容によって変えない
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: AppAiTag(label: 'Geminiの言い方の案')),
            AppButton(
              label: 'なおす',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.s,
              leadingIcon: AppIcons.pencil,
              onTap: () => showComingSoon(context),
            ),
          ],
        ),
        const Text(
          '「ハナさん、美咲さんからご伝言です。\n金曜の通院は、朝10時に\nお迎えに来るそうです。」',
          style: AppTextStyles.capM,
        ),
      ],
    );
  }
}

class _VoiceSettings extends StatelessWidget {
  const _VoiceSettings();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // チップの上下の透明の余白 6 と合わせて、見た目の間隔をモックの 8 にする
      spacing: 2,
      children: [
        Text('話し方', style: AppTextStyles.labelM),
        VoiceSetting(
          label: 'はやさ',
          alternativeLabel: 'ゆっくり',
          minLabel: 'おそい',
          maxLabel: 'はやい',
          initialValue: 35,
        ),
        VoiceSetting(
          label: 'ボリューム',
          alternativeLabel: 'おおきい',
          minLabel: '小さい',
          maxLabel: '大きい',
          initialValue: 70,
        ),
      ],
    );
  }
}

class _AskActions extends StatelessWidget {
  const _AskActions({required this.onCall, required this.onBook});

  final VoidCallback? onCall;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        AppButton(
          label: '通話',
          variant: AppButtonVariant.record,
          size: AppButtonSize.l,
          leadingIcon: AppIcons.phone,
          onTap: onCall,
        ),
        AppButton(
          label: '日時を決めて予約する',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.m,
          onTap: onBook,
        ),
      ],
    );
  }
}
