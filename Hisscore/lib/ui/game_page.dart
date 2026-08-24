import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/high_score_store.dart';
import '../game/snake_engine.dart';
import 'board.dart';
import 'controls.dart';
import 'theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({
    super.key,
    required this.highScoreStore,
    this.engineFactory,
  });

  final HighScoreStore highScoreStore;
  final SnakeEngine Function()? engineFactory;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage>
    with SingleTickerProviderStateMixin {
  late SnakeEngine engine;
  late AnimationController pulse;
  Timer? ticker;
  int highScore = 0;
  bool newHighScore = false;

  @override
  void initState() {
    super.initState();
    engine = widget.engineFactory?.call() ?? SnakeEngine();
    pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    unawaited(_loadHighScore());
  }

  Future<void> _loadHighScore() async {
    final value = await widget.highScoreStore.load();
    if (!mounted) {
      return;
    }
    setState(() => highScore = value);
  }

  Future<void> _persistHighScore() async {
    if (engine.score > highScore) {
      highScore = engine.score;
      newHighScore = true;
      await widget.highScoreStore.save(engine.score);
    }
  }

  void _armTicker() {
    ticker?.cancel();
    if (engine.phase != GamePhase.running) {
      return;
    }
    ticker = Timer.periodic(engine.tickInterval, (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        engine.tick();
        if (engine.justAte) {
          unawaited(_persistHighScore());
          _armTicker();
        }
        if (engine.phase == GamePhase.gameOver) {
          ticker?.cancel();
          unawaited(_persistHighScore());
        }
      });
    });
  }

  void _onPrimary() {
    setState(() {
      if (engine.phase == GamePhase.running) {
        engine.pause();
        ticker?.cancel();
        return;
      }
      newHighScore = false;
      engine.start();
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

  String get actionLabel {
    return switch (engine.phase) {
      GamePhase.ready => 'PLAY',
      GamePhase.running => 'PAUSE',
      GamePhase.paused => 'RESUME',
      GamePhase.gameOver => 'PLAY AGAIN',
    };
  }

  @override
  void dispose() {
    ticker?.cancel();
    pulse.dispose();
    super.dispose();
  }

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
          if (engine.phase == GamePhase.running ||
              engine.phase == GamePhase.paused) {
            setState(() {
              engine.pause();
              if (engine.phase == GamePhase.paused) {
                ticker?.cancel();
              } else {
                _armTicker();
              }
            });
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          if (engine.phase == GamePhase.running ||
              engine.phase == GamePhase.paused) {
            setState(() {
              engine.pause();
              if (engine.phase == GamePhase.paused) {
                ticker?.cancel();
              } else {
                _armTicker();
              }
            });
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: RetroColors.voidBg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth.clamp(0, 520).toDouble();
                return Center(
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: RetroColors.cabinet,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: RetroColors.cabinetRim,
                            width: 6,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 24,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                          child: Column(
                            children: [
                              Text(
                                'HISCORE',
                                style: RetroText.pixel(
                                  size: 22,
                                  color: RetroColors.amber,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'RETRO SNAKE',
                                style: RetroText.pixel(
                                  size: 8,
                                  color: RetroColors.phosphorDim,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  ScoreReadout(
                                    label: 'SCORE',
                                    value: engine.score,
                                  ),
                                  ScoreReadout(
                                    label: 'HI',
                                    value: highScore,
                                    highlight: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: AnimatedBuilder(
                                  animation: pulse,
                                  builder: (context, _) {
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        SnakeBoard(
                                          engine: engine,
                                          pulse: pulse.value,
                                          onSwipe: _onTurn,
                                        ),
                                        if (engine.phase != GamePhase.running)
                                          _Overlay(
                                            phase: engine.phase,
                                            score: engine.score,
                                            won: engine.won,
                                            newHighScore: newHighScore,
                                            blinkOn: pulse.value > 0.4,
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              ArcadeDpad(onTurn: _onTurn),
                              const SizedBox(height: 16),
                              ArcadeActionButton(
                                label: actionLabel,
                                onPressed: _onPrimary,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'ARROWS / WASD  ·  SWIPE',
                                textAlign: TextAlign.center,
                                style: RetroText.pixel(
                                  size: 7,
                                  color: RetroColors.metal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({
    required this.phase,
    required this.score,
    required this.won,
    required this.newHighScore,
    required this.blinkOn,
  });

  final GamePhase phase;
  final int score;
  final bool won;
  final bool newHighScore;
  final bool blinkOn;

  @override
  Widget build(BuildContext context) {
    final title = switch (phase) {
      GamePhase.ready => 'PRESS START',
      GamePhase.paused => 'PAUSED',
      GamePhase.gameOver => won ? 'YOU WIN' : 'GAME OVER',
      GamePhase.running => '',
    };

    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0x9903140A),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (phase == GamePhase.ready || blinkOn)
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: RetroText.pixel(size: 14, color: RetroColors.amber),
                ),
              if (phase == GamePhase.gameOver) ...[
                const SizedBox(height: 16),
                Text(
                  score.toString().padLeft(5, '0'),
                  style: RetroText.pixel(size: 16, color: RetroColors.phosphor),
                ),
                if (newHighScore) ...[
                  const SizedBox(height: 10),
                  Text(
                    'NEW HISCORE',
                    style: RetroText.pixel(size: 10, color: RetroColors.food),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
