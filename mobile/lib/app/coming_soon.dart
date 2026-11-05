import 'package:flutter/material.dart';

// 遷移先がないボタンから呼ぶ
void showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('準備中です'), duration: Duration(seconds: 2)),
    );
}
