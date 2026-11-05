import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';

// 遷移を確かめるための仮画面。後の PR で置き換える。
class CallDetailScreen extends StatelessWidget {
  const CallDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(title: '朝の電話'),
            Expanded(
              child: Center(child: Text('通話記録の詳細', style: AppTextStyles.bodyM)),
            ),
          ],
        ),
      ),
    );
  }
}
