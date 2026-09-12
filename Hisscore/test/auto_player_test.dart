import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/auto_player.dart';
import 'package:hisscore/game/food_types.dart';
import 'package:hisscore/game/snake_engine.dart';

void main() {
  SnakeEngine engine({
    int columns = 20,
    int rows = 20,
    GameMode mode = GameMode.endless,
    int seed = 1,
  }) {
    return SnakeEngine(
      columns: columns,
      rows: rows,
      mode: mode,
      firstFoodDistance: 10,
      random: Random(seed),
    );
  }

  test('heads toward the food', () {
    final game = engine();
    game.start();
    // Food directly below the head.
    game.foods = [
      FoodItem(
        position: GridPoint(game.head.x, game.head.y + 5),
        type: FoodType.apple,
      ),
    ];

    expect(AutoPlayer.chooseDirection(game), Direction.down);
  });

  test('never turns back on itself', () {
    final game = engine();
    game.start();
    // Food behind the snake: it must not reverse into its own neck.
    game.foods = [
      FoodItem(
        position: GridPoint(game.head.x - 5, game.head.y),
        type: FoodType.apple,
      ),
    ];

    final choice = AutoPlayer.chooseDirection(game);
    expect(choice, isNot(game.direction.opposite));
  });

  test('does not walk into a wall when the board has edges', () {
    final game = engine(mode: GameMode.classic, columns: 8, rows: 8);
    game.start();
    // Put the snake one cell from the right wall, heading at it, with
    // the food beyond the wall so the greedy pull points outward.
    game.snake = [const GridPoint(7, 4), const GridPoint(6, 4)];
    game.previousSnake = List.of(game.snake);
    game.direction = Direction.right;
    game.foods = [
      const FoodItem(position: GridPoint(0, 4), type: FoodType.apple),
    ];

    final choice = AutoPlayer.chooseDirection(game);
    expect(choice, isNot(Direction.right));
  });

  test('does not steer into its own body', () {
    final game = engine(mode: GameMode.classic);
    game.start();
    // (5,6) sits directly below the head and is a *middle* segment, so
    // it will still be there next tick.
    game.snake = [
      const GridPoint(5, 5),
      const GridPoint(4, 5),
      const GridPoint(4, 6),
      const GridPoint(5, 6),
      const GridPoint(6, 6),
    ];
    game.previousSnake = List.of(game.snake);
    game.direction = Direction.right;
    game.foods = [
      const FoodItem(position: GridPoint(5, 9), type: FoodType.apple),
    ];

    // Down is the greedy choice but it's occupied, so it must pick
    // something else.
    expect(AutoPlayer.chooseDirection(game), isNot(Direction.down));
  });

  test('will follow its own tail, which vacates as it moves', () {
    final game = engine(mode: GameMode.classic);
    game.start();
    // Same shape, but now the cell below the head is the last segment.
    // Chasing it is legal — the engine applies the same rule in tick().
    game.snake = [
      const GridPoint(5, 5),
      const GridPoint(4, 5),
      const GridPoint(4, 6),
      const GridPoint(5, 6),
    ];
    game.previousSnake = List.of(game.snake);
    game.direction = Direction.right;
    game.foods = [
      const FoodItem(position: GridPoint(5, 9), type: FoodType.apple),
    ];

    expect(AutoPlayer.chooseDirection(game), Direction.down);
  });

  test('returns null when every move is fatal', () {
    final game = engine(mode: GameMode.classic, columns: 5, rows: 5);
    game.start();
    // Head in the corner: wall above and left, and the cell below is a
    // middle segment rather than the vacating tail.
    game.snake = [
      const GridPoint(0, 0),
      const GridPoint(1, 0),
      const GridPoint(2, 0),
      const GridPoint(2, 1),
      const GridPoint(1, 1),
      const GridPoint(0, 1),
      const GridPoint(0, 2),
    ];
    game.previousSnake = List.of(game.snake);
    game.direction = Direction.left;

    expect(AutoPlayer.chooseDirection(game), isNull);
  });

  test('keeps a demo alive for a long stretch', () {
    final game = engine();
    game.start();
    var survived = 0;
    for (var i = 0; i < 300; i++) {
      final next = AutoPlayer.chooseDirection(game);
      if (next != null) game.queueTurn(next);
      game.tick();
      if (game.phase != GamePhase.running) break;
      survived++;
    }
    // The attract demo shouldn't die in the first few seconds on an
    // open wrapping board.
    expect(survived, greaterThan(100));
  });
}
