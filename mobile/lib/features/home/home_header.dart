import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_avatar.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          spacing: 12,
          children: [
            AppAvatar(person.initial, color: AppColors.speakerParent),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${person.name}さん', style: AppTextStyles.labelL),
                  Text(
                    '${formatMonthDayWeekday(now)} ${formatTime(now)} 時点',
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
              onTap: onOpenNotifications,
            ),
          ],
        ),
      ),
    );
  }
}
