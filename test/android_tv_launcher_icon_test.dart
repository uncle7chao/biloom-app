import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

String _androidAttribute(String source, String element, String attribute) {
  final elementTag = RegExp('<$element\\b[^>]*>').firstMatch(source)!.group(0)!;
  return RegExp(
    'android:$attribute="([^"]+)"',
  ).firstMatch(elementTag)!.group(1)!;
}

double _androidDoubleAttribute(
  String source,
  String element,
  String attribute,
) {
  return double.parse(_androidAttribute(source, element, attribute));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TV launcher icons meet density-specific minimum sizes', () async {
    const expectedSizes = {
      'mdpi': 80,
      'hdpi': 120,
      'xhdpi': 160,
      'xxhdpi': 240,
      'xxxhdpi': 320,
    };

    for (final MapEntry(key: density, value: size) in expectedSizes.entries) {
      final file = File(
        'android/app/src/main/res/'
        'mipmap-television-$density/ic_launcher.webp',
      );
      expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');

      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      expect(
        (frame.image.width, frame.image.height),
        (size, size),
        reason: file.path,
      );
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('TV adaptive launcher icon stays centered in the safe zone', () {
    final adaptiveIcon = File(
      'android/app/src/main/res/'
      'mipmap-television-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(
      _androidAttribute(adaptiveIcon, 'foreground', 'drawable'),
      '@drawable/ic_launcher_foreground_tv',
    );
    expect(
      _androidAttribute(adaptiveIcon, 'background', 'drawable'),
      '@color/ic_launcher_background',
    );

    final vector = File(
      'android/app/src/main/res/drawable/'
      'ic_launcher_foreground_tv.xml',
    ).readAsStringSync();
    final scaleX = _androidDoubleAttribute(vector, 'group', 'scaleX');
    final scaleY = _androidDoubleAttribute(vector, 'group', 'scaleY');
    final translateX = _androidDoubleAttribute(vector, 'group', 'translateX');
    final translateY = _androidDoubleAttribute(vector, 'group', 'translateY');
    final viewportWidth = _androidDoubleAttribute(
      vector,
      'vector',
      'viewportWidth',
    );
    final viewportHeight = _androidDoubleAttribute(
      vector,
      'vector',
      'viewportHeight',
    );

    // The generator fits the whole SVG viewBox into the adaptive viewport, so
    // the viewBox is exactly the rectangle that gets centred. Read it from the
    // source instead of hardcoding bounds: a hardcoded rectangle silently went
    // stale when the brand SVG was redrawn (the old constant described a much
    // smaller logo), and the test then reported an off-centre icon that was in
    // fact perfectly centred.
    final brandSvg = File(
      'assets_source/brand/biloom-mark.svg',
    ).readAsStringSync();
    final viewBox = RegExp(
      r'viewBox="([-\d.\s]+)"',
    ).firstMatch(brandSvg)!.group(1)!;
    final vb = viewBox
        .trim()
        .split(RegExp(r'\s+'))
        .map(double.parse)
        .toList();
    final logoBounds = ui.Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]);
    final transformedBounds = ui.Rect.fromLTRB(
      (logoBounds.left * scaleX + translateX) / viewportWidth * 108,
      (logoBounds.top * scaleY + translateY) / viewportHeight * 108,
      (logoBounds.right * scaleX + translateX) / viewportWidth * 108,
      (logoBounds.bottom * scaleY + translateY) / viewportHeight * 108,
    );
    const safeZone = ui.Rect.fromLTWH(18, 18, 72, 72);

    expect(transformedBounds.left, greaterThanOrEqualTo(safeZone.left));
    expect(transformedBounds.top, greaterThanOrEqualTo(safeZone.top));
    expect(transformedBounds.right, lessThanOrEqualTo(safeZone.right));
    expect(transformedBounds.bottom, lessThanOrEqualTo(safeZone.bottom));
    expect(transformedBounds.center.dx, closeTo(safeZone.center.dx, 0.05));
    expect(transformedBounds.center.dy, closeTo(safeZone.center.dy, 0.05));
  });
}
