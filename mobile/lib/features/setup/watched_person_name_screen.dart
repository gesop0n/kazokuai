import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kazokuai/data/watched_person_repository.dart';
import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_button.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';
import 'package:kazokuai/design/widgets/app_text_field.dart';

// L6。ログインした家族に見守る方がいないときに開く。登録できると、ルーターがホームに切り替える。
// モックの AI の呼びかけを声で確かめる機能と、L7 へ進む段階の表示はまだない。
// 呼び方をあとから変える画面もまだないので、モックの「※あとから変えられます。」は書かない
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
            const AppNavBar(title: 'セットアップ', showsBack: false),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 24,
                  children: [
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

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.field});

  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        // 入力欄の読み上げと重ならないようにする
        ExcludeSemantics(child: Text(label, style: AppTextStyles.labelM)),
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
        style: AppTextStyles.labelM.copyWith(color: AppColors.stateAlertOn),
      ),
    );
  }
}
