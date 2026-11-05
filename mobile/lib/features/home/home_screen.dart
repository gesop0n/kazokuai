import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/calling_banner.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_header.dart';
import 'package:kazokuai/features/home/home_status.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/home/week_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.data});

  final HomeData? data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(homeStatusProvider);
    final data = this.data ?? sampleHomeDataFor(status);
    final isCalling = status == HomeStatus.calling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isCalling) const CallingBanner(),
        Expanded(
          child: SafeArea(
            // 通話中は CallingBanner が状態バーの裏まで伸びる
            top: !isCalling,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeHeader(
                  person: data.person,
                  now: data.now,
                  onOpenNotifications: () => showComingSoon(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: switch (status) {
                      HomeStatus.normal || HomeStatus.calling => _HomeCards(
                        data: data,
                        isCalling: isCalling,
                      ),
                      HomeStatus.missedCall => MissedCallView(
                        missedCall: data.missedCall,
                        now: data.now,
                        onCallAgain: ref
                            .read(homeStatusProvider.notifier)
                            .startCall,
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeCards extends StatelessWidget {
  const _HomeCards({required this.data, required this.isCalling});

  final HomeData data;
  final bool isCalling;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        RecentCallCard(
          call: data.latestCall,
          person: data.person,
          now: data.now,
          onOpenConversation: () => context.pushNamed(AppRoutes.callDetail),
        ),
        AskCard(
          onOpenAsk: () => context.pushNamed(AppRoutes.ask),
          isCalling: isCalling,
        ),
        TodayCard(call: data.latestCall),
        WeekCard(
          week: data.week,
          onOpenCallLog: () => context.goNamed(AppRoutes.calls),
        ),
      ],
    );
  }
}
