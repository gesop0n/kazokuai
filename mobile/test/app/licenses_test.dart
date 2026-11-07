import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kazokuai/app/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ライセンスは BIZ UDPGothic と Lucide で、外したフォントは載らない', () async {
    LicenseRegistry.reset();
    registerLicenses();

    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }

    expect(packages, containsAll(['BIZ UDPGothic', 'Lucide']));
    expect(packages, isNot(contains('Zen Maru Gothic')));
    expect(packages, isNot(contains('Shippori Mincho')));
    expect(packages, isNot(contains('DM Mono')));
  });

  test('同梱するのは BIZ UDPGothic の Regular と Bold だけ', () async {
    final regular = await rootBundle.load(
      'assets/fonts/BIZUDPGothic-Regular.ttf',
    );
    final bold = await rootBundle.load('assets/fonts/BIZUDPGothic-Bold.ttf');
    expect(regular.lengthInBytes, greaterThan(0));
    expect(bold.lengthInBytes, greaterThan(0));

    final license = await rootBundle.loadString(
      'assets/licenses/BIZUDPGothic-OFL.txt',
    );
    expect(license, contains('SIL Open Font License'));

    expect(
      () => rootBundle.load('assets/fonts/ZenMaruGothic-Regular.ttf'),
      throwsFlutterError,
    );
    expect(
      () => rootBundle.load('assets/fonts/ShipporiMincho-Medium.ttf'),
      throwsFlutterError,
    );
    expect(
      () => rootBundle.load('assets/fonts/DMMono-Regular.ttf'),
      throwsFlutterError,
    );
  });
}
