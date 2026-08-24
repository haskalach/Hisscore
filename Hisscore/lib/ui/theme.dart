import 'package:flutter/material.dart';

/// Phosphor CRT palette for the Hisscore cabinet.
abstract final class RetroColors {
  static const voidBg = Color(0xFF07080A);
  static const cabinet = Color(0xFF1A1410);
  static const cabinetRim = Color(0xFF3A2A1C);
  static const metal = Color(0xFF8A8478);
  static const screen = Color(0xFF03140A);
  static const grid = Color(0xFF0C2A16);
  static const phosphor = Color(0xFF7CFF6B);
  static const phosphorDim = Color(0xFF2E8A3A);
  static const phosphorHot = Color(0xFFD4FF9A);
  static const amber = Color(0xFFFFB000);
  static const cherry = Color(0xFFFF3B3B);
  static const food = Color(0xFFFF5A6A);
}

abstract final class RetroText {
  static TextStyle pixel({
    double size = 12,
    Color color = RetroColors.phosphor,
    double letterSpacing = 1,
    double height = 1.3,
  }) {
    return TextStyle(
      fontFamily: 'PressStart2P',
      fontSize: size,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}
