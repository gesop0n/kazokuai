import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/features/home/home_data.dart';

// 枠だけの仮の実装。PR 4 で作る。
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.person,
    required this.now,
    required this.onOpenNotifications,
  });

  final WatchedPerson person;
  final DateTime now;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(person.name, style: AppTextStyles.labelL)),
          AppIconButton(
            AppIcons.bell,
            semanticLabel: '通知',
            onTap: onOpenNotifications,
          ),
        ],
      ),
    );
  }
}
