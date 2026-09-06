import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Controls a screen-shake effect that can be applied via [ScreenShake].
///
/// Call [shake] to trigger a decaying random offset. The controller notifies
/// listeners each frame so a wrapping widget can apply `Transform.translate`.
class ScreenShakeController extends ChangeNotifier {
  ScreenShakeController({Random? random}) : _random = random ?? Random();

  final Random _random;
  double _offsetX = 0;
  double _offsetY = 0;
  double _intensity = 0;
  Timer? _timer;

  double get offsetX => _offsetX;
  double get offsetY => _offsetY;

  /// Start shaking with the given [intensity] (pixels).
  void shake({double intensity = 6.0}) {
    _intensity = intensity;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_intensity < 0.3) {
        _offsetX = 0;
        _offsetY = 0;
        _intensity = 0;
        _timer?.cancel();
        notifyListeners();
        return;
      }
      _offsetX = (_random.nextDouble() * 2 - 1) * _intensity;
      _offsetY = (_random.nextDouble() * 2 - 1) * _intensity;
      _intensity *= 0.82;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Wraps a [child] and applies a random offset when the [controller] shakes.
class ScreenShake extends StatelessWidget {
  const ScreenShake({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScreenShakeController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Transform.translate(
          offset: Offset(controller.offsetX, controller.offsetY),
          child: child,
        );
      },
    );
  }
}
