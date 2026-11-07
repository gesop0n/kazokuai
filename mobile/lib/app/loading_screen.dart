import 'package:flutter/material.dart';

// ログインした家族に見守る方がいるかを読み終えるまでの画面。
// 読むのはすぐに終わるので、ちらつかないように何も描かない
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(label: '読み込んでいます', child: const SizedBox.expand()),
    );
  }
}
