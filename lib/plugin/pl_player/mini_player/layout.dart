import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Width ratio of the floating window relative to the screen width.
const double _widthRatio = 0.6;

/// Minimum and maximum size of the floating window.
const double _minWidth = 200;
const double _maxWidth = 400;

/// The window never takes more than this ratio of the screen height.
const double _maxHeightRatio = 0.45;

/// Space kept between the floating window and the screen edges.
const double _edgeGap = 8;

/// Default distance kept from the bottom edge so the window usually sits
/// above the bottom navigation bar.
const double _bottomBarGap = 72;

/// Computes the floating window size for a video with [aspectRatio]
/// (width / height) on a [screen] of the given size.
Size miniPlayerSize({
  required double aspectRatio,
  required Size screen,
}) {
  final ratio = aspectRatio.isFinite && aspectRatio > 0
      ? aspectRatio.clamp(0.5, 2.4)
      : 16 / 9;
  var width = (screen.width * _widthRatio).clamp(_minWidth, _maxWidth);
  var height = width / ratio;
  final maxHeight = screen.height * _maxHeightRatio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * ratio;
  }
  return Size(width, height);
}

/// Default position of the floating window, anchored to the bottom right.
Offset defaultMiniPlayerOffset({
  required Size screen,
  required EdgeInsets padding,
  required Size size,
}) {
  return clampMiniPlayerOffset(
    offset: Offset(
      screen.width - size.width - _edgeGap,
      screen.height - size.height - padding.bottom - _bottomBarGap,
    ),
    screen: screen,
    padding: padding,
    size: size,
  );
}

/// Keeps the floating window inside the usable screen area.
Offset clampMiniPlayerOffset({
  required Offset offset,
  required Size screen,
  required EdgeInsets padding,
  required Size size,
}) {
  const minX = _edgeGap;
  final maxX = math.max(minX, screen.width - size.width - _edgeGap);
  final minY = padding.top + _edgeGap;
  final maxY = math.max(
    minY,
    screen.height - padding.bottom - size.height - _edgeGap,
  );
  return Offset(
    offset.dx.clamp(minX, maxX),
    offset.dy.clamp(minY, maxY),
  );
}
