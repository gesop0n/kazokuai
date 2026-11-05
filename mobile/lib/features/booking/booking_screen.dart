import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:kazokuai/app/router.dart';
import 'package:kazokuai/design/app_text_styles.dart';

// 遷移を確かめるための仮画面。後の PR で置き換える。
class BookingScreen extends StatelessWidget {
  const BookingScreen({super.key});

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
          const Text('予約電話', style: AppTextStyles.titleL),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => context.pushNamed(AppRoutes.retryRule),
            child: const Text('かけなおしのルール'),
          ),
        ],
      ),
    );
  }
}
