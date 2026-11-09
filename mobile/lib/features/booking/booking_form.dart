import 'package:flutter/material.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

// 01 と 06b が同じ部品を使う。通話内容をいつ出すかと、保存の中身は各画面が決める。

class BookingMessageField extends StatelessWidget {
  const BookingMessageField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

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

class CallScriptCard extends StatelessWidget {
  const CallScriptCard({super.key, required this.script});

  final String script;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Flexible(child: AppAiTag(label: '通話内容')),
            AppButton(
              label: 'なおす',
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.s,
              leadingIcon: AppIcons.pencil,
              onTap: () => showComingSoon(context),
            ),
          ],
        ),
        Text(script, style: AppTextStyles.capM),
      ],
    );
  }
}

class BookingFormActions extends StatelessWidget {
  const BookingFormActions({
    super.key,
    required this.onBook,
    required this.onCall,
    this.callLabel = '今すぐ通話',
  });

  final VoidCallback? onBook;
  final VoidCallback? onCall;

  // 01 は電話の最中、「通話中です」にする。06b は「今すぐ通話」のまま
  final String callLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        AppButton(
          label: 'この日時で予約する',
          variant: AppButtonVariant.primary,
          size: AppButtonSize.l,
          leadingIcon: AppIcons.calendarClock,
          onTap: onBook,
        ),
        AppButton(
          label: callLabel,
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.m,
          leadingIcon: AppIcons.phone,
          onTap: onCall,
        ),
      ],
    );
  }
}

// 01 と 06b の骨組み。モックの foot は画面の下端に固定されている。
// キーボードの分だけ画面を縮めると、その foot がキーボードの上へ持ち上がり、
// 短い画面では入力欄を押しつぶす。開いているあいだは foot を下端に残して
// キーボードの下に隠し、中身はキーボードの上でスクロールする。
// 閉じると、モックどおりボタンはホームバーの上に戻る。
// スマホのブラウザも iOS も、キーボードは viewInsets.bottom で届く。
class BookingFormLayout extends StatelessWidget {
  const BookingFormLayout({
    super.key,
    required this.title,
    required this.onLeadingTap,
    required this.children,
    required this.actions,
  });

  final String title;
  final VoidCallback onLeadingTap;
  final List<Widget> children;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final scroll = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: children,
      ),
    );
    // モックの foot はボタンとホームバーの間も 8 空ける
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: actions,
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(title: title, onLeadingTap: onLeadingTap),
            Expanded(
              child: keyboard == 0
                  ? scroll
                  : Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: keyboard),
                          child: scroll,
                        ),
                        Positioned(left: 0, right: 0, bottom: 0, child: footer),
                      ],
                    ),
            ),
            if (keyboard == 0) footer,
          ],
        ),
      ),
    );
  }
}
