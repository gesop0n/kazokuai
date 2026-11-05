import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _licenses = {
  'Zen Maru Gothic': 'assets/licenses/ZenMaruGothic-OFL.txt',
  'Shippori Mincho': 'assets/licenses/ShipporiMincho-OFL.txt',
  'DM Mono': 'assets/licenses/DMMono-OFL.txt',
  'Lucide': 'assets/licenses/Lucide-LICENSE.txt',
};

void registerLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: package, value: asset) in _licenses.entries) {
      final text = await rootBundle.loadString(asset);
      yield LicenseEntryWithLineBreaks([package], text);
    }
  });
}
