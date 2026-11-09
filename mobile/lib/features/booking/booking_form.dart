import 'package:flutter/material.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_ai_tag.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
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
  });

  final VoidCallback? onBook;
  final VoidCallback? onCall;

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
          label: '今すぐ通話',
          variant: AppButtonVariant.secondary,
          size: AppButtonSize.m,
          leadingIcon: AppIcons.phone,
          onTap: onCall,
        ),
      ],
    );
  }
}
