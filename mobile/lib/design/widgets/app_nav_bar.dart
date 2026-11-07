import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';

class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.title, this.showsBack = true});

  final String title;
  // もどる先のない画面では false にする。題名は真ん中のまま
  final bool showsBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (showsBack)
            AppIconButton(
              AppIcons.chevronLeft,
              semanticLabel: 'もどる',
              onTap: () => Navigator.maybePop(context),
            )
          else
            const SizedBox(width: 44),
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
