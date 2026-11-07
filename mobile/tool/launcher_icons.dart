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

int _outsideSafeCircle(img.Image icon) {
  final radius = _safeDiameter * icon.width / 2;
  final limit = radius * radius;
  var outside = 0;
  for (final pixel in icon) {
    if (pixel.a < 16) {
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
