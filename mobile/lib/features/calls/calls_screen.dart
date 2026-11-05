import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_icon.dart';

// 遷移とスクロール位置の保持を確かめるための仮画面。後の PR で置き換える。
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  static const recordCount = 30;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      // padding を指定しないと、タブバーの高さが MediaQuery から下の余白に入る
      child: ListView.builder(
        itemCount: recordCount,
        itemBuilder: (context, index) => ListTile(
          title: Text('記録 ${index + 1}'),
          trailing: const AppIcon(AppIcons.chevronRight),
          onTap: () => context.pushNamed(AppRoutes.callDetail),
        ),
      ),
    );
  }
}
