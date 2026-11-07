import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _licenses = {
  'BIZ UDPGothic': 'assets/licenses/BIZUDPGothic-OFL.txt',
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
