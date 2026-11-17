import 'package:PiliPlus/plugin/pl_player/mini_player/layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('miniPlayerSize', () {
    test('uses the video aspect ratio', () {
      final size = miniPlayerSize(
        aspectRatio: 16 / 9,
        screen: const Size(400, 800),
      );
      expect(size.width, closeTo(240, 0.001));
      expect(size.height, closeTo(135, 0.001));
    });

    test('caps the width on large screens', () {
      final size = miniPlayerSize(
        aspectRatio: 16 / 9,
        screen: const Size(1000, 800),
      );
      expect(size.width, 400);
      expect(size.height, closeTo(225, 0.001));
    });

    test('caps the height of portrait videos', () {
      final size = miniPlayerSize(
        aspectRatio: 9 / 16,
        screen: const Size(400, 800),
      );
      expect(size.height, closeTo(360, 0.001));
      expect(size.width, closeTo(202.5, 0.001));
    });

    test('falls back to 16:9 for invalid ratios', () {
      final size = miniPlayerSize(
        aspectRatio: double.nan,
        screen: const Size(400, 800),
      );
      expect(size.width / size.height, closeTo(16 / 9, 0.001));
    });
  });

  group('clampMiniPlayerOffset', () {
    const screen = Size(400, 800);
    const padding = EdgeInsets.only(top: 44, bottom: 34);
    const size = Size(200, 120);

    test('keeps the window inside the screen and the safe area', () {
      expect(
        clampMiniPlayerOffset(
          offset: const Offset(-100, -100),
          screen: screen,
          padding: padding,
          size: size,
        ),
        const Offset(8, 52),
      );
      expect(
        clampMiniPlayerOffset(
          offset: const Offset(1000, 1000),
          screen: screen,
          padding: padding,
          size: size,
        ),
        const Offset(192, 638),
      );
    });

    test('default position stays inside the screen', () {
      final offset = defaultMiniPlayerOffset(
        screen: screen,
        padding: padding,
        size: size,
      );
      final clamped = clampMiniPlayerOffset(
        offset: offset,
        screen: screen,
        padding: padding,
        size: size,
      );
      expect(offset, clamped);
      expect(offset.dx + size.width, lessThanOrEqualTo(screen.width));
      expect(
        offset.dy + size.height + padding.bottom,
        lessThanOrEqualTo(screen.height),
      );
    });
  });
}
