import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';

// L1。ログインしていないときに開く
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('かぞくAI', style: AppTextStyles.titleM),
                    const SizedBox(height: 8),
                    const _WelcomeIllustration(),
                    const SizedBox(height: 16),
                    Text(
                      '離れていても、\nいつもの電話で見守れる',
                      style: AppTextStyles.display.copyWith(
                        fontSize: 26,
                        height: 36 / 26,
                        letterSpacing: .02 * 26,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ご実家の専用の固定電話に、AIがお電話します。\n話した様子を、このアプリにお届けします。',
                      style: AppTextStyles.bodyM.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        _WelcomeLine(AppIcons.phone, '親御さんは、電話に出るだけで大丈夫'),
                        _WelcomeLine(AppIcons.sparkles, '話した様子を、短くまとめてお届け'),
                        _WelcomeLine(AppIcons.pencil, '伝えたいことや電話の時間は、ご家族で'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  // 新規登録は次に作る
                  AppButton(
                    label: 'はじめる',
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.l,
                    onTap: () => showComingSoon(context),
                  ),
                  AppButton(
                    label: 'アカウントをお持ちの方はログイン',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.m,
                    onTap: () => context.goNamed(AppRoutes.login),
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

// おじいちゃんと娘の絵に、吹き出しとハートを重ねた 1 枚の絵。
// 幅が足りないときは全体を縮める。吹き出しの文字だけが大きくなると重なるので、文字倍率には従わない
class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: MediaQuery.withNoTextScaling(
        child: SizedBox(
          width: 345,
          height: 232,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 42,
                child: SvgPicture.asset(
                  'assets/illustrations/grandpa.svg',
                  width: 164,
                  height: 190,
                  semanticsLabel: '固定電話で話しながら笑っているおじいちゃん',
                ),
              ),
              Positioned(
                right: 0,
                top: 42,
                child: SvgPicture.asset(
                  'assets/illustrations/daughter.svg',
                  width: 164,
                  height: 190,
                  semanticsLabel: 'スマートフォンを見ながら笑っている娘',
                ),
              ),
              Positioned(
                left: 154,
                top: 122,
                child: Container(
                  width: 37,
                  height: 37,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.paperRaised,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x2E3A2A19),
                        offset: Offset(0, 2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: SvgPicture.asset(
                    'assets/illustrations/heart.svg',
                    width: 20,
                    height: 20,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                top: 0,
                child: _Bubble('よく眠れたよ。', tail: _BubbleTail.left),
              ),
              const Positioned(
                right: 0,
                top: 0,
                child: _Bubble('元気そうでよかった。', tail: _BubbleTail.right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BubbleTail { left, right }

class _Bubble extends StatelessWidget {
  const _Bubble(this.text, {required this.tail});

  static const _radius = Radius.circular(18);
  static const _tailRadius = Radius.circular(6);

  final String text;
  final _BubbleTail tail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paperRaised,
        border: Border.all(color: AppColors.line),
        // 話している人の側の下の角を、しっぽにする
        borderRadius: BorderRadius.only(
          topLeft: _radius,
          topRight: _radius,
          bottomLeft: tail == _BubbleTail.left ? _tailRadius : _radius,
          bottomRight: tail == _BubbleTail.right ? _tailRadius : _radius,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x143A2A19),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(text, style: AppTextStyles.capS),
    );
  }
}

class _WelcomeLine extends StatelessWidget {
  const _WelcomeLine(this.icon, this.text);

  final AppIcons icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.stateCareSoft,
            shape: BoxShape.circle,
          ),
          child: AppIcon(icon, size: 18, color: AppColors.stateCareOn),
        ),
        Expanded(child: Text(text, style: AppTextStyles.labelM)),
      ],
    );
  }
}
