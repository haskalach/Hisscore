import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../game/daily_challenge.dart';
import '../game/food_types.dart';
import '../game/high_score_store.dart';
import '../game/notification_service.dart';
import '../game/review_prompter.dart';
import '../game/snake_engine.dart';
import '../game/sound_manager.dart';
import 'board.dart';
import 'controls.dart';
import 'particles.dart';
import 'screen_shake.dart';
import 'theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.highScoreStore, this.engineFactory});

  final HighScoreStore highScoreStore;
  final SnakeEngine Function()? engineFactory;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with TickerProviderStateMixin {
  late SnakeEngine engine;

  // Animation controllers.
  late AnimationController pulse;
  late AnimationController titleGlow;

  Timer? ticker;
  int highScore = 0;
  bool newHighScore = false;
  List<ScoreEntry> topScores = [];
  GameStats stats = GameStats();
  DateTime? startedAt;
  final focusNode = FocusNode();

  // Effects.
  final particleSystem = ParticleSystem();
  final shakeController = ScreenShakeController();

  // Mode selection.
  GameMode selectedMode = GameMode.classic;

  // Floating popup text (score gains, combos, level-ups).
  final List<_FloatingLabel> floatingLabels = [];
  final List<Timer> _labelTimers = [];
  int _labelSeq = 0;

  // Sound, reviews, reminders, daily challenge.
  final soundManager = SoundManager();
  final reviewPrompter = ReviewPrompter();
  final notificationService = NotificationService();
  DailyState dailyState = const DailyState();
  bool isDailyRun = false;

  int get _dailyDayNumber => DailyChallenge.dayNumber(DateTime.now());

  bool get _playedDailyToday => DailyChallenge.playedToday(
    lastPlayedKey: dailyState.lastPlayedKey,
    today: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    engine = widget.engineFactory?.call() ?? SnakeEngine(mode: selectedMode);
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    titleGlow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    unawaited(_loadHighScore());
    unawaited(soundManager.init());
    unawaited(notificationService.init());
  }

  Future<void> _loadHighScore() async {
    final value = await widget.highScoreStore.load();
    final scores = await widget.highScoreStore.loadTopScores();
    final loadedStats = await widget.highScoreStore.loadStats();
    final loadedDaily = await widget.highScoreStore.loadDailyState();
    if (!mounted) return;
    setState(() {
      highScore = value;
      topScores = scores;
      stats = loadedStats;
      dailyState = loadedDaily;
    });
  }

  /// Zen mode never ends and scores climb forever — it doesn't compete
  /// on the leaderboard or count toward the high score.
  bool get _countsForLeaderboard => engine.mode != GameMode.zen;

  Future<void> _persistHighScore() async {
    if (!_countsForLeaderboard) return;
    if (engine.score > highScore) {
      highScore = engine.score;
      newHighScore = true;
      await widget.highScoreStore.save(engine.score);
      unawaited(reviewPrompter.maybePrompt(gamesPlayed: stats.gamesPlayed));
    }
  }

  Future<void> _persistGameEnd() async {
    await _persistHighScore();
    if (_countsForLeaderboard) {
      await widget.highScoreStore.saveScoreEntry(
        ScoreEntry(
          score: engine.score,
          level: engine.level,
          mode: engine.mode.label,
        ),
      );
    }
    await widget.highScoreStore.updateStats(engine);
    final scores = await widget.highScoreStore.loadTopScores();
    final loadedStats = await widget.highScoreStore.loadStats();
    if (mounted) {
      setState(() {
        topScores = scores;
        stats = loadedStats;
      });
    }
    if (isDailyRun) {
      await _persistDailyResult();
    }
  }

  /// Updates the daily-challenge streak after a daily run ends, and — the
  /// first time a daily run is completed — asks for notification
  /// permission and schedules a "keep your streak" reminder for tomorrow.
  Future<void> _persistDailyResult() async {
    final today = DateTime.now();
    final alreadyPlayedToday = _playedDailyToday;
    final newStreak = DailyChallenge.nextStreak(
      lastPlayedKey: dailyState.lastPlayedKey,
      previousStreak: dailyState.currentStreak,
      today: today,
    );
    final newState = DailyState(
      lastPlayedKey: DailyChallenge.dateKey(today),
      lastScore: alreadyPlayedToday
          ? max(engine.score, dailyState.lastScore)
          : engine.score,
      currentStreak: newStreak,
      bestStreak: max(newStreak, dailyState.bestStreak),
    );
    await widget.highScoreStore.saveDailyState(newState);
    if (mounted) {
      setState(() => dailyState = newState);
    }
    if (!alreadyPlayedToday) {
      await notificationService.requestPermission();
      await notificationService.scheduleStreakReminder(streak: newStreak);
    }
  }

  void _armTicker() {
    ticker?.cancel();
    if (engine.phase != GamePhase.running) return;
    ticker = Timer.periodic(engine.tickInterval, (_) {
      if (!mounted) return;
      final scoreBefore = engine.score;
      setState(() {
        engine.tick();

        // Eat particles + floating popup.
        if (engine.justAte && engine.lastEatenFood != null) {
          final pos = engine.lastEatenFood!.position;
          _emitEatParticles(pos);
          unawaited(
            engine.lastEatenFood!.type == FoodType.apple
                ? soundManager.playEat()
                : soundManager.playBonus(),
          );
          final gained = engine.score - scoreBefore;
          if (gained > 0) {
            _spawnLabel('+$gained', pos, RetroColors.phosphorHot);
          }
          if (engine.comboCount > 1) {
            _spawnLabel(
              'COMBO x${engine.comboMultiplier.toStringAsFixed(1)}',
              GridPoint(pos.x, pos.y - 1),
              RetroColors.combo,
              big: true,
            );
          }
        }

        // Speed changed → re-arm ticker.
        if (engine.justAte) {
          unawaited(_persistHighScore());
          _armTicker();
        }

        // Level advanced banner.
        if (engine.levelJustAdvanced) {
          _spawnLabel(
            'LEVEL ${engine.level}!',
            GridPoint(engine.columns ~/ 2, engine.rows ~/ 2),
            RetroColors.amber,
            big: true,
          );
          shakeController.shake(intensity: 3);
          unawaited(soundManager.playLevelUp());
        }

        // Game over.
        if (engine.phase == GamePhase.gameOver) {
          ticker?.cancel();
          _emitDeathParticles();
          shakeController.shake(intensity: 8);
          unawaited(soundManager.playGameOver());
          unawaited(_persistGameEnd());
        }
      });
    });
  }

  /// Spawns a floating text popup at a grid position; it rises and
  /// fades, then removes itself.
  void _spawnLabel(
    String text,
    GridPoint gridPos,
    Color color, {
    bool big = false,
  }) {
    const boardSize = 380.0;
    final cellW = boardSize / engine.columns;
    final cellH = boardSize / engine.rows;
    final id = _labelSeq++;
    floatingLabels.add(
      _FloatingLabel(
        id: id,
        text: text,
        x: gridPos.x * cellW + cellW / 2,
        y: gridPos.y * cellH + cellH / 2,
        color: color,
        big: big,
      ),
    );
    late final Timer timer;
    timer = Timer(const Duration(milliseconds: 700), () {
      _labelTimers.remove(timer);
      if (!mounted) return;
      setState(() => floatingLabels.removeWhere((l) => l.id == id));
    });
    _labelTimers.add(timer);
  }

  void _emitEatParticles(GridPoint pos) {
    // We need to estimate the pixel position. The board fills the
    // available space — we can approximate using the engine grid.
    // The particles are drawn in the board's CustomPainter coordinate
    // space, so we convert grid → fraction → expected pixel.
    // The board painter uses: cellW = boardWidth / columns.
    // We don't know the exact board pixel size here, but the particle
    // system operates on approximate canvas coordinates passed through.
    // For simplicity, we'll compute a reasonable position using the
    // known grid dimensions and an assumed ~380×380 board area.
    const boardSize = 380.0;
    final cellW = boardSize / engine.columns;
    final cellH = boardSize / engine.rows;
    final cx = pos.x * cellW + cellW / 2;
    final cy = pos.y * cellH + cellH / 2;

    final color = switch (engine.lastEatenFood?.type) {
      FoodType.apple => RetroColors.food,
      FoodType.star => RetroColors.starGold,
      FoodType.shield => RetroColors.shieldCyan,
      FoodType.speedBurst => RetroColors.speedYellow,
      FoodType.shrink => RetroColors.shrinkPurple,
      FoodType.magnet => RetroColors.magnetPink,
      _ => RetroColors.phosphor,
    };
    particleSystem.emitEat(cx, cy, color);

    if (engine.comboCount > 1) {
      particleSystem.emitComboSparkle(cx, cy - 10);
    }
  }

  void _emitDeathParticles() {
    const boardSize = 380.0;
    final cellW = boardSize / engine.columns;
    final cellH = boardSize / engine.rows;
    final cx = engine.head.x * cellW + cellW / 2;
    final cy = engine.head.y * cellH + cellH / 2;
    particleSystem.emitDeath(cx, cy, RetroColors.cherry);
  }

  void _onPrimary() {
    setState(() {
      if (engine.phase == GamePhase.running) {
        final justStarted =
            startedAt != null &&
            DateTime.now().difference(startedAt!) <
                const Duration(milliseconds: 400);
        if (justStarted) return;
        engine.pause();
        ticker?.cancel();
        return;
      }
      newHighScore = false;
      if (engine.phase == GamePhase.gameOver ||
          engine.phase == GamePhase.ready) {
        // Apply selected mode.
        if (engine.mode != selectedMode) {
          engine =
              widget.engineFactory?.call() ?? SnakeEngine(mode: selectedMode);
        }
        engine.mode = selectedMode;
        isDailyRun = false;
      }
      particleSystem.clear();
      floatingLabels.clear();
      engine.start();
      startedAt = DateTime.now();
      focusNode.requestFocus();
      _armTicker();
    });
  }

  void _onTurn(Direction direction) {
    setState(() {
      final wasReady = engine.phase == GamePhase.ready;
      engine.queueTurn(direction);
      if (wasReady && engine.phase == GamePhase.running) {
        _armTicker();
      }
    });
  }

  String get actionLabel => switch (engine.phase) {
    GamePhase.ready => 'PLAY',
    GamePhase.running => 'PAUSE',
    GamePhase.paused => 'RESUME',
    GamePhase.gameOver => 'PLAY AGAIN',
  };

  void _onExitToMenu() {
    setState(() {
      ticker?.cancel();
      engine = widget.engineFactory?.call() ?? SnakeEngine(mode: selectedMode);
      engine.reset();
      engine.phase = GamePhase.ready;
      newHighScore = false;
      isDailyRun = false;
      particleSystem.clear();
      floatingLabels.clear();
      focusNode.requestFocus();
    });
  }

  /// Starts today's daily challenge: a Classic run seeded so every
  /// player sees the same food layout on the same calendar day.
  void _startDailyChallenge() {
    setState(() {
      ticker?.cancel();
      final seed = DailyChallenge.seedForDay(_dailyDayNumber);
      engine = SnakeEngine(mode: GameMode.classic, random: Random(seed));
      selectedMode = GameMode.classic;
      isDailyRun = true;
      newHighScore = false;
      particleSystem.clear();
      floatingLabels.clear();
      engine.start();
      startedAt = DateTime.now();
      focusNode.requestFocus();
    });
    _armTicker();
  }

  /// Shares the current run's result via the platform share sheet.
  Future<void> _shareScore() async {
    final text = isDailyRun
        ? 'HISSCORE Daily #$_dailyDayNumber — Score ${engine.score} 🐍🍎\n'
              'Streak: ${dailyState.currentStreak} day${dailyState.currentStreak == 1 ? '' : 's'}\n'
              'Can you beat it?'
        : 'HISSCORE — ${engine.mode.label} — Score ${engine.score}'
              '${engine.mode == GameMode.adventure ? ' (Level ${engine.level})' : ''} 🐍\n'
              'Can you beat it?';
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      debugPrint('Share failed: $e');
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    for (final t in _labelTimers) {
      t.cancel();
    }
    unawaited(soundManager.dispose());
    pulse.dispose();
    titleGlow.dispose();
    focusNode.dispose();
    shakeController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _onTurn(Direction.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _onTurn(Direction.down),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _onTurn(Direction.left),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _onTurn(Direction.right),
        const SingleActivator(LogicalKeyboardKey.keyW): () =>
            _onTurn(Direction.up),
        const SingleActivator(LogicalKeyboardKey.keyS): () =>
            _onTurn(Direction.down),
        const SingleActivator(LogicalKeyboardKey.keyA): () =>
            _onTurn(Direction.left),
        const SingleActivator(LogicalKeyboardKey.keyD): () =>
            _onTurn(Direction.right),
        const SingleActivator(LogicalKeyboardKey.space): _onPrimary,
        const SingleActivator(LogicalKeyboardKey.enter): _onPrimary,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (engine.phase == GamePhase.running) {
            setState(() {
              engine.pause();
              ticker?.cancel();
            });
          } else if (engine.phase == GamePhase.paused ||
              engine.phase == GamePhase.gameOver) {
            _onExitToMenu();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          if (engine.phase == GamePhase.running ||
              engine.phase == GamePhase.paused) {
            _onPrimary();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyM): () {
          if (engine.phase != GamePhase.ready) {
            _onExitToMenu();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyQ): () {
          if (engine.phase != GamePhase.ready) {
            _onExitToMenu();
          }
        },
      },
      child: Focus(
        focusNode: focusNode,
        autofocus: true,
        child: Scaffold(
          backgroundColor: RetroColors.voidBg,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.2,
                colors: [Color(0xFF10130F), RetroColors.voidBg],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: 440,
                        height: 800,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: _buildCabinet(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCabinet() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF201810), RetroColors.cabinet, Color(0xFF181010)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RetroColors.cabinetRim, width: 5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          children: [
            // ── Title ──
            _buildTitle(),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  engine.phase == GamePhase.ready
                      ? 'RETRO SNAKE'
                      : engine.mode.label,
                  style: RetroText.pixel(
                    size: 7,
                    color: engine.phase == GamePhase.ready
                        ? RetroColors.phosphorDim
                        : engine.mode.accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () {
                    final next = !soundManager.enabled;
                    unawaited(soundManager.setEnabled(next));
                    setState(() {});
                  },
                  child: Icon(
                    soundManager.enabled ? Icons.volume_up : Icons.volume_off,
                    size: 12,
                    color: RetroColors.phosphorDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Score bar ──
            _buildScoreBar(),
            const SizedBox(height: 10),

            // ── Board area ──
            Expanded(child: _buildBoardArea()),
            const SizedBox(height: 12),

            // ── Compact Centered Arcade Controls ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF140E0A), Color(0xFF0C0704)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: RetroColors.cabinetRim.withValues(alpha: 0.8),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Centered Cross D-Pad
                  ArcadeDpad(onTurn: _onTurn),
                  const SizedBox(height: 8),

                  // Centered Action Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ArcadeActionButton(
                        label: actionLabel,
                        onPressed: _onPrimary,
                      ),
                      if (engine.phase != GamePhase.ready) ...[
                        const SizedBox(width: 10),
                        SecondaryArcadeButton(
                          label: 'MENU',
                          color: RetroColors.amber,
                          onPressed: _onExitToMenu,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),

                  // Centered Hint Text
                  Text(
                    engine.phase == GamePhase.running
                        ? 'ARROWS / WASD  ·  ESC / M: MENU'
                        : 'ARROWS / WASD  ·  SWIPE',
                    textAlign: TextAlign.center,
                    style: RetroText.pixel(size: 5.5, color: RetroColors.metal),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return AnimatedBuilder(
      animation: titleGlow,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final glowPos = titleGlow.value;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                RetroColors.amber,
                RetroColors.phosphorHot,
                RetroColors.amber,
              ],
              stops: [
                (glowPos - 0.3).clamp(0.0, 1.0),
                glowPos,
                (glowPos + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(
            'HISCORE',
            style: RetroText.pixel(
              size: 22,
              color: Colors.white,
              letterSpacing: 4,
            ),
          ),
        );
      },
    );
  }

  Widget _buildScoreBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ScoreReadout(label: 'SCORE', value: engine.score),
        if (engine.mode == GameMode.adventure)
          _MiniStat(label: 'LVL', value: engine.level.toString()),
        if (engine.phase == GamePhase.running)
          GestureDetector(
            onTap: () {
              setState(() {
                engine.pause();
                ticker?.cancel();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: RetroColors.screen,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: RetroColors.amberDim, width: 1),
              ),
              child: Text(
                'SWITCH MODE',
                style: RetroText.pixel(size: 6, color: RetroColors.amber),
              ),
            ),
          ),
        if (engine.comboCount > 1)
          _MiniStat(
            label: 'COMBO',
            value: '×${engine.comboMultiplier.toStringAsFixed(1)}',
            color: RetroColors.combo,
          ),
        if (engine.hasShield)
          const _MiniStat(
            label: '',
            value: '🛡',
            color: RetroColors.shieldCyan,
          ),
        if (engine.magnetTicksLeft > 0)
          const _MiniStat(
            label: '',
            value: '🧲',
            color: RetroColors.magnetPink,
          ),
        ScoreReadout(label: 'HI', value: highScore, highlight: true),
      ],
    );
  }

  Widget _buildBoardArea() {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ScreenShake(
              controller: shakeController,
              child: SnakeBoard(
                engine: engine,
                pulse: pulse.value,
                particles: particleSystem,
                onSwipe: _onTurn,
              ),
            ),
            for (final label in floatingLabels)
              _FloatingLabelView(key: ValueKey(label.id), label: label),
            if (engine.phase != GamePhase.running)
              _Overlay(
                phase: engine.phase,
                engine: engine,
                won: engine.won,
                newHighScore: newHighScore,
                blinkOn: pulse.value > 0.4,
                selectedMode: selectedMode,
                onModeChanged: (mode) {
                  // Tapping the mode that's already active shouldn't
                  // wipe a paused run — only an actual mode change
                  // resets the game.
                  if (mode == selectedMode &&
                      engine.phase == GamePhase.paused) {
                    return;
                  }
                  setState(() {
                    selectedMode = mode;
                    ticker?.cancel();
                    engine =
                        widget.engineFactory?.call() ??
                        SnakeEngine(mode: selectedMode);
                    engine.mode = selectedMode;
                    engine.reset();
                    engine.phase = GamePhase.ready;
                    newHighScore = false;
                    isDailyRun = false;
                    particleSystem.clear();
                    floatingLabels.clear();
                    focusNode.requestFocus();
                  });
                },
                topScores: topScores,
                stats: stats,
                isDailyRun: isDailyRun,
                dailyDayNumber: _dailyDayNumber,
                dailyState: dailyState,
                playedDailyToday: _playedDailyToday,
                onStartDaily: _startDailyChallenge,
                onShare: _shareScore,
                onResume: _onPrimary,
                onExitToMenu: _onExitToMenu,
              ),
          ],
        );
      },
    );
  }
}

// ─── Floating popup text (score gains, combos, level-ups) ──

class _FloatingLabel {
  _FloatingLabel({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    this.big = false,
  });

  final int id;
  final String text;
  final double x;
  final double y;
  final Color color;
  final bool big;
}

class _FloatingLabelView extends StatelessWidget {
  const _FloatingLabelView({super.key, required this.label});

  final _FloatingLabel label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: label.x - 60,
      top: label.y - 20,
      width: 120,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (context, t, _) {
            return Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -24 * t),
                child: Transform.scale(
                  scale: 0.8 + (t < 0.25 ? t * 4 * 0.3 : 0.3),
                  child: Center(
                    child: Text(
                      label.text,
                      textAlign: TextAlign.center,
                      style: RetroText.pixel(
                        size: label.big ? 10 : 7,
                        color: label.color,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Mini stat chip (level, combo, shield) ──────────

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.color = RetroColors.phosphor,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label.isNotEmpty)
          Text(
            label,
            style: RetroText.pixel(size: 6, color: RetroColors.phosphorDim),
          ),
        if (label.isNotEmpty) const SizedBox(height: 2),
        Text(value, style: RetroText.pixel(size: 11, color: color)),
      ],
    );
  }
}

// ─── Overlay (ready / paused / game-over) ───────────

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.phase,
    required this.engine,
    required this.won,
    required this.newHighScore,
    required this.blinkOn,
    required this.selectedMode,
    required this.onModeChanged,
    required this.topScores,
    required this.stats,
    required this.isDailyRun,
    required this.dailyDayNumber,
    required this.dailyState,
    required this.playedDailyToday,
    required this.onStartDaily,
    required this.onShare,
    this.onResume,
    this.onExitToMenu,
  });

  final GamePhase phase;
  final SnakeEngine engine;
  final bool won;
  final bool newHighScore;
  final bool blinkOn;
  final GameMode selectedMode;
  final ValueChanged<GameMode> onModeChanged;
  final List<ScoreEntry> topScores;
  final GameStats stats;
  final bool isDailyRun;
  final int dailyDayNumber;
  final DailyState dailyState;
  final bool playedDailyToday;
  final VoidCallback onStartDaily;
  final VoidCallback onShare;
  final VoidCallback? onResume;
  final VoidCallback? onExitToMenu;

  @override
  Widget build(BuildContext context) {
    final title = switch (phase) {
      GamePhase.ready => 'PRESS START',
      GamePhase.paused => 'PAUSED',
      GamePhase.gameOver => won ? 'YOU WIN' : 'GAME OVER',
      GamePhase.running => '',
    };

    return IgnorePointer(
      ignoring: phase == GamePhase.running,
      child: ColoredBox(
        color: const Color(0x9903140A),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title.
                Opacity(
                  opacity: phase == GamePhase.ready && !blinkOn ? 0.35 : 1,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: RetroText.pixel(size: 14, color: RetroColors.amber),
                  ),
                ),

                // ── Ready: mode selector, food legend, stats, best runs ──
                if (phase == GamePhase.ready) ...[
                  const SizedBox(height: 16),
                  ModeSelector(
                    selected: selectedMode,
                    onChanged: onModeChanged,
                  ),
                  const SizedBox(height: 14),
                  const FoodLegend(),
                  if (stats.gamesPlayed > 0) ...[
                    const SizedBox(height: 12),
                    _StatsRow(stats: stats),
                  ],
                  if (topScores.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _TopScoresList(scores: topScores),
                  ],
                  const SizedBox(height: 16),
                  _DailyChallengeCard(
                    dayNumber: dailyDayNumber,
                    dailyState: dailyState,
                    playedToday: playedDailyToday,
                    onStart: onStartDaily,
                  ),
                ],

                // ── Paused: mode selector (picking a new mode restarts) ──
                if (phase == GamePhase.paused) ...[
                  const SizedBox(height: 16),
                  ModeSelector(
                    selected: selectedMode,
                    onChanged: onModeChanged,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'PICKING A NEW MODE RESTARTS THE RUN',
                    textAlign: TextAlign.center,
                    style: RetroText.pixel(size: 5, color: RetroColors.metal),
                  ),
                ],

                // ── Game over: score breakdown & mode selector ──
                if (phase == GamePhase.gameOver) ...[
                  const SizedBox(height: 12),
                  Text(
                    engine.score.toString().padLeft(5, '0'),
                    style: RetroText.pixel(
                      size: 16,
                      color: RetroColors.phosphor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ScoreBreakdown(engine: engine),
                  if (isDailyRun) ...[
                    const SizedBox(height: 8),
                    Text(
                      'DAILY #$dailyDayNumber  ·  STREAK ${dailyState.currentStreak}',
                      style: RetroText.pixel(size: 7, color: RetroColors.zenBlue),
                    ),
                  ],
                  if (newHighScore) ...[
                    const SizedBox(height: 10),
                    Text(
                      'NEW HISCORE',
                      style: RetroText.pixel(size: 10, color: RetroColors.food),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SecondaryArcadeButton(
                    label: 'SHARE SCORE',
                    color: RetroColors.zenBlue,
                    onPressed: onShare,
                  ),
                  if (topScores.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _TopScoresList(scores: topScores),
                  ],
                  const SizedBox(height: 14),
                  ModeSelector(
                    selected: selectedMode,
                    onChanged: onModeChanged,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Score breakdown on game-over ────────────────────

class _ScoreBreakdown extends StatelessWidget {
  const _ScoreBreakdown({required this.engine});

  final SnakeEngine engine;

  @override
  Widget build(BuildContext context) {
    final items = <_BreakdownItem>[
      _BreakdownItem('APPLES', engine.totalApplesEaten.toString()),
      if (engine.mode == GameMode.adventure)
        _BreakdownItem('LEVEL', engine.level.toString()),
      if (engine.bestCombo > 1)
        _BreakdownItem(
          'BEST COMBO',
          '×${(1.0 + (engine.bestCombo - 1) * 0.5).toStringAsFixed(1)}',
        ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                items[i].label,
                style: RetroText.pixel(size: 6, color: RetroColors.phosphorDim),
              ),
              const SizedBox(height: 2),
              Text(
                items[i].value,
                style: RetroText.pixel(size: 9, color: RetroColors.phosphor),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BreakdownItem {
  const _BreakdownItem(this.label, this.value);
  final String label;
  final String value;
}

// ─── Lifetime stats (ready screen) ──────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final GameStats stats;

  @override
  Widget build(BuildContext context) {
    final comboMult = stats.bestCombo <= 1
        ? 1.0
        : 1.0 + (stats.bestCombo - 1) * 0.5;
    final items = [
      _BreakdownItem('GAMES', stats.gamesPlayed.toString()),
      _BreakdownItem('APPLES', stats.totalApples.toString()),
      _BreakdownItem('BEST COMBO', '×${comboMult.toStringAsFixed(1)}'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                items[i].label,
                style: RetroText.pixel(size: 5, color: RetroColors.metal),
              ),
              const SizedBox(height: 2),
              Text(
                items[i].value,
                style: RetroText.pixel(size: 7, color: RetroColors.phosphorDim),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Daily challenge card (ready screen) ─────────────

class _DailyChallengeCard extends StatelessWidget {
  const _DailyChallengeCard({
    required this.dayNumber,
    required this.dailyState,
    required this.playedToday,
    required this.onStart,
  });

  final int dayNumber;
  final DailyState dailyState;
  final bool playedToday;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RetroColors.zenBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: RetroColors.zenBlue.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DAILY CHALLENGE #$dayNumber',
            style: RetroText.pixel(size: 7, color: RetroColors.zenBlue),
          ),
          if (dailyState.currentStreak > 0) ...[
            const SizedBox(height: 6),
            Text(
              'STREAK ${dailyState.currentStreak} DAY'
              '${dailyState.currentStreak == 1 ? '' : 'S'}'
              '${dailyState.bestStreak > dailyState.currentStreak ? '  ·  BEST ${dailyState.bestStreak}' : ''}',
              style: RetroText.pixel(size: 6, color: RetroColors.metal),
            ),
          ],
          if (playedToday) ...[
            const SizedBox(height: 4),
            Text(
              "TODAY'S SCORE ${dailyState.lastScore}",
              style: RetroText.pixel(size: 6, color: RetroColors.phosphorDim),
            ),
          ],
          const SizedBox(height: 8),
          SecondaryArcadeButton(
            label: playedToday ? 'PLAY DAILY AGAIN' : 'PLAY DAILY',
            color: RetroColors.zenBlue,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

// ─── Top 5 leaderboard ──────────────────────────────

class _TopScoresList extends StatelessWidget {
  const _TopScoresList({required this.scores});

  final List<ScoreEntry> scores;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TOP SCORES',
          style: RetroText.pixel(size: 7, color: RetroColors.amberDim),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < scores.length && i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}.',
                    style: RetroText.pixel(
                      size: 6,
                      color: i == 0 ? RetroColors.amber : RetroColors.metal,
                    ),
                  ),
                ),
                Text(
                  scores[i].score.toString().padLeft(5, '0'),
                  style: RetroText.pixel(
                    size: 7,
                    color: i == 0 ? RetroColors.amber : RetroColors.phosphorDim,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'L${scores[i].level}',
                  style: RetroText.pixel(size: 6, color: RetroColors.metal),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
