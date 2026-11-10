import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _creamR = 255;
const _creamG = 245;
const _creamB = 211;
const _canvas = 1024;

/// 108 dp の層の真ん中、直径 66 dp の円。丸く切り抜いても絵が欠けない範囲。
const _safeDiameter = 66 / 108;

const _foregroundSizes = [108, 162, 216, 324, 432];

// flutter_launcher_icons は favicon を 16×16 で書く。タブは 16 論理画素を
// 高 DPI では 2 倍以上で描くので、元画像から 48×48 を作り直す。
const _faviconSize = 48;

void main() {
  final source = img.decodePng(
    File('assets/app_icon/icon_1024.png').readAsBytesSync(),
  );
  if (source == null || source.width != _canvas || source.height != _canvas) {
    stderr.writeln(
      'assets/app_icon/icon_1024.png は 1024×1024 の PNG である必要があります',
    );
    exit(1);
  }

  final foreground = _foregroundInSafeCircle(source);
  File('assets/app_icon/android_foreground.png')
      .writeAsBytesSync(img.encodePng(foreground));

  // flutter_launcher_icons は、プロジェクトが並べている大きさより多い iOS の
  // アイコンを足し、関係ないビルド設定も書き換える。先に控えて、あとで戻す。
  final contentsFile = File(
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
  );
  final contents = contentsFile.readAsStringSync();
  final manifestFile = File('web/manifest.json');
  final manifestText = manifestFile.readAsStringSync();
  final listed = (jsonDecode(contents)['images'] as List<dynamic>)
      .map((image) => (image as Map<String, dynamic>)['filename'] as String)
      .toSet();

  final result = Process.runSync('dart', ['run', 'flutter_launcher_icons']);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }

  contentsFile.writeAsStringSync(contents);
  final iconDir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  for (final entity in iconDir.listSync()) {
    if (entity is! File) {
      continue;
    }
    final name = entity.uri.pathSegments.last;
    if (name != 'Contents.json' && !listed.contains(name)) {
      entity.deleteSync();
    }
  }

  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  project.writeAsStringSync(
    project.readAsStringSync().replaceAll(
      'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;',
      'ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;',
    ),
  );

  _restoreWebManifest(manifestFile, manifestText);
  _writeFavicon(source);
  _fitMaskableIcons();
}

// manifest の名前と色は、アイコンを作り直しても変えない。
void _restoreWebManifest(File manifestFile, String originalText) {
  final original = jsonDecode(originalText) as Map<String, dynamic>;
  final rewritten =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  rewritten['name'] = original['name'];
  rewritten['short_name'] = original['short_name'];
  rewritten['background_color'] = original['background_color'];
  rewritten['theme_color'] = original['theme_color'];
  if (_jsonEquals(rewritten, original)) {
    manifestFile.writeAsStringSync(originalText);
    return;
  }
  manifestFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('    ').convert(rewritten)}\n',
  );
}

// 生成が書いた 16×16 を、元の 1024×1024 から縮小した画像で置き換える。
void _writeFavicon(img.Image source) {
  File('web/favicon.png').writeAsBytesSync(
    img.encodePng(
      img.copyResize(
        source,
        width: _faviconSize,
        height: _faviconSize,
        interpolation: img.Interpolation.average,
      ),
    ),
  );
}

// 丸や角丸に切り抜いても絵が欠けないようにする。収まらないときは、Android の
// アダプティブアイコンと同じ余白のある前景を、クリーム色の上に置く。
void _fitMaskableIcons() {
  const files = {
    'web/icons/Icon-maskable-192.png': 192,
    'web/icons/Icon-maskable-512.png': 512,
  };
  final needsMargin = files.keys.any((path) {
    final icon = img.decodePng(File(path).readAsBytesSync());
    return icon == null || _drawingOutsideSafeCircle(icon) != 0;
  });
  if (!needsMargin) {
    return;
  }

  final foreground = img.decodePng(
    File('assets/app_icon/android_foreground.png').readAsBytesSync(),
  );
  if (foreground == null) {
    stderr.writeln('assets/app_icon/android_foreground.png を読めません');
    exit(1);
  }
  for (final entry in files.entries) {
    final canvas = img.Image(
      width: entry.value,
      height: entry.value,
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorRgba8(_creamR, _creamG, _creamB, 255));
    img.compositeImage(
      canvas,
      img.copyResize(
        foreground,
        width: entry.value,
        height: entry.value,
        interpolation: img.Interpolation.average,
      ),
    );
    final file = File(entry.key);
    file.writeAsBytesSync(img.encodePng(canvas));
    final written = img.decodePng(file.readAsBytesSync());
    if (written == null || _drawingOutsideSafeCircle(written) != 0) {
      stderr.writeln('${entry.key} の絵が安全な範囲に収まりません');
      exit(1);
    }
  }
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

int _drawingOutsideSafeCircle(img.Image icon) {
  return _outsideSafeCircleWhere(
    icon,
    (pixel) => pixel.a >= 16 && !_isNearCream(pixel),
  );
}

int _outsideSafeCircle(img.Image icon) {
  return _outsideSafeCircleWhere(icon, (pixel) => pixel.a >= 16);
}

int _outsideSafeCircleWhere(img.Image icon, bool Function(img.Pixel) counts) {
  final radius = _safeDiameter * icon.width / 2;
  final limit = radius * radius;
  var outside = 0;
  for (final pixel in icon) {
    if (!counts(pixel)) {
      continue;
    }
    final dx = (pixel.x + 0.5) - icon.width / 2;
    final dy = (pixel.y + 0.5) - icon.height / 2;
    if (dx * dx + dy * dy > limit) {
      outside++;
    }
  }
  return outside;
}

bool _isNearCream(img.Pixel pixel) {
  return (pixel.r.toInt() - _creamR).abs() <= 1 &&
      (pixel.g.toInt() - _creamG).abs() <= 1 &&
      (pixel.b.toInt() - _creamB).abs() <= 1;
}

img.Image _foregroundInSafeCircle(img.Image source) {
  final keyed = _withoutCream(source);
  final center = _drawingCenter(keyed);
  final farthest = _farthest(keyed, center);
  var scale = (_safeDiameter * _canvas / 2) / farthest;

  for (var attempt = 0; attempt < 40; attempt++) {
    final placed = _place(keyed, center, scale);
    final fitsMaster = _outsideSafeCircle(placed) == 0;
    final fitsSizes = _foregroundSizes.every((size) {
      final resized = img.copyResize(
        placed,
        width: size,
        height: size,
        interpolation: img.Interpolation.average,
      );
      return _outsideSafeCircle(resized) == 0;
    });
    if (fitsMaster && fitsSizes) {
      return placed;
    }
    scale *= 0.99;
  }

  throw StateError('絵を安全な範囲に収められません');
}

img.Image _withoutCream(img.Image source) {
  final image = source.convert(numChannels: 4);
  for (final pixel in image) {
    final cream =
        pixel.r == _creamR && pixel.g == _creamG && pixel.b == _creamB;
    pixel.a = cream ? 0 : 255;
  }
  return image;
}

(double, double) _drawingCenter(img.Image image) {
  var minX = image.width;
  var minY = image.height;
  var maxX = 0;
  var maxY = 0;
  for (final pixel in image) {
    if (pixel.a == 0) {
      continue;
    }
    minX = math.min(minX, pixel.x);
    minY = math.min(minY, pixel.y);
    maxX = math.max(maxX, pixel.x);
    maxY = math.max(maxY, pixel.y);
  }
  return ((minX + maxX + 1) / 2, (minY + maxY + 1) / 2);
}

double _farthest(img.Image image, (double, double) center) {
  var farthest = 0.0;
  for (final pixel in image) {
    if (pixel.a == 0) {
      continue;
    }
    final dx = (pixel.x + 0.5) - center.$1;
    final dy = (pixel.y + 0.5) - center.$2;
    farthest = math.max(farthest, math.sqrt(dx * dx + dy * dy));
  }
  return farthest;
}

img.Image _place(img.Image keyed, (double, double) center, double scale) {
  final scaledSize = math.max(1, (_canvas * scale).round());
  final scaled = img.copyResize(
    keyed,
    width: scaledSize,
    height: scaledSize,
    interpolation: img.Interpolation.average,
  );
  final actual = scaledSize / _canvas;
  final out = img.Image(width: _canvas, height: _canvas, numChannels: 4);
  img.fill(out, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(
    out,
    scaled,
    dstX: (_canvas / 2 - center.$1 * actual).round(),
    dstY: (_canvas / 2 - center.$2 * actual).round(),
  );
  return out;
}
