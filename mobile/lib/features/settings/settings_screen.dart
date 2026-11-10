import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/features/booking/booking_data.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/settings/settings_rows.dart';

// モックの見本。好きな話題と AI の声は、まだ保存していない。
const _sampleTopics = '家族・孫、庭・花、料理';
const _sampleVoice = 'やさしい女性の声';

enum _Action { comingSoon, account, phone, retry }

class _Entry {
  const _Entry({
    required this.label,
    required this.value,
    required this.action,
    this.field = false,
  });

  final String label;
  final String value;
  final _Action action;

  // 入力欄の形で出す。押すと「準備中です」
  final bool field;
}

// 08。ホームの歯車から開く、見守る方の設定。
// 名前と呼び方は出すが、まだ書き換えられない。
// 同期している電話機は同期の画面を、かけなおしのルールは 07 を開く。
// ほかの行は「準備中です」。アカウント情報は 08e を開く。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeRepositoryProvider);
    final auth = ref.watch(authRepositoryProvider);
    final retry = ref.watch(retryRuleProvider);
    return ValueListenableBuilder(
      valueListenable: home.view,
      builder: (context, view, _) {
        return ValueListenableBuilder(
          valueListenable: auth.account,
          builder: (context, account, _) {
            final person = view?.person;
            return _SettingsBody(
              title: person == null ? '設定' : '${person.name}さんの設定',
              groups: _groups(
                person: person,
                email: account?.email ?? '',
                retrySummary: retry.summary,
              ),
            );
          },
        );
      },
    );
  }
}

// 電話機が結び付いていなければ、まだ同期していない
String _phoneStatus(WatchedPerson? person) =>
    person != null && person.hasPhone ? '同期済み' : 'まだ同期していません';

List<List<_Entry>> _groups({
  required WatchedPerson? person,
  required String email,
  required String retrySummary,
}) => [
  [
    _Entry(
      label: '見守る方のお名前',
      value: person?.name ?? '',
      action: _Action.comingSoon,
      field: true,
    ),
    _Entry(
      label: '電話での呼び方',
      value: person?.callName ?? '',
      action: _Action.comingSoon,
      field: true,
    ),
    const _Entry(
      label: '好きな話題',
      value: _sampleTopics,
      action: _Action.comingSoon,
    ),
    const _Entry(
      label: 'AIの声',
      value: _sampleVoice,
      action: _Action.comingSoon,
    ),
  ],
  [
    _Entry(
      label: '同期している電話機',
      value: _phoneStatus(person),
      action: _Action.phone,
    ),
    _Entry(label: 'かけなおしのルール', value: retrySummary, action: _Action.retry),
  ],
  [_Entry(label: 'アカウント情報', value: email, action: _Action.account)],
];

void _open(BuildContext context, _Action action) {
  switch (action) {
    case _Action.account:
      context.pushNamed(AppRoutes.accountInfo);
    case _Action.phone:
      context.pushNamed(AppRoutes.settingsSync);
    case _Action.retry:
      context.pushNamed(AppRoutes.retryRule);
    case _Action.comingSoon:
      showComingSoon(context);
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody({required this.title, required this.groups});

  final String title;
  final List<List<_Entry>> groups;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(
              title: title,
              onLeadingTap: () => popOrGoToParent(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  spacing: 16,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in groups)
                      SettingsCard(
                        children: [
                          for (final entry in group)
                            entry.field
                                ? SettingsLabeledField(
                                    label: entry.label,
                                    onTap: () => _open(context, entry.action),
                                    semanticsLabel: entry.value.isEmpty
                                        ? entry.label
                                        : '${entry.label}、${entry.value}',
                                    field: SettingsValueField(
                                      value: entry.value,
                                    ),
                                  )
                                : SettingsLinkRow(
                                    label: entry.label,
                                    value: entry.value,
                                    onTap: () => _open(context, entry.action),
                                  ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
