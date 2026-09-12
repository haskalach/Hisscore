import 'package:flutter_test/flutter_test.dart';
import 'package:hisscore/game/level.dart';
import 'package:hisscore/game/snake_engine.dart';

void main() {
  const cols = 20;
  const rows = 20;

  group('progression', () {
    test('asks for more apples as levels climb', () {
      expect(
        LevelData.applesRequired(2),
        greaterThan(LevelData.applesRequired(1)),
      );
    });

    test('speeds up as levels climb', () {
      expect(
        LevelData.speedMultiplier(5),
        greaterThan(LevelData.speedMultiplier(1)),
      );
      expect(LevelData.speedMultiplier(1), 1.0);
    });

    test('the first levels are deliberately empty', () {
      for (var level = 1; level <= 3; level++) {
        expect(
          LevelData.obstaclesForLevel(level, cols, rows),
          isEmpty,
          reason: 'level $level should still be open board',
        );
      }
    });

    test('every level from 4 on has obstacles', () {
      for (var level = 4; level <= 20; level++) {
        expect(
          LevelData.obstaclesForLevel(level, cols, rows),
          isNotEmpty,
          reason: 'level $level should place something',
        );
      }
    });
  });

  group('every pattern stays on the board', () {
    test('no obstacle sits outside the grid', () {
      for (var level = 4; level <= 20; level++) {
        for (final point in LevelData.obstaclesForLevel(level, cols, rows)) {
          expect(
            point.x >= 0 && point.x < cols && point.y >= 0 && point.y < rows,
            isTrue,
            reason: 'level $level put $point off the board',
          );
        }
      }
    });

    test('patterns hold up on a tall phone-shaped grid', () {
      // The board is no longer square, so patterns get non-square grids.
      const tallRows = 43;
      for (var level = 4; level <= 20; level++) {
        final obstacles = LevelData.obstaclesForLevel(level, cols, tallRows);
        expect(obstacles, isNotEmpty, reason: 'level $level went empty');
        for (final point in obstacles) {
          expect(
            point.x >= 0 &&
                point.x < cols &&
                point.y >= 0 &&
                point.y < tallRows,
            isTrue,
            reason: 'level $level put $point off a tall board',
          );
        }
      }
    });

    test('patterns survive a cramped grid without escaping it', () {
      const small = 8;
      for (var level = 4; level <= 20; level++) {
        for (final point in LevelData.obstaclesForLevel(level, small, small)) {
          expect(
            point.x >= 0 && point.x < small && point.y >= 0 && point.y < small,
            isTrue,
            reason: 'level $level put $point off a small board',
          );
        }
      }
    });
  });

  group('safeObstacles', () {
    test('clears a buffer around every snake segment', () {
      final snake = [
        const GridPoint(5, 5),
        const GridPoint(4, 5),
        const GridPoint(3, 5),
      ];
      // A solid block covering the snake and its surroundings.
      final raw = <GridPoint>{
        for (var x = 0; x < cols; x++)
          for (var y = 0; y < rows; y++) GridPoint(x, y),
      };

      final safe = LevelData.safeObstacles(raw, snake, cols, rows);

      for (final segment in snake) {
        expect(safe.contains(segment), isFalse);
        // And the cells immediately around it, so the snake has room.
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            expect(
              safe.contains(GridPoint(segment.x + dx, segment.y + dy)),
              isFalse,
              reason: 'no breathing room beside $segment',
            );
          }
        }
      }
    });

    test('drops anything outside the grid', () {
      final raw = <GridPoint>{
        const GridPoint(-1, 5),
        const GridPoint(5, -1),
        GridPoint(cols, 5),
        GridPoint(5, rows),
        const GridPoint(10, 10),
      };

      final safe = LevelData.safeObstacles(raw, [], cols, rows);
      expect(safe, {const GridPoint(10, 10)});
    });
  });
}
