import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/loading_screen.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/widgets/app_tab_bar.dart';
import 'package:kazokuai/features/account/document_screen.dart';
import 'package:kazokuai/features/account/login_screen.dart';
import 'package:kazokuai/features/account/password_reset_screen.dart';
import 'package:kazokuai/features/account/register_screen.dart';
import 'package:kazokuai/features/account/sample_documents.dart';
import 'package:kazokuai/features/account/welcome_screen.dart';
import 'package:kazokuai/features/ask/ask_screen.dart';
import 'package:kazokuai/features/booking/booking_edit_screen.dart';
import 'package:kazokuai/features/booking/booking_screen.dart';
import 'package:kazokuai/features/booking/retry_rule_screen.dart';
import 'package:kazokuai/features/calls/call_detail_screen.dart';
import 'package:kazokuai/features/calls/calls_screen.dart';
import 'package:kazokuai/features/home/home_screen.dart';
import 'package:kazokuai/features/setup/watched_person_name_screen.dart';

abstract final class AppRoutes {
  static const welcome = 'welcome';
  static const login = 'login';
  static const passwordReset = 'passwordReset';
  static const register = 'register';
  static const terms = 'terms';
  static const privacy = 'privacy';
  static const loading = 'loading';
  static const watchedPersonName = 'watchedPersonName';
  static const home = 'home';
  static const calls = 'calls';
  static const booking = 'booking';
  static const ask = 'ask';
  static const callDetail = 'callDetail';
  static const callDetailById = 'callDetailById';
  static const retryRule = 'retryRule';
  static const bookingEdit = 'bookingEdit';
}

// ログインする前に開ける画面は、すべてこの下に置く
const _signedOutPath = '/welcome';
// ログインした家族に見守る方がいるかを読み終えるまでと、読めなかったときに開く
const _loadingPath = '/loading';
const _watchedPersonNamePath = '/setup/name';

GoRouter createAppRouter({
  required AuthRepository auth,
  required WatchedPersonRepository watchedPerson,
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    // ログインしていない家族は L1 に、見守る方がいない家族は L6 に、それ以外は開いている道に残す
    refreshListenable: Listenable.merge([auth.signedIn, watchedPerson.status]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!auth.signedIn.value) {
        // ログアウトすると L1 に戻す。見守る方が続いて unknown になっても、
        // この分岐が先なので、読み込み中の画面には進まない
        return location.startsWith(_signedOutPath) ? null : _signedOutPath;
      }
      switch (watchedPerson.status.value) {
        case WatchedPersonStatus.unknown:
        case WatchedPersonStatus.unreadable:
          // 読み終えるまで道を変えない。読み込み中はアプリが上に出す。
          // /loading へ付け替えると、読み終えたあとホームへ戻り、読み直した画面を失う
          return null;
        case WatchedPersonStatus.none:
          return location == _watchedPersonNamePath
              ? null
              : _watchedPersonNamePath;
        case WatchedPersonStatus.registered:
          final isBeforeHome =
              location.startsWith(_signedOutPath) ||
              location == _loadingPath ||
              location == _watchedPersonNamePath;
          return isBeforeHome ? '/home' : null;
      }
    },
    routes: [
      GoRoute(
        name: AppRoutes.welcome,
        path: _signedOutPath,
        builder: (context, state) => const WelcomeScreen(),
        routes: [
          GoRoute(
            name: AppRoutes.login,
            path: 'login',
            builder: (context, state) => const LoginScreen(),
            routes: [
              GoRoute(
                name: AppRoutes.passwordReset,
                path: 'reset',
                builder: (context, state) => const PasswordResetScreen(),
              ),
            ],
          ),
          GoRoute(
            name: AppRoutes.register,
            path: 'register',
            builder: (context, state) => const RegisterScreen(),
            routes: [
              GoRoute(
                name: AppRoutes.terms,
                path: 'terms',
                builder: (context, state) =>
                    const DocumentScreen(document: termsDocument),
              ),
              GoRoute(
                name: AppRoutes.privacy,
                path: 'privacy',
                builder: (context, state) =>
                    const DocumentScreen(document: privacyDocument),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        name: AppRoutes.loading,
        path: _loadingPath,
        builder: (context, state) => const LoadingScreen(),
      ),
      GoRoute(
        name: AppRoutes.watchedPersonName,
        path: _watchedPersonNamePath,
        builder: (context, state) => const WatchedPersonNameScreen(),
      ),
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
                routes: [
                  GoRoute(
                    name: AppRoutes.callDetail,
                    path: 'detail',
                    builder: (context, state) => const CallDetailScreen(),
                  ),
                  // 見本の子にすると、戻る先が見本の詳細になる
                  GoRoute(
                    name: AppRoutes.callDetailById,
                    path: 'detail/:callId',
                    builder: (context, state) => CallDetailScreen(
                      callId: state.pathParameters['callId'],
                    ),
                  ),
                ],
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
        name: AppRoutes.bookingEdit,
        path: '/booking/edit/:index',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            BookingEditRoute(index: state.pathParameters['index'] ?? ''),
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
