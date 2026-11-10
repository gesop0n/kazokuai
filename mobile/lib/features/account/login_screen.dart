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
import 'package:kazokuai/design/widgets/app_text_field.dart';

// L2。ログインできると、ルーターがホームに切り替える
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showsPassword = false;
  bool _signingIn = false;
  SignInError? _error;

  bool get _canSignIn =>
      !_signingIn &&
      _emailController.text.isNotEmpty &&
      _passwordController.text.isNotEmpty;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // 入力を直したら、前のメッセージは消す
  void _onChanged(String _) => setState(() => _error = null);

  Future<void> _signIn() async {
    if (!_canSignIn) return;
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
    } on SignInException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_signingIn) return;
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on SignInException catch (e) {
      if (mounted) setState(() => _error = e.error);
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final googleOnWeb = ref.watch(googleSignInOnWebProvider);
    return Scaffold(
      body: SafeArea(
        // キーボードが出るとホームバーの余白がなくなるので、ボタンがキーボードに付かないようにする
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
                    spacing: 16,
                    children: [
                      const Text('ログイン', style: AppTextStyles.display),
                      AppButton(
                        label: 'Googleでログイン',
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.l,
                        leading: SvgPicture.asset(
                          'assets/logos/google.svg',
                          width: 20,
                          height: 20,
                          excludeFromSemantics: true,
                        ),
                        onTap: googleOnWeb
                            ? (_signingIn ? null : _signInWithGoogle)
                            : () => showComingSoon(context),
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
                        field: AppTextField(
                          controller: _passwordController,
                          semanticLabel: 'パスワード',
                          obscureText: !_showsPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onChanged: _onChanged,
                          onSubmitted: (_) => _signIn(),
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
                      if (error != null) _ErrorMessage(error),
                      AppButton(
                        label: 'ログイン',
                        variant: AppButtonVariant.primary,
                        size: AppButtonSize.l,
                        onTap: _canSignIn ? _signIn : null,
                      ),
                      Center(
                        child: AppButton(
                          label: 'パスワードを忘れた場合',
                          variant: AppButtonVariant.ghostInk,
                          size: AppButtonSize.m,
                          underlined: true,
                          onTap: () =>
                              context.pushNamed(AppRoutes.passwordReset),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppButton(
                label: 'はじめての方は新規登録',
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.m,
                underlined: true,
                onTap: () => context.pushNamed(AppRoutes.register),
              ),
            ),
          ],
        ),
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
  const _LabeledField({required this.label, required this.field});

  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        // 入力欄の読み上げと重ならないようにする
        ExcludeSemantics(child: Text(label, style: AppTextStyles.labelM)),
        field,
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.error);

  final SignInError error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(switch (error) {
        SignInError.wrongCredentials => 'メールアドレスかパスワードが違います',
        SignInError.other => 'ログインできませんでした。時間をおいて、もう一度お試しください',
      }, style: AppTextStyles.labelM.copyWith(color: AppColors.stateAlert)),
    );
  }
}
