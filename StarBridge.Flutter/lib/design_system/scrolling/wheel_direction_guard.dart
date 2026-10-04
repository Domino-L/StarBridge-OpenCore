/// Mirrors WPF WheelDirectionBounceGuard. A single rapid reverse pulse brakes;
/// a second reverse pulse confirms the user's intent rather than being lost.
class WheelDirectionGuard {
  int _direction = 0, _time = 0, _pending = 0, _pendingTime = 0;

  bool accept(
    double delta,
    int milliseconds, {
    required bool moving,
    required bool boundary,
  }) {
    final direction = delta.sign.toInt();
    if (direction == 0) return true;
    if (milliseconds - _pendingTime > 90) _pending = 0;
    if (_direction != 0 &&
        direction != _direction &&
        !(_pending == direction && milliseconds - _pendingTime <= 90) &&
        milliseconds - _time <= 55 &&
        (moving || boundary)) {
      _pending = direction;
      _pendingTime = milliseconds;
      return false;
    }
    _direction = direction;
    _time = milliseconds;
    _pending = 0;
    return true;
  }

  void reset() {
    _direction = 0;
    _pending = 0;
  }
}
