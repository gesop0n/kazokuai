import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_header.dart';
import 'package:kazokuai/features/home/home_status.dart';
import 'package:kazokuai/features/home/missed_call_view.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/reply_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/tutorial/tutorial_anchor.dart';
import 'package:kazokuai/features/tutorial/tutorial_step.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.data});

  final HomeData? data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(homeStatusProvider);
    // 不在は見本のまま確かめる。通常のホームだけ Firestore の電話を出す
    if (data != null || status != HomeStatus.normal) {
      final shown = data ?? sampleHomeDataFor(status);
      return _Frame(
        person: shown.person,
        now: shown.now,
        onOpenSettings: () => context.pushNamed(AppRoutes.settings),
        body: switch (status) {
          HomeStatus.normal => _HomeCards(data: shown),
          HomeStatus.missedCall => MissedCallView(
            missedCall: shown.missedCall,
            onOpenAsk: () => context.pushNamed(AppRoutes.ask),
          ),
        },
      );
    }
    return _LiveHome(repository: ref.watch(homeRepositoryProvider));
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.person,
    required this.now,
    required this.onOpenSettings,
    required this.body,
  });

  final WatchedPerson person;
  final DateTime now;
  final VoidCallback onOpenSettings;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeader(person: person, now: now, onOpenSettings: onOpenSettings),
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
        // 電話がまだなくても、案内のあいだはモックの見本を出して明るく残す。終わると消す
        final sample = latest == null && TutorialAnchors.samplingOf(context);
        final recent = latest ?? (sample ? sampleHomeData.latestCall : null);
        return _Frame(
          person: view.person,
          now: view.now,
          onOpenSettings: () => context.pushNamed(AppRoutes.settings),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              if (view.reply case final reply?)
                ReplyCard(
                  callName: view.person.callName,
                  reply: reply,
                  now: view.now,
                ),
              if (recent == null)
                const _NoCalls()
              else
                TutorialAnchor(
                  part: TutorialPart.recent,
                  child: RecentCallCard(
                    call: recent,
                    now: latest == null ? sampleHomeData.now : view.now,
                    onOpenConversation: () =>
                        _openConversation(context, recent),
                  ),
                ),
              TutorialAnchor(
                part: TutorialPart.ask,
                child: AskCard(
                  onOpenAsk: () => context.pushNamed(AppRoutes.ask),
                ),
              ),
              if (latest != null)
                view.todayCall == null
                    ? const TutorialAnchor(
                        part: TutorialPart.today,
                        child: TodayCard.undisclosed(),
                      )
                    : TutorialAnchor(
                        part: TutorialPart.today,
                        child: TodayCard(call: view.todayCall!),
                      )
              else if (sample)
                TutorialAnchor(
                  part: TutorialPart.today,
                  child: TodayCard(call: sampleHomeData.latestCall),
                ),
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

void _openConversation(BuildContext context, Call call) {
  final id = call.id;
  if (id == null) {
    context.goNamed(AppRoutes.callDetail);
    return;
  }
  context.goNamed(AppRoutes.callDetailById, pathParameters: {'callId': id});
}

class _HomeCards extends StatelessWidget {
  const _HomeCards({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        TutorialAnchor(
          part: TutorialPart.recent,
          child: RecentCallCard(
            call: data.latestCall,
            now: data.now,
            onOpenConversation: () =>
                _openConversation(context, data.latestCall),
          ),
        ),
        TutorialAnchor(
          part: TutorialPart.ask,
          child: AskCard(onOpenAsk: () => context.pushNamed(AppRoutes.ask)),
        ),
        TutorialAnchor(
          part: TutorialPart.today,
          child: TodayCard(call: data.latestCall),
        ),
      ],
    );
  }
}
