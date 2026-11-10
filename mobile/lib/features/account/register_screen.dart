import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_agree_box.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_icon_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

// L2b と L2d。文書の終わりで「同意する」を押すまで、そのチェックは押せない。
// 2つともチェックが付いているときだけアカウントを作れる。作れると、ルーターがホームに切り替える。
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showsPassword = false;
  bool _termsChecked = false;
  bool _privacyChecked = false;

  // 「同意する」を一度押すと、そのあとはチェックを切り替えられる
  bool _termsUnlocked = false;
  bool _privacyUnlocked = false;
  bool _creating = false;
  bool _googleSigningIn = false;
  bool _missingFields = false;
  CreateAccountError? _error;
  SignInError? _googleError;

  bool get _bothChecked => _termsChecked && _privacyChecked;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onChanged(String _) => setState(() {
    _missingFields = false;
    _error = null;
    _googleError = null;
  });

  Future<void> _openDocument(String routeName) async {
    final agreed = await context.pushNamed<bool>(routeName);
    if (agreed != true || !mounted) return;
    setState(() {
      if (routeName == AppRoutes.terms) {
        _termsUnlocked = true;
        _termsChecked = true;
      }
      if (routeName == AppRoutes.privacy) {
        _privacyUnlocked = true;
        _privacyChecked = true;
      }
    });
  }

  Future<void> _createAccount() async {
    if (!_bothChecked || _creating || _googleSigningIn) return;
    final email = _emailController.text;
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _missingFields = true;
        _error = null;
        _googleError = null;
      });
      return;
    }
    setState(() {
      _creating = true;
      _missingFields = false;
      _error = null;
      _googleError = null;
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

  Future<void> _signInWithGoogle() async {
    if (!_bothChecked || _creating || _googleSigningIn) return;
    setState(() {
      _googleSigningIn = true;
      _missingFields = false;
      _error = null;
      _googleError = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on SignInException catch (e) {
      if (mounted) setState(() => _googleError = e.error);
    } finally {
      if (mounted) setState(() => _googleSigningIn = false);
    }
  }

  String? get _message {
    if (_missingFields) return 'メールアドレスとパスワードを入力してください';
    // Google の失敗は、ログインの画面と同じ文にする。Firebase の文はそのまま出さない
    if (_googleError != null) {
      return 'ログインできませんでした。時間をおいて、もう一度お試しください';
    }
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
    final googleOnWeb = ref.watch(googleSignInOnWebProvider);
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
                            'それぞれ開いて内容を読み、同意してください',
                            style: AppTextStyles.labelM,
                          ),
                          _AgreeRow(
                            title: '利用規約',
                            checked: _termsChecked,
                            locked: !_termsUnlocked,
                            onToggle: () =>
                                setState(() => _termsChecked = !_termsChecked),
                            onOpen: () => _openDocument(AppRoutes.terms),
                          ),
                          _AgreeRow(
                            title: 'プライバシーポリシー',
                            checked: _privacyChecked,
                            locked: !_privacyUnlocked,
                            onToggle: () => setState(
                              () => _privacyChecked = !_privacyChecked,
                            ),
                            onOpen: () => _openDocument(AppRoutes.privacy),
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
                        onTap: !googleOnWeb
                            ? (_bothChecked
                                  ? () => showComingSoon(context)
                                  : null)
                            : (_bothChecked && !_googleSigningIn && !_creating
                                  ? _signInWithGoogle
                                  : null),
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
                          color: AppColors.stateAlert,
                        ),
                      ),
                    ),
                  AppButton(
                    label: '登録する',
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.l,
                    onTap: _bothChecked && !_creating && !_googleSigningIn
                        ? _createAccount
                        : null,
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
    required this.checked,
    required this.locked,
    required this.onToggle,
    required this.onOpen,
  });

  final String title;
  final bool checked;
  final bool locked;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        borderRadius: AppRadius.borderRadius,
        border: Border.all(color: AppColors.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          // モックは左余白 12 と、チェックの margin-left -10。押せる範囲の左端は 2
          padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
          child: Row(
            spacing: 2,
            children: [
              AppAgreeBox(
                checked: checked,
                semanticLabel: '$titleに同意',
                onTap: locked ? null : onToggle,
              ),
              Expanded(
                child: AppPressable(
                  onTap: onOpen,
                  foregroundColor: AppColors.inkPrimary,
                  shape: const RoundedRectangleBorder(),
                  minHeight: 56,
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Text('$titleに同意する', style: AppTextStyles.labelM),
                      ),
                      const AppIcon(
                        AppIcons.chevronRight,
                        size: 20,
                        color: AppColors.inkSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
