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
import 'floating_label.dart';
import 'game_overlay.dart';
import 'hud_widgets.dart';
import 'intro_panel.dart';
import 'particles.dart';
import 'ready_tabs.dart';
import 'screen_shake.dart';
import 'theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.highScoreStore, this.engineFactory});

  final HighScoreStore highScoreStore;
  final SnakeEngine Function()? engineFactory;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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
  final List<FloatingLabel> floatingLabels = [];
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
    WidgetsBinding.instance.addObserver(this);
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

  /// Leaving the foreground must not cost the player a run: a call or a
  /// notification would otherwise keep the ticker going and kill the
  /// snake off-screen. The attract demo stops too, rather than
  /// animating a menu nobody is looking at.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      // A paused run stays paused — the player decides when to go
      // again — but the menu comes back to life.
      if (showIntro && demoTicker == null) _startDemo();
      return;
    }

    if (engine.phase == GamePhase.running) {
      setState(() {
        engine.pause();
        ticker?.cancel();
      });
    }
    _stopDemo();
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

  /// Tracks a new high score in memory while the run is going.
  ///
  /// Writing to disk on every apple meant a store write (and a second
  /// prefs read from the review prompter) every tick or so late in a
  /// run. The number on screen is state, not storage — it gets flushed
  /// once, when the run ends.
  void _noteHighScore() {
    if (!_countsForLeaderboard) return;
    if (engine.score <= highScore) return;
    highScore = engine.score;
    newHighScore = true;
  }

  Future<void> _persistHighScore() async {
    if (!_countsForLeaderboard) return;
    if (engine.score > highScore) {
      highScore = engine.score;
      newHighScore = true;
    }
    if (!newHighScore) return;
    await widget.highScoreStore.save(highScore);
    unawaited(reviewPrompter.maybePrompt(gamesPlayed: stats.gamesPlayed));
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
          _noteHighScore();
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
      FloatingLabel(
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
    return Offset(point.x * cellW + cellW / 2, point.y * cellH + cellH / 2);
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
    WidgetsBinding.instance.removeObserver(this);
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
                  MiniStat(label: 'LVL', value: engine.level.toString()),
                if (engine.comboCount > 1)
                  MiniStat(
                    label: 'COMBO',
                    value: '×${engine.comboMultiplier.toStringAsFixed(1)}',
                    color: RetroColors.combo,
                  ),
                if (engine.hasShield)
                  const MiniStat(
                    label: '',
                    value: '🛡',
                    color: RetroColors.shieldCyan,
                  ),
                if (engine.magnetActive)
                  const MiniStat(
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
          PauseButton(
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
            IntroPanel(
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
              FloatingLabelView(key: ValueKey(label.id), label: label),
            if (engine.phase == GamePhase.paused ||
                engine.phase == GamePhase.gameOver)
              GameOverlay(
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
