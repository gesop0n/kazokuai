import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// 色、文字、アイコンを確かめるための仮画面。PR 3 で置き換える。
class FoundationPreviewScreen extends StatelessWidget {
  const FoundationPreviewScreen({super.key});

  static const _textStyles = [
    ('display', AppTextStyles.display, '親の様子'),
    ('titleL', AppTextStyles.titleL, '親の様子を確かめる'),
    ('titleM', AppTextStyles.titleM, '親の様子を確かめる'),
    ('labelL', AppTextStyles.labelL, '親の様子を、ひと目で確かめる'),
    ('labelM', AppTextStyles.labelM, '親の様子を、ひと目で確かめる'),
    ('labelS', AppTextStyles.labelS, '親の様子を、ひと目で確かめる'),
    ('bodyM', AppTextStyles.bodyM, '親の様子を、ひと目で確かめる'),
    ('bodyS', AppTextStyles.bodyS, '親の様子を、ひと目で確かめる'),
    ('capM', AppTextStyles.capM, '「よく眠れたよ。」'),
    ('capS', AppTextStyles.capS, '「朝ごはんも食べたしね。」'),
    ('monoM', AppTextStyles.monoM, '9:02　6分12秒　03-0000-0000'),
    ('monoS', AppTextStyles.monoS, '9:02　6分12秒　03-0000-0000'),
  ];

  static const _colors = [
    AppColors.paperBase,
    AppColors.paperRaised,
    AppColors.paperSunken,
    AppColors.inkPrimary,
    AppColors.inkSecondary,
    AppColors.line,
    AppColors.lineStrong,
    AppColors.accentCall,
    AppColors.stateCareSoft,
    AppColors.stateOkSoft,
    AppColors.stateAlert,
    AppColors.stateAlertSoft,
    AppColors.nightBase,
    AppColors.speakerAi,
    AppColors.speakerParent,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (name, style, sample) in _textStyles)
              Text('$name $sample', style: style),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [for (final icon in AppIcons.values) AppIcon(icon)],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in _colors)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
