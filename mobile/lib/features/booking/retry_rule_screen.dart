import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';

// 遷移を確かめるための仮画面。後の PR で置き換える。
class RetryRuleScreen extends StatelessWidget {
  const RetryRuleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(title: 'かけなおしのルール'),
            Expanded(
              child: Center(
                child: Text('電話に出なかったときのルール', style: AppTextStyles.bodyM),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
