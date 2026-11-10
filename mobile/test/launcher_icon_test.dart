import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('元の画像はリポジトリにあり、アプリには入らない', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(
      r'^  assets:\n(?:    - .+\n)+',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(assets, isNotNull);
    expect(assets!.group(0)!, isNot(contains('app_icon')));

    final file = File('assets/app_icon/icon_1024.png');
    final bytes = file.readAsBytesSync();
    expect(_pngColorType(bytes), 2);
    expect(_hasTransparencyChunk(bytes), isFalse);
    final icon = img.decodePng(bytes)!;
    expect(icon.width, 1024);
    expect(icon.height, 1024);
    _expectCream(icon.getPixel(0, 0));
  });

  test('iOS のアイコンは、並んでいるすべての大きさで、透明な部分がない', () {
    final contents = jsonDecode(
      File('ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')
          .readAsStringSync(),
    );
    final images = contents['images'] as List<dynamic>;
    expect(images, isNotEmpty);

    for (final image in images) {
      final entry = image as Map<String, dynamic>;
      final filename = entry['filename'] as String;
      final pixels = _pixelSize(
        entry['size'] as String,
        entry['scale'] as String,
      );
      final file = File(
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/$filename',
      );
      final bytes = file.readAsBytesSync();
      expect(_pngColorType(bytes), 2, reason: filename);
      expect(_hasTransparencyChunk(bytes), isFalse, reason: filename);
      final icon = img.decodePng(bytes)!;
      expect(icon.width, pixels, reason: filename);
      expect(icon.height, pixels, reason: filename);
      // 割り切れない大きさでは、縮小でクリーム色が 1 階調ずれる。
      _expectNearCream(icon.getPixel(0, 0));
      if (pixels == 1024) {
        expect(_hasDrawing(icon), isTrue, reason: filename);
      }
    }
  });

  test('Android のアダプティブアイコンは背景がクリーム色で、丸く切り抜いても絵が収まる', () {
    final colors = File('android/app/src/main/res/values/colors.xml')
        .readAsStringSync();
    expect(colors, contains('name="ic_launcher_background"'));
    expect(colors.toUpperCase(), contains('#FFF5D3'));

    final xml = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(xml, contains('@color/ic_launcher_background'));
    expect(xml, contains('@drawable/ic_launcher_foreground'));
    expect(xml, contains('android:inset="0%"'));

    final foregrounds = Directory('android/app/src/main/res')
        .listSync()
        .whereType<Directory>()
        .map((dir) => File('${dir.path}/ic_launcher_foreground.png'))
        .where((file) => file.existsSync())
        .toList();
    expect(foregrounds, isNotEmpty);

    for (final file in foregrounds) {
      final icon = img.decodePng(file.readAsBytesSync())!;
      expect(icon.getPixel(0, 0).a.toInt(), 0, reason: file.path);
      expect(_outsideSafeCircle(icon), 0, reason: file.path);
      expect(_hasDrawing(icon), isTrue, reason: file.path);
    }
  });

  test('古い Android 向けのアイコンもある', () {
    const sizes = {
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };
    for (final entry in sizes.entries) {
      final file = File(
        'android/app/src/main/res/${entry.key}/ic_launcher.png',
      );
      final bytes = file.readAsBytesSync();
      expect(_pngColorType(bytes), 2, reason: entry.key);
      expect(_hasTransparencyChunk(bytes), isFalse, reason: entry.key);
      final icon = img.decodePng(bytes)!;
      expect(icon.width, entry.value, reason: entry.key);
      expect(icon.height, entry.value, reason: entry.key);
      // 割り切れない大きさでは、縮小でクリーム色が 1 階調ずれる。
      _expectNearCream(icon.getPixel(0, 0));
    }
  });

  test('Web のファビコンとアイコンは Flutter の最初のものではなく、元の画像から作ってある', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<title>かぞくAI</title>'));

    final manifest = jsonDecode(
      File('web/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest['name'], 'かぞくAI');
    expect(manifest['short_name'], 'かぞくAI');
    expect(manifest['background_color'], '#F5F5F5');
    expect(manifest['theme_color'], '#F5F5F5');
    final sources = (manifest['icons'] as List<dynamic>)
        .map((icon) => (icon as Map<String, dynamic>)['src'])
        .toList();
    expect(sources, contains('icons/Icon-192.png'));
    expect(sources, contains('icons/Icon-512.png'));
    expect(sources, contains('icons/Icon-maskable-192.png'));
    expect(sources, contains('icons/Icon-maskable-512.png'));

    final source = img.decodePng(
      File('assets/app_icon/icon_1024.png').readAsBytesSync(),
    )!;
    const regular = {
      'web/favicon.png': 48,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
    };
    for (final entry in regular.entries) {
      final icon = img.decodePng(File(entry.key).readAsBytesSync())!;
      expect(icon.width, entry.value, reason: entry.key);
      expect(icon.height, entry.value, reason: entry.key);
      final made = img.copyResize(
        source,
        width: entry.value,
        height: entry.value,
        interpolation: img.Interpolation.average,
      );
      expect(_differentRgb(icon, made), 0, reason: entry.key);
    }

    // maskable は Android が丸や角丸に切り抜く。円の外のクリーム色は欠けてよく、
    // 絵だけが安全な円の中に残る。
    for (final path in [
      'web/icons/Icon-maskable-192.png',
      'web/icons/Icon-maskable-512.png',
    ]) {
      final icon = img.decodePng(File(path).readAsBytesSync())!;
      _expectNearCream(icon.getPixel(0, 0));
      expect(_hasDrawing(icon), isTrue, reason: path);
      expect(_drawingOutsideSafeCircle(icon), 0, reason: path);
    }
  });
}

int _pixelSize(String size, String scale) {
  final points = double.parse(size.split('x').first);
  final factor = int.parse(scale.replaceAll('x', ''));
  return (points * factor).round();
}

/// 108 dp の層の真ん中、直径 66 dp の円の外にある絵の画素の数。
int _outsideSafeCircle(img.Image icon) {
  return _outsideSafeCircleWhere(icon, (pixel) => pixel.a >= 16);
}

/// 背景のクリーム色を除いた、絵の画素だけを数える。
int _drawingOutsideSafeCircle(img.Image icon) {
  return _outsideSafeCircleWhere(icon, (pixel) {
    if (pixel.a < 16) {
      return false;
    }
    return !_isNearCream(pixel);
  });
}

int _outsideSafeCircleWhere(img.Image icon, bool Function(img.Pixel) counts) {
  final radius = 33 / 108 * icon.width;
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

int _differentRgb(img.Image actual, img.Image expected) {
  var different = 0;
  for (final pixel in actual) {
    final other = expected.getPixel(pixel.x, pixel.y);
    if (pixel.r != other.r || pixel.g != other.g || pixel.b != other.b) {
      different++;
    }
  }
  return different;
}

bool _hasDrawing(img.Image icon) {
  for (final pixel in icon) {
    final opaque = pixel.a >= 16;
    final cream = pixel.r == 255 && pixel.g == 245 && pixel.b == 211;
    if (opaque && !cream) {
      return true;
    }
  }
  return false;
}

void _expectCream(img.Pixel pixel) {
  expect(pixel.r.toInt(), 255);
  expect(pixel.g.toInt(), 245);
  expect(pixel.b.toInt(), 211);
}

bool _isNearCream(img.Pixel pixel) {
  return (pixel.r.toInt() - 255).abs() <= 1 &&
      (pixel.g.toInt() - 245).abs() <= 1 &&
      (pixel.b.toInt() - 211).abs() <= 1;
}

void _expectNearCream(img.Pixel pixel) {
  expect(_isNearCream(pixel), isTrue);
}

int _pngColorType(List<int> bytes) {
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'IHDR');
  return bytes[25];
}

bool _hasTransparencyChunk(List<int> bytes) {
  var offset = 8;
  while (offset + 8 <= bytes.length) {
    final length = _uint32(bytes, offset);
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    if (type == 'tRNS') {
      return true;
    }
    if (type == 'IEND') {
      return false;
    }
    offset += 12 + length;
  }
  return false;
}

int _uint32(List<int> bytes, int offset) {
  return bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];
}
