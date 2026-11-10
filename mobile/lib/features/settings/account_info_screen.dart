import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';
import 'package:kazokuai/features/settings/settings_rows.dart';
import 'package:kazokuai/features/tutorial/tutorial_replay.dart';

// 08e。家族自身のアカウント。名前はここで書き換えて、Auth の表示名に残す
class AccountInfoScreen extends ConsumerStatefulWidget {
  const AccountInfoScreen({super.key});

  @override
  ConsumerState<AccountInfoScreen> createState() => _AccountInfoScreenState();
}

class _AccountInfoScreenState extends ConsumerState<AccountInfoScreen> {
  late final TextEditingController _nameController;
  late final FocusNode _nameFocus;
  bool _nameError = false;

  @override
  void initState() {
    super.initState();
    final account = ref.read(authRepositoryProvider).account.value;
    _nameController = TextEditingController(text: account?.name ?? '');
    _nameFocus = FocusNode()..addListener(_onNameFocus);
  }

  // 欄を離れたら保存する。変わっていなければ何もしない
  void _onNameFocus() {
    if (_nameFocus.hasFocus) return;
    unawaited(_saveName());
  }

  // 見た記録はそのまま。ホームで T1 からもう一度出す
  void _showTutorialAgain() {
    ref.read(tutorialReplayProvider).request();
    context.goNamed(AppRoutes.home);
  }

  Future<void> _saveName() async {
    final next = _nameController.text.trim();
    if (_nameController.text != next) _nameController.text = next;
    final auth = ref.read(authRepositoryProvider);
    if (next == (auth.account.value?.name ?? '')) {
      if (_nameError && mounted) setState(() => _nameError = false);
      return;
    }
    try {
      await auth.updateName(next);
      if (mounted) setState(() => _nameError = false);
    } on UpdateNameException {
      if (mounted) setState(() => _nameError = true);
    }
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_onNameFocus);
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    return ValueListenableBuilder(
      valueListenable: auth.account,
      builder: (context, account, _) {
        final registered = account?.registeredOn;
        return Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppNavBar(
                  title: 'アカウント情報',
                  onLeadingTap: () => popOrGoToParent(context),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      spacing: 16,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SettingsCard(
                          children: [
                            SettingsLabeledField(
                              label: 'あなたのお名前',
                              note: _nameError
                                  ? '名前を保存できませんでした。時間をおいて、もう一度お試しください'
                                  : null,
                              field: AppTextField(
                                controller: _nameController,
                                focusNode: _nameFocus,
                                semanticLabel: 'あなたのお名前',
                                minHeight: 48,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) {
                                  if (_nameError) {
                                    setState(() => _nameError = false);
                                  }
                                },
                                onSubmitted: (_) => _nameFocus.unfocus(),
                              ),
                            ),
                            SettingsInfoRow(
                              label: 'メールアドレス',
                              value: account?.email ?? '',
                            ),
                            SettingsLinkRow(
                              label: 'パスワード',
                              value: '••••••••',
                              onTap: () => showComingSoon(context),
                            ),
                          ],
                        ),
                        SettingsCard(
                          children: [
                            SettingsInfoRow(
                              label: 'ログイン方法',
                              value: account?.signInMethod.label ?? '',
                            ),
                            SettingsInfoRow(
                              label: '登録日',
                              value: registered == null
                                  ? ''
                                  : _formatRegisteredOn(registered),
                            ),
                          ],
                        ),
                        SettingsCard(
                          children: [
                            SettingsLinkRow(
                              label: 'チュートリアル確認',
                              value: '使い方をもう一度見る',
                              onTap: _showTutorialAgain,
                            ),
                          ],
                        ),
                        AppButton(
                          label: 'ログアウト',
                          variant: AppButtonVariant.alertSecondary,
                          size: AppButtonSize.l,
                          leadingIcon: AppIcons.logOut,
                          onTap: () => context.pushNamed(AppRoutes.logout),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// 2026年11月5日。端末の現地の日付にする
String _formatRegisteredOn(DateTime date) {
  final local = date.toLocal();
  return '${local.year}年${local.month}月${local.day}日';
}
