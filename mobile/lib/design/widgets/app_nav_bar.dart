import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';

class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          AppIconButton(
            AppIcons.chevronLeft,
            semanticLabel: 'もどる',
            onTap: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleM,
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}
