// Generates the app icon and adaptive-icon foreground/splash mark from
// code, so the app has real branded art instead of the stock Flutter
// logo. Run with: dart run tool/generate_icon.dart
//
// Design: a coiled green "phosphor" ring (the snake) with a mouth gap,
// a small eye, and a red apple just outside the gap — readable at
// launcher-icon sizes, using the game's own retro CRT palette.
import 'dart:io';

import 'package:image/image.dart' as img;

// Retro palette (mirrors lib/ui/theme.dart RetroColors).
final _screenBg = img.ColorRgba8(0x03, 0x14, 0x0A, 255); // RetroColors.screen
final _phosphor = img.ColorRgba8(0x7C, 0xFF, 0x6B, 255); // RetroColors.phosphor
final _phosphorHot = img.ColorRgba8(0xD4, 0xFF, 0x9A, 255);
final _apple = img.ColorRgba8(0xFF, 0x5A, 0x6A, 255); // RetroColors.food
final _eyeDark = img.ColorRgba8(0x03, 0x14, 0x0A, 255);

void main() {
  Directory('assets/icon').createSync(recursive: true);

  // Full icon: opaque background (required for iOS/store listing).
  File('assets/icon/icon.png').writeAsBytesSync(
    img.encodePng(_drawMark(background: _screenBg, scale: 1.0)),
  );

  // Adaptive-icon foreground / splash mark: transparent background,
  // shrunk to sit inside Android's adaptive-icon safe zone.
  File('assets/icon/icon_foreground.png').writeAsBytesSync(
    img.encodePng(_drawMark(background: null, scale: 0.66)),
  );

  stdout.writeln('Wrote assets/icon/icon.png and icon_foreground.png');
}

img.Image _drawMark({required img.Color? background, required double scale}) {
  const size = 1024;
  final image = img.Image(width: size, height: size, numChannels: 4);
  if (background != null) {
    img.fill(image, color: background);
  }

  final cx = size / 2;
  final cy = size / 2;
  final outerR = 360.0 * scale;
  final innerR = 235.0 * scale;
  final gapHalfW = 65.0 * scale;

  // Ring body: outer disc in phosphor green, then punch the inner hole
  // with the background color (or fully transparent for the
  // foreground variant) to leave a thick coiled ring.
  img.fillCircle(image, x: cx.round(), y: cy.round(), radius: outerR.round(), color: _phosphor);
  // BlendMode.direct overwrites pixels outright (including alpha) so a
  // fully-transparent punch color actually erases pixels instead of
  // alpha-blending as a no-op on top of the opaque ring.
  img.fillCircle(
    image,
    x: cx.round(),
    y: cy.round(),
    radius: innerR.round(),
    color: background ?? img.ColorRgba8(0, 0, 0, 0),
    blend: img.BlendMode.direct,
  );

  // Mouth gap: cut a notch out of the right side of the ring so it
  // reads as a coiled snake, not a plain donut.
  img.fillPolygon(
    image,
    vertices: [
      img.Point(cx + innerR - 60 * scale, cy - gapHalfW),
      img.Point(cx + outerR + 60 * scale, cy - gapHalfW),
      img.Point(cx + outerR + 60 * scale, cy + gapHalfW),
      img.Point(cx + innerR - 60 * scale, cy + gapHalfW),
    ],
    color: background ?? img.ColorRgba8(0, 0, 0, 0),
    blend: img.BlendMode.direct,
  );

  // Eye, on the upper lip of the mouth gap.
  final midR = (outerR + innerR) / 2;
  img.fillCircle(
    image,
    x: (cx + midR).round(),
    y: (cy - gapHalfW * 0.9).round(),
    radius: (28 * scale).round(),
    color: _eyeDark,
  );
  img.fillCircle(
    image,
    x: (cx + midR).round(),
    y: (cy - gapHalfW * 0.9).round(),
    radius: (12 * scale).round(),
    color: _phosphorHot,
  );

  // Apple, just outside the open mouth.
  img.fillCircle(
    image,
    x: (cx + outerR + 60 * scale).round(),
    y: cy.round(),
    radius: (42 * scale).round(),
    color: _apple,
  );

  return image;
}
