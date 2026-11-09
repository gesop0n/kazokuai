import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_card.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/features/booking/booking_data.dart';

class BookingScreen extends StatelessWidget {
  const BookingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('予約電話', style: AppTextStyles.titleL),
            const SizedBox(height: 8),
            const _BookedCallsCard(),
            const SizedBox(height: 12),
            AppButton(
              label: '新しい予約',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.l,
              leadingIcon: AppIcons.plus,
              onTap: () => context.pushNamed(AppRoutes.ask),
            ),
            const SizedBox(height: 12),
            const _RetryRuleRow(),
          ],
        ),
      ),
    );
  }
}

class _BookedCallsCard extends ConsumerWidget {
  const _BookedCallsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(bookedCallsProvider);
    return AppCard(
      variant: AppCardVariant.paper,
      children: [
        // このカードだけ間隔が 10 なので、1 つの Column にまとめる
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const Text('予約している電話', style: AppTextStyles.titleM),
            for (final (index, call) in calls.indexed)
              _BookedRow(call, index: index),
          ],
        ),
      ],
    );
  }
}

// モックの bookedRow。1 行に日時、伝えたいこと、シェブロンが並ぶ
class _BookedRow extends StatelessWidget {
  const _BookedRow(this.call, {required this.index});

  final BookedCall call;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: AppPressable(
        onTap: () => context.pushNamed(
          AppRoutes.bookingEdit,
          pathParameters: {'index': '$index'},
        ),
        foregroundColor: AppColors.inkPrimary,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          spacing: 12,
          children: [
            SizedBox(
              // モックの幅 72。短い時刻は 1 行で、「11/7 10:00」は 2 行になる。文字倍率に合わせて広げる
              width: MediaQuery.textScalerOf(context).scale(72),
              child: Text(formatBookedAt(call.at), style: AppTextStyles.monoS),
            ),
            Expanded(child: Text(call.message, style: AppTextStyles.labelM)),
            const AppIcon(
              AppIcons.chevronRight,
              size: 18,
              color: AppColors.inkSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryRuleRow extends ConsumerWidget {
  const _RetryRuleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = ref.watch(retryRuleProvider);
    return AppPressable(
      onTap: () => context.pushNamed(AppRoutes.retryRule),
      foregroundColor: AppColors.inkPrimary,
      backgroundColor: AppColors.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadius,
        side: const BorderSide(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.paperSunken,
              shape: BoxShape.circle,
            ),
            child: const AppIcon(AppIcons.rotate, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('かけなおしのルール', style: AppTextStyles.labelL),
                Text(
                  rule.summary,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ],
            ),
          ),
          const AppIcon(
            AppIcons.chevronRight,
            size: 20,
            color: AppColors.inkSecondary,
          ),
        ],
      ),
    );
  }
}
