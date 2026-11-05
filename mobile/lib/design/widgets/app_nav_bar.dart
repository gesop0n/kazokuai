import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';

class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Semantics(
            container: true,
            button: true,
            label: 'もどる',
            child: InkWell(
              customBorder: const CircleBorder(),
              highlightColor: const Color(0x142A2420),
              onTap: () => Navigator.maybePop(context),
              child: const SizedBox.square(
                dimension: 44,
                child: Center(child: AppIcon(AppIcons.chevronLeft)),
              ),
            ),
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
