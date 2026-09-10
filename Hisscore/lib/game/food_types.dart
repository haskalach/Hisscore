import 'snake_engine.dart';

/// Types of collectible food that appear on the board.
enum FoodType {
  /// Standard apple: +10 points, snake grows by 1.
  apple,

  /// High-value star: +50 points, no growth. Despawns after a timeout.
  star,

  /// Shield pickup: pass through one wall or obstacle collision. Despawns.
  shield,

  /// Speed burst: doubles tick speed for ~3 seconds. Despawns.
  speedBurst,

  /// Shrink potion: snake loses up to 2 tail segments. Despawns.
  shrink,

  /// Magnet: pulls every other food item one step closer each tick
  /// for a short while. Despawns.
  magnet;

  /// Whether eating this type causes the snake to grow by one segment.
  bool get growsSnake => this == FoodType.apple;

  /// Display label for UI.
  String get label => switch (this) {
    FoodType.apple => 'APPLE',
    FoodType.star => 'STAR',
    FoodType.shield => 'SHIELD',
    FoodType.speedBurst => 'SPEED',
    FoodType.shrink => 'SHRINK',
    FoodType.magnet => 'MAGNET',
  };
}

/// A single collectible item on the game board.
class FoodItem {
  const FoodItem({
    required this.position,
    required this.type,
    this.spawnTick = 0,
    this.lifetime,
  });

  /// Grid position of this item.
  final GridPoint position;

  /// What kind of food this is.
  final FoodType type;

  /// The tick count when this item was spawned.
  final int spawnTick;

  /// How many ticks this item lives before despawning.
  /// `null` means it stays until eaten (apples).
  final int? lifetime;

  /// Whether this food has expired at the given tick count.
  bool isExpired(int currentTick) {
    if (lifetime == null) return false;
    return currentTick - spawnTick >= lifetime!;
  }

  /// Fraction of lifetime remaining (1.0 = just spawned, 0.0 = about to expire).
  double lifeFraction(int currentTick) {
    if (lifetime == null) return 1.0;
    final elapsed = currentTick - spawnTick;
    return (1.0 - elapsed / lifetime!).clamp(0.0, 1.0);
  }
}
