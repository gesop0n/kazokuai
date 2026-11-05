import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/features/home/ask_card.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/home_header.dart';
import 'package:kazokuai/features/home/recent_call_card.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';
import 'package:kazokuai/features/home/today_card.dart';
import 'package:kazokuai/features/home/week_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.data});

  final HomeData? data;

  @override
  Widget build(BuildContext context) {
    final data = this.data ?? sampleHomeData;
    return SafeArea(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  RecentCallCard(
                    call: data.latestCall,
                    person: data.person,
                    now: data.now,
                    onOpenConversation: () =>
                        context.pushNamed(AppRoutes.callDetail),
                  ),
                  AskCard(onOpenAsk: () => context.pushNamed(AppRoutes.ask)),
                  TodayCard(call: data.latestCall),
                  WeekCard(
                    week: data.week,
                    onOpenCallLog: () => context.goNamed(AppRoutes.calls),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
