import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/app/setup_return.dart';
import 'package:kazokuai/data/auth_repository.dart';
import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

// L6。ログインした家族に見守る方がいないときに開く。登録できると、ルーターがホームに切り替える。
// モックの AI の呼びかけを声で確かめる機能はまだない。L7 もまだないので、進み具合は 1 段階目のまま
// 呼び方をあとから変える画面はまだない。モックの注記だけ出す
class WatchedPersonNameScreen extends ConsumerStatefulWidget {
  const WatchedPersonNameScreen({super.key});

  @override
  ConsumerState<WatchedPersonNameScreen> createState() =>
      _WatchedPersonNameScreenState();
}

class _WatchedPersonNameScreenState
    extends ConsumerState<WatchedPersonNameScreen> {
  final _nameController = TextEditingController();
  final _callNameController = TextEditingController();
  bool _registering = false;
  bool _failed = false;

  String get _name => _nameController.text.trim();
  String get _callName => _callNameController.text.trim();

  bool get _canRegister =>
      !_registering && _name.isNotEmpty && _callName.isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    _callNameController.dispose();
    super.dispose();
  }

  // 入力を直したら、前のメッセージは消す
  void _onChanged(String _) => setState(() => _failed = false);

  // ログインしたままではルーターが L6 に戻すので、ログアウトしてから開く前の画面へ戻す。
  // アプリを開いただけで L6 だったときは、戻る先がホームになる。ログアウトすると L1 に着く
  Future<void> _back() async {
    final setupReturn = ref.read(setupReturnProvider);
    setupReturn.leaving = true;
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      setupReturn.leaving = false;
    }
  }

  Future<void> _register() async {
    if (!_canRegister) return;
    setState(() {
      _registering = true;
      _failed = false;
    });
    try {
      await ref
          .read(watchedPersonRepositoryProvider)
          .register(name: _name, callName: _callName);
    } on RegisterWatchedPersonException {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // キーボードが出るとホームバーの余白がなくなるので、ボタンがキーボードに付かないようにする
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppNavBar(title: 'セットアップ', onLeadingTap: _back),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 24,
                  children: [
                    const _SetupProgress(step: 1, steps: 2),
                    const Text(
                      '見守る方のお名前を\n教えてください',
                      style: AppTextStyles.titleL,
                    ),
                    _LabeledField(
                      label: 'お名前',
                      field: AppTextField(
                        controller: _nameController,
                        semanticLabel: 'お名前',
                        textInputAction: TextInputAction.next,
                        onChanged: _onChanged,
                      ),
                    ),
                    _LabeledField(
                      label: '電話での呼び方',
                      note: '※あとから変えられます。',
                      field: AppTextField(
                        controller: _callNameController,
                        semanticLabel: '電話での呼び方',
                        textInputAction: TextInputAction.done,
                        onChanged: _onChanged,
                        onSubmitted: (_) => _register(),
                      ),
                    ),
                    if (_failed) const _ErrorMessage(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppButton(
                label: '次へ',
                variant: AppButtonVariant.primary,
                size: AppButtonSize.l,
                onTap: _canRegister ? _register : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// モックの .prog。終わった段階は ink、残りの段階は line-strong
class _SetupProgress extends StatelessWidget {
  const _SetupProgress({required this.step, required this.steps});

  final int step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$steps段階のうち$step段階目',
      child: Row(
        spacing: 6,
        children: [
          for (var i = 0; i < steps; i++)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: i < step ? AppColors.inkPrimary : AppColors.lineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const SizedBox(height: 4),
              ),
            ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.field, this.note});

  final String label;
  final Widget field;

  // 見出しの右に出す、小さい注記。モックは label の中の span
  final String? note;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 入力欄の読み上げと重ならないようにする。注記は読み上げる
            ExcludeSemantics(child: Text(label, style: AppTextStyles.labelM)),
            if (note != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // モックは注記の前に空白を 1 つ置く
                  const Text(' ', style: AppTextStyles.bodyS),
                  Text(
                    note,
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),
        field,
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        '登録できませんでした。時間をおいて、もう一度お試しください',
        style: AppTextStyles.labelM.copyWith(color: AppColors.stateAlert),
      ),
    );
  }
}
