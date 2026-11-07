import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kazokuai/data/home_repository.dart';
import 'package:kazokuai/features/home/home_data.dart';
import 'package:kazokuai/features/home/sample_home_data.dart';

// ホームに出す中身を、テストが直接決める
class FakeHomeRepository implements HomeRepository {
  FakeHomeRepository(HomeView? view) : view = ValueNotifier(view);

  @override
  final ValueNotifier<HomeView?> view;
}

// 見本のホーム。アプリ全体のテストが、Firestore を起動せずに今までどおり進むために使う
Override sampleHome() => homeRepositoryProvider.overrideWithValue(
  FakeHomeRepository(
    HomeView(
      person: sampleHomeData.person,
      now: sampleHomeData.now,
      latestCall: sampleHomeData.latestCall,
      todayCall: sampleHomeData.latestCall,
      week: sampleHomeData.week,
    ),
  ),
);
