import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/features/settings/account_info_screen.dart';
import 'package:kazokuai/features/settings/logout_screen.dart';
import 'package:kazokuai/features/settings/settings_screen.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_home_repository.dart';
import '../../support/layout_matrix.dart';

void main() {
  testEachLayout('08 が崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const SettingsScreen(),
      overrides: [signedInAuth(), sampleHome()],
    );

    expect(find.text('田中ハナさんの設定'), findsOneWidget);
    expect(find.text('アカウント情報'), findsOneWidget);
  });

  testEachLayout('08e が崩れない', (tester, layout) async {
    await pumpScreenInLayout(
      tester,
      layout,
      const AccountInfoScreen(),
      overrides: [signedInAuth()],
    );

    expect(find.text('田中 太郎'), findsOneWidget);
    expect(find.text('2026年11月5日'), findsOneWidget);
    expect(find.text('ログアウト'), findsOneWidget);
  });

  testEachLayout('08d が崩れない', (tester, layout) async {
    await pumpScreenInLayout(tester, layout, const LogoutScreen());

    expect(find.text('ログアウトしますか？'), findsOneWidget);
    expect(find.text('ログアウトする'), findsOneWidget);
    expect(find.text('アカウント情報にもどる'), findsOneWidget);
  });
}
