import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
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
    // 通話中と不在は、見本のまま確かめる。通常のホームだけ Firestore の電話を出す
    if (data != null || status != HomeStatus.normal) {
      final shown = data ?? sampleHomeDataFor(status);
      return _Frame(
        isCalling: status == HomeStatus.calling,
        person: shown.person,
        now: shown.now,
        onOpenNotifications: () => showComingSoon(context),
        body: switch (status) {
          HomeStatus.normal || HomeStatus.calling => _HomeCards(
            data: shown,
            isCalling: status == HomeStatus.calling,
          ),
          HomeStatus.missedCall => MissedCallView(
            missedCall: shown.missedCall,
            now: shown.now,
            onCallAgain: ref.read(homeStatusProvider.notifier).startCall,
          ),
        },
      );
    }
    return _LiveHome(repository: ref.watch(homeRepositoryProvider));
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.isCalling,
    required this.person,
    required this.now,
    required this.onOpenNotifications,
    required this.body,
  });

  final bool isCalling;
  final WatchedPerson person;
  final DateTime now;
  final VoidCallback onOpenNotifications;
  final Widget body;

  @override
  Widget build(BuildContext context) {
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
                  person: person,
                  now: now,
                  onOpenNotifications: onOpenNotifications,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: body,
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

class _LiveHome extends StatelessWidget {
  const _LiveHome({required this.repository});

  final HomeRepository repository;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: repository.view,
      builder: (context, view, _) {
        if (view == null) return const SizedBox.expand();
        final latest = view.latestCall;
        return _Frame(
          isCalling: false,
          person: view.person,
          now: view.now,
          onOpenNotifications: () => showComingSoon(context),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (latest == null)
                const _NoCalls()
              else
                RecentCallCard(
                  call: latest,
                  now: view.now,
                  onOpenConversation: () =>
                      context.pushNamed(AppRoutes.callDetail),
                ),
              AskCard(onOpenAsk: () => context.pushNamed(AppRoutes.ask)),
              if (latest != null) ...[
                view.todayCall == null
                    ? const TodayCard.undisclosed()
                    : TodayCard(call: view.todayCall!),
                WeekCard(
                  week: view.week,
                  onOpenCallLog: () => context.goNamed(AppRoutes.calls),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NoCalls extends StatelessWidget {
  const _NoCalls();

  @override
  Widget build(BuildContext context) {
    return Text(
      'まだ電話がありません',
      style: AppTextStyles.bodyM.copyWith(color: AppColors.inkSecondary),
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
