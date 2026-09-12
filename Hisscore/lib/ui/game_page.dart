import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../game/auto_player.dart';
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

  // Which ready-screen tab is showing.
  ReadyTab readyTab = ReadyTab.modes;

  /// Intro (cabinet, attract demo, mode picking) versus the full-screen
  /// game. The engine's own phase drives everything inside the game.
  bool showIntro = true;

  /// A second engine that plays itself behind the intro screen.
  SnakeEngine? demoEngine;
  Timer? demoTicker;
  DateTime _demoTickAt = DateTime.now();

  /// Last measured viewport, so a new game's grid can be sized to the
  /// device instead of a fixed square.
  Size _viewport = Size.zero;

  /// Status-bar / notch inset, excluded from the play area.
  double _topInset = 0;

  /// Height of the in-game HUD band above the board.
  static const double _hudHeight = 52;

  /// What the board itself will get once the HUD band is taken off the
  /// top — the grid is shaped to this, not to the whole screen.
  Size get _playAreaSize => Size(
    _viewport.width,
    (_viewport.height - _topInset - _hudHeight).clamp(1, double.infinity),
  );

  // Floating popup text (score gains, combos, level-ups).
  final List<_FloatingLabel> floatingLabels = [];
  final List<Timer> _labelTimers = [];
  int _labelSeq = 0;

  // Movement interpolation: when the current tick started, so the board
  // can animate the snake between cells instead of jumping.
  DateTime _lastTickAt = DateTime.now();

  /// When the last level-up flash fired, so it can fade out on its own.
  DateTime? _levelFlashAt;
  static const _levelFlashDuration = Duration(milliseconds: 420);

  /// 1.0 right after a level advance, fading to 0.
  double get _levelFlashOpacity {
    final at = _levelFlashAt;
    if (at == null) return 0;
    final elapsed = DateTime.now().difference(at).inMilliseconds;
    final total = _levelFlashDuration.inMilliseconds;
    if (elapsed >= total) return 0;
    return 1.0 - elapsed / total;
  }

  /// Measured board geometry, so particles and popups land on the cell
  /// they belong to instead of an assumed board size.
  Size _boardSize = Size.zero;
  Offset _boardOffset = Offset.zero;

  /// Builds an engine sized to the current screen. Tests inject their
  /// own engine and keep whatever grid they asked for.
  SnakeEngine _newEngine({GameMode? mode, Random? random}) {
    final injected = widget.engineFactory;
    if (injected != null && random == null) return injected();
    final grid = boardGridFor(_playAreaSize);
    return SnakeEngine(
      columns: grid.columns,
      rows: grid.rows,
      mode: mode ?? selectedMode,
      random: random,
    );
  }

  double get _tickProgress {
    if (engine.phase != GamePhase.running) return 1.0;
    final tickMs = engine.tickInterval.inMilliseconds;
    if (tickMs <= 0) return 1.0;
    final elapsed = DateTime.now().difference(_lastTickAt).inMicroseconds;
    return (elapsed / (tickMs * 1000)).clamp(0.0, 1.0);
  }

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
    _startDemo();
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

  // ═══════════════════════════════════════════════════
  // Attract mode
  // ═══════════════════════════════════════════════════

  /// Runs a snake that plays itself behind the intro, so the menu shows
  /// the game rather than describing it.
  void _startDemo() {
    demoTicker?.cancel();
    final demo = SnakeEngine(
      columns: 20,
      rows: 20,
      mode: GameMode.endless, // wraps, so the demo rarely stalls
    );
    demo.start();
    demoEngine = demo;
    _demoTickAt = DateTime.now();
    demoTicker = Timer.periodic(const Duration(milliseconds: 170), (_) {
      if (!mounted || !showIntro) return;
      setState(() {
        _demoTickAt = DateTime.now();
        final next = AutoPlayer.chooseDirection(demo);
        if (next != null) demo.queueTurn(next);
        demo.tick();
        // Cornered itself — start over rather than sit on a dead board.
        if (demo.phase != GamePhase.running) {
          demo.reset();
          demo.start();
        }
      });
    });
  }

  void _stopDemo() {
    demoTicker?.cancel();
    demoTicker = null;
    demoEngine = null;
  }

  double get _demoTickProgress {
    final demo = demoEngine;
    if (demo == null) return 1;
    final tickMs = demo.tickInterval.inMilliseconds;
    if (tickMs <= 0) return 1;
    final elapsed = DateTime.now().difference(_demoTickAt).inMicroseconds;
    return (elapsed / (tickMs * 1000)).clamp(0.0, 1.0);
  }

  void _armTicker() {
    ticker?.cancel();
    if (engine.phase != GamePhase.running) return;
    _lastTickAt = DateTime.now();
    ticker = Timer.periodic(engine.tickInterval, (_) {
      if (!mounted) return;
      final scoreBefore = engine.score;
      setState(() {
        _lastTickAt = DateTime.now();
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
          _levelFlashAt = DateTime.now();
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
    final cell = _cellCenter(gridPos);
    final id = _labelSeq++;
    floatingLabels.add(
      _FloatingLabel(
        id: id,
        text: text,
        // Labels sit in the board *area*, so shift by where the board
        // itself is within it.
        x: cell.dx + _boardOffset.dx,
        y: cell.dy + _boardOffset.dy,
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

  /// Centre of a grid cell in the board's own pixel space — the same
  /// space the painter (and therefore the particle system) draws in.
  Offset _cellCenter(GridPoint point) {
    final cellW = _boardSize.width / engine.columns;
    final cellH = _boardSize.height / engine.rows;
    return Offset(
      point.x * cellW + cellW / 2,
      point.y * cellH + cellH / 2,
    );
  }

  void _emitEatParticles(GridPoint pos) {
    final cell = _cellCenter(pos);
    final cx = cell.dx;
    final cy = cell.dy;

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
    final cell = _cellCenter(engine.head);
    particleSystem.emitDeath(cell.dx, cell.dy, RetroColors.cherry);
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
        // A fresh run always gets an engine sized to this screen.
        engine = _newEngine();
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

  /// Leaves the intro for the full-screen game.
  void _enterGame() {
    _stopDemo();
    setState(() => showIntro = false);
    _onPrimary();
  }

  /// Back to the intro, demo running again.
  void _returnToIntro() {
    setState(() {
      ticker?.cancel();
      engine = _newEngine();
      engine.reset();
      engine.phase = GamePhase.ready;
      newHighScore = false;
      isDailyRun = false;
      showIntro = true;
      particleSystem.clear();
      floatingLabels.clear();
      focusNode.requestFocus();
    });
    _startDemo();
  }

  /// Android's back gesture: pause a run, leave a finished or paused one,
  /// and only close the app from the intro.
  void _onSystemBack() {
    if (showIntro) return;
    if (engine.phase == GamePhase.running) {
      setState(() {
        engine.pause();
        ticker?.cancel();
      });
      return;
    }
    _returnToIntro();
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

  void _onExitToMenu() => _returnToIntro();

  /// Starts today's daily challenge: a Classic run seeded from the
  /// date, so the same device gets the same board all day.
  ///
  /// Note the grid now follows the screen, so two different-sized
  /// phones no longer see an identical layout. That only starts to
  /// matter if daily scores are ever compared across devices.
  void _startDailyChallenge() {
    _stopDemo();
    setState(() {
      ticker?.cancel();
      final seed = DailyChallenge.seedForDay(_dailyDayNumber);
      engine = _newEngine(mode: GameMode.classic, random: Random(seed));
      engine.mode = GameMode.classic;
      selectedMode = GameMode.classic;
      isDailyRun = true;
      newHighScore = false;
      showIntro = false;
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
    demoTicker?.cancel();
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
          body: PopScope(
            // Back belongs to the game first: pause a run, leave a
            // finished one, and only then close the app.
            canPop: showIntro,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _onSystemBack();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = constraints.biggest;
                _topInset = MediaQuery.paddingOf(context).top;
                return showIntro ? _buildIntro() : _buildGameScreen();
              },
            ),
          ),
        ),
      ),
    );
  }

  /// The intro: cabinet chrome, the attract demo playing in its screen,
  /// and everything you pick before a run.
  Widget _buildIntro() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.2,
          colors: [Color(0xFF10130F), RetroColors.voidBg],
        ),
      ),
      child: SafeArea(
        child: Center(
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
        ),
      ),
    );
  }

  /// The game: board edge to edge, a thin HUD over it, gestures only.
  Widget _buildGameScreen() {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // The HUD gets its own band rather than floating over the
          // playfield — otherwise the snake runs underneath the score.
          SizedBox(height: _hudHeight, child: _buildGameHud()),
          Expanded(child: _buildBoardStack()),
        ],
      ),
    );
  }

  Widget _buildGameHud() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: const BoxDecoration(
        color: RetroColors.voidBg,
        border: Border(
          bottom: BorderSide(color: RetroColors.phosphorDim, width: 1.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScoreReadout(label: 'SCORE', value: engine.score),
          const SizedBox(width: 14),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (engine.mode == GameMode.adventure)
                  _MiniStat(label: 'LVL', value: engine.level.toString()),
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
                if (engine.magnetActive)
                  const _MiniStat(
                    label: '',
                    value: '🧲',
                    color: RetroColors.magnetPink,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          ScoreReadout(label: 'HI', value: highScore, highlight: true),
          const SizedBox(width: 10),
          _PauseButton(
            onPressed: () {
              if (engine.phase != GamePhase.running) return;
              setState(() {
                engine.pause();
                ticker?.cancel();
              });
            },
          ),
        ],
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

            // ── Attract demo with the menu over it ──
            Expanded(child: _buildIntroScreenArea()),
            const SizedBox(height: 14),

            // ── Start ──
            ArcadeActionButton(label: 'PLAY', onPressed: _enterGame),
            const SizedBox(height: 8),
            Text(
              'SWIPE TO STEER  ·  ARROWS / WASD',
              textAlign: TextAlign.center,
              style: RetroText.pixel(size: 7, color: RetroColors.metal),
            ),
          ],
        ),
      ),
    );
  }

  /// The cabinet's screen on the intro: the demo snake playing itself,
  /// with the mode picker and friends laid over it.
  Widget _buildIntroScreenArea() {
    final demo = demoEngine;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (demo != null)
              SnakeBoard(
                engine: demo,
                pulse: pulse.value,
                tickProgress: _demoTickProgress,
              ),
            _IntroPanel(
              blinkOn: pulse.value > 0.4,
              selectedMode: selectedMode,
              onModeChanged: (mode) {
                setState(() {
                  selectedMode = mode;
                  engine.mode = mode;
                });
              },
              readyTab: readyTab,
              onReadyTabChanged: (tab) => setState(() => readyTab = tab),
              stats: stats,
              topScores: topScores,
              dailyDayNumber: _dailyDayNumber,
              dailyState: dailyState,
              playedDailyToday: _playedDailyToday,
              onStartDaily: _startDailyChallenge,
            ),
          ],
        );
      },
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

  Widget _buildBoardStack() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The board fills this area edge to edge, so its geometry is
        // simply the area itself — particles and popups ride on it.
        _boardSize = constraints.biggest;
        _boardOffset = Offset.zero;
        return _buildBoardLayers();
      },
    );
  }

  Widget _buildBoardLayers() {
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
                tickProgress: _tickProgress,
                particles: particleSystem,
                onSwipe: _onTurn,
                fullBleed: true,
              ),
            ),
            // Level-up flash, over the board but under the popups.
            if (_levelFlashOpacity > 0)
              IgnorePointer(
                child: Opacity(
                  opacity: _levelFlashOpacity * 0.5,
                  child: const ColoredBox(color: RetroColors.levelFlash),
                ),
              ),
            for (final label in floatingLabels)
              _FloatingLabelView(key: ValueKey(label.id), label: label),
            if (engine.phase == GamePhase.paused ||
                engine.phase == GamePhase.gameOver)
              _Overlay(
                phase: engine.phase,
                engine: engine,
                won: engine.won,
                newHighScore: newHighScore,
                isDailyRun: isDailyRun,
                dailyDayNumber: _dailyDayNumber,
                dailyState: dailyState,
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


// ─── Pause button (in-game HUD) ─────────────────────

/// Deliberately a small dedicated target rather than tap-anywhere: the
/// whole board is a swipe surface, so a stray tap must never pause.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pause',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: RetroColors.screen.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RetroColors.phosphorDim, width: 1.4),
          ),
          child: const Icon(
            Icons.pause,
            size: 20,
            color: RetroColors.phosphor,
          ),
        ),
      ),
    );
  }
}

// ─── Intro panel (over the attract demo) ────────────

class _IntroPanel extends StatelessWidget {
  const _IntroPanel({
    required this.blinkOn,
    required this.selectedMode,
    required this.onModeChanged,
    required this.readyTab,
    required this.onReadyTabChanged,
    required this.stats,
    required this.topScores,
    required this.dailyDayNumber,
    required this.dailyState,
    required this.playedDailyToday,
    required this.onStartDaily,
  });

  final bool blinkOn;
  final GameMode selectedMode;
  final ValueChanged<GameMode> onModeChanged;
  final ReadyTab readyTab;
  final ValueChanged<ReadyTab> onReadyTabChanged;
  final GameStats stats;
  final List<ScoreEntry> topScores;
  final int dailyDayNumber;
  final DailyState dailyState;
  final bool playedDailyToday;
  final VoidCallback onStartDaily;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      // Dark enough to read against, sheer enough to keep the demo
      // visible behind it.
      color: const Color(0xCC03140A),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: blinkOn ? 1 : 0.35,
                child: Text(
                  'PRESS START',
                  textAlign: TextAlign.center,
                  style: RetroText.pixel(size: 14, color: RetroColors.amber),
                ),
              ),
              const SizedBox(height: 14),
              _ReadyTabBar(selected: readyTab, onChanged: onReadyTabChanged),
              const SizedBox(height: 14),
              switch (readyTab) {
                ReadyTab.modes => _ReadyModesTab(
                  selectedMode: selectedMode,
                  onModeChanged: onModeChanged,
                  dailyDayNumber: dailyDayNumber,
                  dailyState: dailyState,
                  playedDailyToday: playedDailyToday,
                  onStartDaily: onStartDaily,
                ),
                ReadyTab.how => const _ReadyHowTab(),
                ReadyTab.stats => _ReadyStatsTab(
                  stats: stats,
                  topScores: topScores,
                  dailyState: dailyState,
                ),
              },
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Overlay (paused / game-over) ───────────────────

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.phase,
    required this.engine,
    required this.won,
    required this.newHighScore,
    required this.isDailyRun,
    required this.dailyDayNumber,
    required this.dailyState,
    required this.onShare,
    required this.onResume,
    required this.onExitToMenu,
  });

  final GamePhase phase;
  final SnakeEngine engine;
  final bool won;
  final bool newHighScore;
  final bool isDailyRun;
  final int dailyDayNumber;
  final DailyState dailyState;
  final VoidCallback onShare;
  final VoidCallback onResume;
  final VoidCallback onExitToMenu;

  @override
  Widget build(BuildContext context) {
    final isOver = phase == GamePhase.gameOver;
    final title = isOver ? (won ? 'YOU WIN' : 'GAME OVER') : 'PAUSED';

    return ColoredBox(
      color: const Color(0xE603140A),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: RetroText.pixel(size: 16, color: RetroColors.amber),
                ),
                if (isOver) ...[
                  const SizedBox(height: 14),
                  Text(
                    engine.score.toString().padLeft(5, '0'),
                    style: RetroText.pixel(
                      size: 18,
                      color: RetroColors.phosphor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ScoreBreakdown(engine: engine),
                  if (isDailyRun) ...[
                    const SizedBox(height: 10),
                    Text(
                      'DAILY #$dailyDayNumber  ·  STREAK ${dailyState.currentStreak}',
                      style: RetroText.pixel(
                        size: 8,
                        color: RetroColors.zenBlue,
                      ),
                    ),
                  ],
                  if (newHighScore) ...[
                    const SizedBox(height: 12),
                    Text(
                      'NEW HISCORE',
                      style: RetroText.pixel(size: 11, color: RetroColors.food),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SecondaryArcadeButton(
                    label: 'SHARE SCORE',
                    color: RetroColors.zenBlue,
                    onPressed: onShare,
                  ),
                ],
                const SizedBox(height: 22),
                ArcadeActionButton(
                  label: isOver ? 'PLAY AGAIN' : 'RESUME',
                  onPressed: onResume,
                ),
                const SizedBox(height: 12),
                SecondaryArcadeButton(
                  label: 'MENU',
                  color: RetroColors.amber,
                  onPressed: onExitToMenu,
                ),
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
                style: RetroText.pixel(size: 7, color: RetroColors.metal),
              ),
              const SizedBox(height: 2),
              Text(
                items[i].value,
                style: RetroText.pixel(size: 9, color: RetroColors.phosphorDim),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Ready screen tabs ──────────────────────────────

/// The ready screen used to stack modes, legend, stats and scores in one
/// column, which left everything at 5–6px on a phone. One tab at a time
/// buys the room to set type at a readable size.
enum ReadyTab {
  modes('MODES'),
  how('HOW'),
  stats('STATS');

  const ReadyTab(this.label);
  final String label;
}

class _ReadyTabBar extends StatelessWidget {
  const _ReadyTabBar({required this.selected, required this.onChanged});

  static const _tabFade = Duration(milliseconds: 200);

  final ReadyTab selected;
  final ValueChanged<ReadyTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final tab in ReadyTab.values) ...[
          if (tab != ReadyTab.values.first) const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onChanged(tab),
            child: AnimatedContainer(
              duration: _tabFade,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tab == selected
                    ? RetroColors.phosphor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: tab == selected
                      ? RetroColors.phosphor
                      : RetroColors.phosphorDim,
                  width: 1.5,
                ),
              ),
              // The label fades with the fill. Switching it instantly
              // would leave dark text on a still-dark chip for the
              // length of the fade.
              child: AnimatedDefaultTextStyle(
                duration: _tabFade,
                style: RetroText.pixel(
                  size: 8,
                  color: tab == selected
                      ? RetroColors.cabinet
                      : RetroColors.phosphorDim,
                ),
                child: Text(tab.label),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadyModesTab extends StatelessWidget {
  const _ReadyModesTab({
    required this.selectedMode,
    required this.onModeChanged,
    required this.dailyDayNumber,
    required this.dailyState,
    required this.playedDailyToday,
    required this.onStartDaily,
  });

  final GameMode selectedMode;
  final ValueChanged<GameMode> onModeChanged;
  final int dailyDayNumber;
  final DailyState dailyState;
  final bool playedDailyToday;
  final VoidCallback onStartDaily;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ModeSelector(selected: selectedMode, onChanged: onModeChanged),
        const SizedBox(height: 18),
        _DailyChallengeCard(
          dayNumber: dailyDayNumber,
          dailyState: dailyState,
          playedToday: playedDailyToday,
          onStart: onStartDaily,
        ),
      ],
    );
  }
}

class _ReadyHowTab extends StatelessWidget {
  const _ReadyHowTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PICKUPS',
          style: RetroText.pixel(size: 9, color: RetroColors.amberDim),
        ),
        const SizedBox(height: 10),
        const FoodLegend(),
        const SizedBox(height: 18),
        Text(
          'CONTROLS',
          style: RetroText.pixel(size: 9, color: RetroColors.amberDim),
        ),
        const SizedBox(height: 10),
        for (final line in const [
          'SWIPE OR DRAG TO TURN',
          'ARROWS / WASD',
          'SPACE: PAUSE  ·  M: MENU',
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              line,
              textAlign: TextAlign.center,
              style: RetroText.pixel(size: 7, color: RetroColors.metal),
            ),
          ),
      ],
    );
  }
}

class _ReadyStatsTab extends StatelessWidget {
  const _ReadyStatsTab({
    required this.stats,
    required this.topScores,
    required this.dailyState,
  });

  final GameStats stats;
  final List<ScoreEntry> topScores;
  final DailyState dailyState;

  @override
  Widget build(BuildContext context) {
    if (stats.gamesPlayed == 0 && topScores.isEmpty) {
      return Text(
        'NO RUNS YET',
        style: RetroText.pixel(size: 8, color: RetroColors.metal),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (stats.gamesPlayed > 0) ...[
          _StatsRow(stats: stats),
          const SizedBox(height: 16),
        ],
        if (dailyState.bestStreak > 0) ...[
          Text(
            'BEST STREAK ${dailyState.bestStreak} DAY'
            '${dailyState.bestStreak == 1 ? '' : 'S'}',
            style: RetroText.pixel(size: 7, color: RetroColors.zenBlue),
          ),
          const SizedBox(height: 16),
        ],
        if (topScores.isNotEmpty) _TopScoresList(scores: topScores),
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
            style: RetroText.pixel(size: 8, color: RetroColors.zenBlue),
          ),
          if (dailyState.currentStreak > 0) ...[
            const SizedBox(height: 6),
            Text(
              'STREAK ${dailyState.currentStreak} DAY'
              '${dailyState.currentStreak == 1 ? '' : 'S'}'
              '${dailyState.bestStreak > dailyState.currentStreak ? '  ·  BEST ${dailyState.bestStreak}' : ''}',
              style: RetroText.pixel(size: 7, color: RetroColors.metal),
            ),
          ],
          if (playedToday) ...[
            const SizedBox(height: 4),
            Text(
              "TODAY'S SCORE ${dailyState.lastScore}",
              style: RetroText.pixel(size: 7, color: RetroColors.phosphorDim),
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
          style: RetroText.pixel(size: 9, color: RetroColors.amberDim),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < scores.length && i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}.',
                    style: RetroText.pixel(
                      size: 7,
                      color: i == 0 ? RetroColors.amber : RetroColors.metal,
                    ),
                  ),
                ),
                Text(
                  scores[i].score.toString().padLeft(5, '0'),
                  style: RetroText.pixel(
                    size: 9,
                    color: i == 0 ? RetroColors.amber : RetroColors.phosphorDim,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'L${scores[i].level}',
                  style: RetroText.pixel(size: 7, color: RetroColors.metal),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
