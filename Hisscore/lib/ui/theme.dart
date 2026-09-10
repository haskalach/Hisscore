import 'package:flutter/material.dart';

/// Phosphor CRT palette for the Hisscore cabinet.
abstract final class RetroColors {
  // ─── Background & cabinet ──────────────────────────
  static const voidBg = Color(0xFF07080A);
  static const cabinet = Color(0xFF1A1410);
  static const cabinetRim = Color(0xFF3A2A1C);
  static const cabinetHighlight = Color(0xFF5A4A38);
  static const metal = Color(0xFF8A8478);
  static const rivet = Color(0xFF6A6054);

  // ─── CRT screen ────────────────────────────────────
  static const screen = Color(0xFF03140A);
  static const grid = Color(0xFF0C2A16);
  static const scanline = Color(0x22000000);

  // ─── Snake phosphor ────────────────────────────────
  static const phosphor = Color(0xFF7CFF6B);
  static const phosphorDim = Color(0xFF2E8A3A);
  static const phosphorHot = Color(0xFFD4FF9A);
  static const phosphorGlow = Color(0x3300FF66);
  static const snakeTail = Color(0xFF1A6030);

  // ─── UI accents ────────────────────────────────────
  static const amber = Color(0xFFFFB000);
  static const amberDim = Color(0xFF8A6000);
  static const cherry = Color(0xFFFF3B3B);
  static const food = Color(0xFFFF5A6A);

  // ─── Power-up colors ───────────────────────────────
  static const starGold = Color(0xFFFFD700);
  static const shieldCyan = Color(0xFF00E5FF);
  static const speedYellow = Color(0xFFFFEA00);
  static const shrinkPurple = Color(0xFFCE93D8);
  static const magnetPink = Color(0xFFFF6EC7);

  // ─── Gameplay ──────────────────────────────────────
  static const combo = Color(0xFFFFD740);
  static const obstacle = Color(0xFF3A3028);
  static const obstacleRim = Color(0xFF5A4A3C);
  static const levelFlash = Color(0xAAFFFFFF);

  // ─── Mode selector ────────────────────────────────
  static const modeActive = Color(0xFFFFB000);
  static const modeInactive = Color(0xFF4A4030);
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
