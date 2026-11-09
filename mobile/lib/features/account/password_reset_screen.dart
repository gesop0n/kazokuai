import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_radius.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

// L2a。再設定のメールを送り、同じ画面に結果を出す。L2ab は送れなかったとき
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  ConsumerState<PasswordResetScreen> createState() =>
      _PasswordResetScreenState();
}

enum _ResetResult { none, sent, failed }

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  final _emailController = TextEditingController();
  _ResetResult _result = _ResetResult.none;
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _result == _ResetResult.sent) return;
    _sending = true;
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPasswordResetEmail(email: _emailController.text);
      if (mounted) setState(() => _result = _ResetResult.sent);
    } on PasswordResetException {
      if (mounted) setState(() => _result = _ResetResult.failed);
    } finally {
      _sending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _result == _ResetResult.sent;
    final failed = _result == _ResetResult.failed;
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          const Text('パスワードの再設定', style: AppTextStyles.display),
                          Text(
                            '登録したメールアドレスを入力してください。再設定用のリンクをメールでお送りします。',
                            style: AppTextStyles.bodyM.copyWith(
                              color: AppColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                      _LabeledField(
                        label: 'メールアドレス',
                        field: AppTextField(
                          controller: _emailController,
                          semanticLabel: 'メールアドレス',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      if (sent) const _ResetNotice.sent(),
                      if (failed) const _ResetNotice.failed(),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppButton(
                label: sent
                    ? 'ログインにもどる'
                    : failed
                    ? 'もう一度送る'
                    : '再設定メールを送る',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                leadingIcon: failed ? AppIcons.rotate : null,
                onTap: sent ? () => context.pop() : _send,
              ),
            ),
          ],
        ),
      ),
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

// 送れたときと、どんな失敗でも出す注意。アイコンの円は 36、アイコンは 18
class _ResetNotice extends StatelessWidget {
  const _ResetNotice.sent()
    : title = 'メールを送信しました',
      body = '届いたメールのリンクから、新しいパスワードを設定してください。',
      bodyColor = AppColors.inkSecondary,
      background = AppColors.paperRaised,
      borderColor = AppColors.line,
      borderWidth = 1,
      icon = AppIcons.check,
      iconColor = AppColors.inkPrimary,
      iconBackground = AppColors.stateOkSoft;

  const _ResetNotice.failed()
    : title = 'メールを送信できませんでした',
      body = 'メールアドレスと通信状況を確認して、もう一度お試しください。',
      bodyColor = AppColors.inkPrimary,
      background = AppColors.stateAlertSoft,
      borderColor = AppColors.stateAlert,
      borderWidth = 2,
      icon = AppIcons.alert,
      iconColor = AppColors.stateAlert,
      iconBackground = AppColors.paperRaised;

  final String title;
  final String body;
  final Color bodyColor;
  final Color background;
  final Color borderColor;
  final double borderWidth;
  final AppIcons icon;
  final Color iconColor;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.borderRadius,
          border: Border.all(color: borderColor, width: borderWidth),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBackground,
                shape: BoxShape.circle,
              ),
              child: AppIcon(icon, size: 18, color: iconColor),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 2,
                children: [
                  Text(title, style: AppTextStyles.labelL),
                  Text(
                    body,
                    style: AppTextStyles.bodyS.copyWith(color: bodyColor),
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
