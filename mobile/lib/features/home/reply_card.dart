import 'package:flutter/widgets.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_format.dart';

// モックの replyCard。伝言への返答を、直近の電話の上に出す。
class ReplyCard extends StatelessWidget {
  const ReplyCard({
    super.key,
    required this.callName,
    required this.reply,
    required this.now,
  });

  final String callName;
  final Reply reply;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text('$callNameからのお返事', style: AppTextStyles.titleM),
            Text(
              '${formatRelativeDay(reply.saidAt, now)} ${formatTime(reply.saidAt)}',
              // Wrap には baseline 揃えがないので、行の高さを見出しと同じにして揃える
              strutStyle: StrutStyle.fromTextStyle(
                AppTextStyles.titleM,
                forceStrutHeight: true,
              ),
              style: AppTextStyles.monoS.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(
              '伝えたこと',
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
            Text(reply.told, style: AppTextStyles.bodyM),
          ],
        ),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                callName,
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.speakerParent,
                ),
              ),
              Text(reply.text, style: AppTextStyles.titleM),
            ],
          ),
        ),
      ],
    );
  }
}
