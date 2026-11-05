import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';

abstract final class AppRoutes {
  static const home = 'home';
  static const calls = 'calls';
  static const booking = 'booking';
  static const ask = 'ask';
  static const callDetail = 'callDetail';
  static const retryRule = 'retryRule';
}

GoRouter createAppRouter() {
  final rootNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => Scaffold(
          // 本文をタブバーの下まで伸ばす。タブバーの高さは本文の MediaQuery の padding.bottom に入る
          extendBody: true,
          body: navigationShell,
          bottomNavigationBar: AppTabBar(
            currentIndex: navigationShell.currentIndex,
            onSelected: navigationShell.goBranch,
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppRoutes.home,
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppRoutes.calls,
                path: '/calls',
                builder: (context, state) => const CallsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                name: AppRoutes.booking,
                path: '/booking',
                builder: (context, state) => const BookingScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        name: AppRoutes.ask,
        path: '/ask',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AskScreen(),
      ),
      GoRoute(
        name: AppRoutes.callDetail,
        path: '/call-detail',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CallDetailScreen(),
      ),
      GoRoute(
        name: AppRoutes.retryRule,
        path: '/retry-rule',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const RetryRuleScreen(),
      ),
    ],
  );
}
