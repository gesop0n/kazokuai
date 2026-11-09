import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_colors.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/widgets/app_pressable.dart';

// モックの .agreebox。24 の四角で、角の丸みは 6、枠は 1.5 の line-strong。
// チェックが付くと ink の地に白いチェックが出る。押せない間は paper-sunken。
// 押せる範囲は 44 × 56。onTap が null のときは押せない。
class AppAgreeBox extends StatelessWidget {
  const AppAgreeBox({
    super.key,
    required this.checked,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool checked;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final showsCheck = checked && enabled;
    return Semantics(
      container: true,
      label: semanticLabel,
      checked: checked,
      enabled: enabled,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            overlayColor: WidgetStatePropertyAll(
              AppPressable.overlayOf(AppColors.inkPrimary),
            ),
            child: SizedBox(
              width: 44,
              height: 56,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: !enabled
                        ? AppColors.paperSunken
                        : showsCheck
                        ? AppColors.inkPrimary
                        : null,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: showsCheck
                          ? AppColors.inkPrimary
                          : AppColors.lineStrong,
                      width: 1.5,
                    ),
                  ),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: showsCheck
                        ? const Center(
                            child: AppIcon(
                              AppIcons.check,
                              size: 16,
                              color: AppColors.white,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
