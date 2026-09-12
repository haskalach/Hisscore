import 'dart:math';
import 'dart:ui';

/// A single particle with position, velocity, lifetime, and appearance.
class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.maxLife,
    this.size = 3.0,
    this.gravity = 180.0,
  }) : life = maxLife;

  double x;
  double y;
  double vx;
  double vy;
  Color color;
  double size;
  double life;
  final double maxLife;
  final double gravity;

  /// Fraction of life remaining (1.0 → 0.0).
  double get lifeFraction => (life / maxLife).clamp(0.0, 1.0);

  bool get isDead => life <= 0;
}

/// Lightweight particle system for eat, death, and trail effects.
///
/// Call [update] each frame with the elapsed delta, then [paint] in the
/// [CustomPainter]. Coordinates are in canvas-pixel space.
class ParticleSystem {
  ParticleSystem({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<Particle> _particles = [];
  DateTime _lastUpdate = DateTime.now();

  bool get hasParticles => _particles.isNotEmpty;
  int get count => _particles.length;

  // ─── Emitters ─────────────────────────────────────────

  /// Burst of particles when the snake eats food.
  void emitEat(double cx, double cy, Color color, {int count = 12}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 60 + _random.nextDouble() * 140;
      _particles.add(
        Particle(
          x: cx,
          y: cy,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          color: color,
          maxLife: 0.35 + _random.nextDouble() * 0.25,
          size: 2.0 + _random.nextDouble() * 2.5,
          gravity: 80,
        ),
      );
    }
  }

  /// Big explosion on death / game-over.
  void emitDeath(double cx, double cy, Color color, {int count = 30}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 80 + _random.nextDouble() * 200;
      _particles.add(
        Particle(
          x: cx,
          y: cy,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          color: Color.lerp(
            color,
            const Color(0xFFFFB000),
            _random.nextDouble() * 0.5,
          )!,
          maxLife: 0.5 + _random.nextDouble() * 0.4,
          size: 2.5 + _random.nextDouble() * 3.5,
          gravity: 120,
        ),
      );
    }
  }

  /// Faint shimmer behind the snake head each frame.
  void emitTrail(double cx, double cy, Color color) {
    if (_random.nextDouble() > 0.4) return; // Only 40% of frames
    _particles.add(
      Particle(
        x: cx + (_random.nextDouble() - 0.5) * 4,
        y: cy + (_random.nextDouble() - 0.5) * 4,
        vx: (_random.nextDouble() - 0.5) * 20,
        vy: (_random.nextDouble() - 0.5) * 20,
        color: color,
        maxLife: 0.25 + _random.nextDouble() * 0.15,
        size: 1.5 + _random.nextDouble(),
        gravity: 0,
      ),
    );
  }

  /// Combo text sparkle at a point.
  void emitComboSparkle(double cx, double cy, {int count = 6}) {
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 40 + _random.nextDouble() * 80;
      _particles.add(
        Particle(
          x: cx,
          y: cy,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          color: const Color(0xFFFFD700),
          maxLife: 0.3 + _random.nextDouble() * 0.2,
          size: 1.5 + _random.nextDouble() * 1.5,
          gravity: 0,
        ),
      );
    }
  }

  // ─── Simulation ───────────────────────────────────────

  /// Update all live particles. Call once per paint frame.
  void update() {
    final now = DateTime.now();
    final dt = now.difference(_lastUpdate).inMicroseconds / 1000000.0;
    _lastUpdate = now;

    // Cap dt to avoid huge jumps after pauses.
    final clampedDt = dt.clamp(0.0, 0.05);

    for (final p in _particles) {
      p.x += p.vx * clampedDt;
      p.y += p.vy * clampedDt;
      p.vy += p.gravity * clampedDt;
      p.life -= clampedDt;
    }
    _particles.removeWhere((p) => p.isDead);
  }

  /// Render all particles onto [canvas].
  void paint(Canvas canvas) {
    for (final p in _particles) {
      final opacity = p.lifeFraction;
      final paint = Paint()..color = p.color.withValues(alpha: opacity * 0.85);
      canvas.drawCircle(
        Offset(p.x, p.y),
        p.size * (0.4 + opacity * 0.6),
        paint,
      );
    }
  }

  /// Remove all particles.
  void clear() => _particles.clear();
}
