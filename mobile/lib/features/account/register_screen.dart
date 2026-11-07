import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_pill.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

// L2d。2つとも読むとアカウントを作れる。作れると、ルーターがホームに切り替える
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showsPassword = false;
  bool _termsRead = false;
  bool _privacyRead = false;
  bool _creating = false;
  bool _missingFields = false;
  CreateAccountError? _error;

  bool get _bothRead => _termsRead && _privacyRead;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onChanged(String _) => setState(() {
    _missingFields = false;
    _error = null;
  });

  Future<void> _openDocument(String routeName) async {
    final read = await context.pushNamed<bool>(routeName);
    if (read != true || !mounted) return;
    setState(() {
      if (routeName == AppRoutes.terms) _termsRead = true;
      if (routeName == AppRoutes.privacy) _privacyRead = true;
    });
  }

  Future<void> _createAccount() async {
    if (!_bothRead || _creating) return;
    final email = _emailController.text;
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _missingFields = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _creating = true;
      _missingFields = false;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .createAccount(email: email, password: password);
    } on CreateAccountException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String? get _message {
    if (_missingFields) return 'メールアドレスとパスワードを入力してください';
    return switch (_error) {
      null => null,
      CreateAccountError.emailInUse => 'このメールアドレスはすでに使われています',
      CreateAccountError.weakPassword => 'パスワードは$minPasswordLength文字以上にしてください',
      CreateAccountError.other => '登録できませんでした。時間をおいて、もう一度お試しください',
    };
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppNavBar(title: ''),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      const Text('新規登録', style: AppTextStyles.display),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 6,
                        children: [
                          const Text(
                            '先に、次の2つをお読みください',
                            style: AppTextStyles.labelM,
                          ),
                          _AgreeRow(
                            title: '利用規約',
                            read: _termsRead,
                            onTap: () => _openDocument(AppRoutes.terms),
                          ),
                          _AgreeRow(
                            title: 'プライバシーポリシー',
                            read: _privacyRead,
                            onTap: () => _openDocument(AppRoutes.privacy),
                          ),
                        ],
                      ),
                      AppButton(
                        label: 'Googleで登録',
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.l,
                        leading: SvgPicture.asset(
                          'assets/logos/google.svg',
                          width: 20,
                          height: 20,
                          excludeFromSemantics: true,
                        ),
                        onTap: _bothRead ? () => showComingSoon(context) : null,
                      ),
                      const _OrLine(),
                      _LabeledField(
                        label: 'メールアドレス',
                        field: AppTextField(
                          controller: _emailController,
                          semanticLabel: 'メールアドレス',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          onChanged: _onChanged,
                        ),
                      ),
                      _LabeledField(
                        label: 'パスワード',
                        hint: '$minPasswordLength文字以上で入力してください',
                        field: AppTextField(
                          controller: _passwordController,
                          semanticLabel: 'パスワード',
                          obscureText: !_showsPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: _onChanged,
                          onSubmitted: (_) => _createAccount(),
                          trailing: AppIconButton(
                            AppIcons.eye,
                            semanticLabel: _showsPassword
                                ? 'パスワードを隠す'
                                : 'パスワードを表示',
                            iconSize: 22,
                            iconColor: AppColors.inkSecondary,
                            onTap: () => setState(
                              () => _showsPassword = !_showsPassword,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  if (message != null)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.labelM.copyWith(
                          color: AppColors.stateAlertOn,
                        ),
                      ),
                    ),
                  Text(
                    _bothRead ? '登録すると、2つの内容に同意したことになります' : '2つとも読むと登録できます',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  AppButton(
                    label: '同意して登録する',
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.l,
                    onTap: _bothRead && !_creating ? _createAccount : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgreeRow extends StatelessWidget {
  const _AgreeRow({
    required this.title,
    required this.read,
    required this.onTap,
  });

  final String title;
  final bool read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      foregroundColor: AppColors.inkPrimary,
      backgroundColor: AppColors.paperRaised,
      minHeight: 52,
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
      child: Row(
        spacing: 10,
        children: [
          read
              ? const AppPill(
                  variant: AppPillVariant.ok,
                  icon: AppIcons.check,
                  label: '読みました',
                )
              : const AppPill(variant: AppPillVariant.care, label: '未読'),
          Expanded(child: Text(title, style: AppTextStyles.labelM)),
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

class _OrLine extends StatelessWidget {
  const _OrLine();

  @override
  Widget build(BuildContext context) {
    const line = Expanded(
      child: Divider(height: 1, thickness: 1, color: AppColors.lineStrong),
    );
    return Row(
      spacing: 12,
      children: [
        line,
        Text(
          'または',
          style: AppTextStyles.labelM.copyWith(color: AppColors.inkSecondary),
        ),
        line,
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.field, this.hint});

  final String label;
  final Widget field;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        // 入力欄の読み上げと重ならないようにする
        ExcludeSemantics(child: Text(label, style: AppTextStyles.labelM)),
        field,
        if (hint != null)
          Text(
            hint!,
            style: AppTextStyles.bodyS.copyWith(color: AppColors.inkSecondary),
          ),
      ],
    );
  }
}
