import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/coming_soon.dart';
import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_icon.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// 遷移を確かめるための仮画面。PR 4 と 5 で置き換える。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              const Expanded(child: Text('ホーム', style: AppTextStyles.titleL)),
              IconButton(
                tooltip: '通知',
                onPressed: () => showComingSoon(context),
                icon: const AppIcon(AppIcons.bell),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.pushNamed(AppRoutes.callDetail),
            child: const Text('会話を見る'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.pushNamed(AppRoutes.ask),
            child: const Text('AIに伝えてもらう'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.goNamed(AppRoutes.calls),
            child: const Text('通話記録を見る'),
          ),
        ],
      ),
    );
  }
}
