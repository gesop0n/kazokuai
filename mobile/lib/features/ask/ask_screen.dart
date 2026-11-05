import 'package:flutter/material.dart';

import 'package:kazokuai/design/app_text_styles.dart';
import 'package:kazokuai/design/widgets/app_nav_bar.dart';

// 遷移を確かめるための仮画面。後の PR で置き換える。
class AskScreen extends StatelessWidget {
  const AskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(title: 'AIに伝えてもらう'),
            Expanded(
              child: Center(
                child: Text('伝えたいことを入力する画面', style: AppTextStyles.bodyM),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
