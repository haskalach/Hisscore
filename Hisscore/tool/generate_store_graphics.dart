// Generates the Play Store feature graphic from code, so it can be
// regenerated rather than re-edited by hand.
// Run with: dart run tool/generate_store_graphics.dart
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

// Retro palette (mirrors lib/ui/theme.dart RetroColors).
final _screenBg = img.ColorRgba8(0x03, 0x14, 0x0A, 255);
final _grid = img.ColorRgba8(0x0C, 0x2A, 0x16, 255);
final _phosphor = img.ColorRgba8(0x7C, 0xFF, 0x6B, 255);
final _phosphorHot = img.ColorRgba8(0xD4, 0xFF, 0x9A, 255);
final _snakeTail = img.ColorRgba8(0x1A, 0x60, 0x30, 255);
final _apple = img.ColorRgba8(0xFF, 0x5A, 0x6A, 255);
final _amber = img.ColorRgba8(0xFF, 0xB0, 0x00, 255);
final _starGold = img.ColorRgba8(0xFF, 0xD7, 0x00, 255);
final _shieldCyan = img.ColorRgba8(0x00, 0xE5, 0xFF, 255);
final _magnetPink = img.ColorRgba8(0xFF, 0x6E, 0xC7, 255);

void main() {
  Directory('../store').createSync(recursive: true);
  final graphic = _featureGraphic();
  File('../store/feature-graphic.png').writeAsBytesSync(img.encodePng(graphic));
  stdout.writeln('Wrote store/feature-graphic.png (1024x500)');

  // Play wants the listing icon at 512x512; the app icon is 1024.
  final source = img.decodePng(File('assets/icon/icon.png').readAsBytesSync());
  if (source == null) {
    stderr.writeln('assets/icon/icon.png missing — run generate_icon.dart');
    exitCode = 1;
    return;
  }
  final listingIcon = img.copyResize(
    source,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.average,
  );
  File(
    '../store/play-icon-512.png',
  ).writeAsBytesSync(img.encodePng(listingIcon));
  stdout.writeln('Wrote store/play-icon-512.png (512x512)');
}

/// Play Store feature graphic: 1024x500, no transparency. Some store
/// layouts crop the edges and overlay the app name, so the art carries
/// it and nothing important sits near a border.
img.Image _featureGraphic() {
  const width = 1024;
  const height = 500;
  const cell = 25.0;

  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: _screenBg);

  // CRT grid.
  for (var x = cell; x < width; x += cell) {
    img.drawLine(
      image,
      x1: x.round(),
      y1: 0,
      x2: x.round(),
      y2: height,
      color: _grid,
    );
  }
  for (var y = cell; y < height; y += cell) {
    img.drawLine(
      image,
      x1: 0,
      y1: y.round(),
      x2: width,
      y2: y.round(),
      color: _grid,
    );
  }

  // A long snake sweeping the full width, so the banner reads as the
  // game rather than a logo on a background.
  final body = <Point<int>>[
    for (var i = 0; i < 9; i++) Point(3, 15 - i),
    for (var i = 1; i < 10; i++) Point(3 + i, 7),
    for (var i = 1; i < 7; i++) Point(12, 7 + i),
    for (var i = 1; i < 9; i++) Point(12 + i, 13),
    for (var i = 1; i < 7; i++) Point(20, 13 - i),
    for (var i = 1; i < 11; i++) Point(20 + i, 7),
    for (var i = 1; i < 6; i++) Point(30, 7 + i),
    for (var i = 1; i < 5; i++) Point(30 + i, 12),
  ];

  Point<double> centreOf(Point<int> p) =>
      Point((p.x * cell) + cell / 2, (p.y * cell) + cell / 2);

  img.Color bodyColour(double t) => img.ColorRgba8(
    (_snakeTail.r + (_phosphor.r - _snakeTail.r) * t).round(),
    (_snakeTail.g + (_phosphor.g - _snakeTail.g) * t).round(),
    (_snakeTail.b + (_phosphor.b - _snakeTail.b) * t).round(),
    255,
  );

  // Connectors first, so the body reads as one continuous snake
  // instead of a dashed line.
  for (var i = 0; i < body.length - 1; i++) {
    final t = i / (body.length - 1);
    final a = centreOf(body[i]);
    final b = centreOf(body[i + 1]);
    final halfWidth = cell * (0.22 + 0.12 * t);
    img.fillRect(
      image,
      x1: (min(a.x, b.x) - halfWidth).round(),
      y1: (min(a.y, b.y) - halfWidth).round(),
      x2: (max(a.x, b.x) + halfWidth).round(),
      y2: (max(a.y, b.y) + halfWidth).round(),
      color: bodyColour(t),
      radius: 3,
    );
  }

  // Then the segments themselves, tapering toward the tail.
  for (var i = 0; i < body.length; i++) {
    final t = i / (body.length - 1);
    final isHead = i == body.length - 1;
    final centre = centreOf(body[i]);
    final half = cell * (0.26 + 0.14 * t);
    img.fillRect(
      image,
      x1: (centre.x - half).round(),
      y1: (centre.y - half).round(),
      x2: (centre.x + half).round(),
      y2: (centre.y + half).round(),
      color: isHead ? _phosphorHot : bodyColour(t),
      radius: 5,
    );
  }

  // Pickups scattered ahead of it, showing the variety on the board.
  final pickups = <(int, int, img.Color)>[
    (35, 12, _apple),
    (26, 16, _starGold),
    (16, 3, _shieldCyan),
    (7, 17, _magnetPink),
  ];
  for (final (x, y, colour) in pickups) {
    img.fillCircle(
      image,
      x: (x * cell + cell / 2).round(),
      y: (y * cell + cell / 2).round(),
      radius: (cell * 0.34).round(),
      color: colour,
    );
  }

  // Scanlines over everything, like the board.
  final scanline = img.ColorRgba8(0, 0, 0, 0x22);
  for (var y = 0; y < height; y += 3) {
    img.drawLine(image, x1: 0, y1: y, x2: width, y2: y, color: scanline);
  }

  return image;
}
