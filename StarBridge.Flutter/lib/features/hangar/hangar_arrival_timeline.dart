/// Scan-scoped arrival timestamps. Survives list virtualization and live/preview layout changes.
class HangarArrivalTimeline {
  HangarArrivalTimeline({this.now});
  final Duration Function()? now;
  final Stopwatch _clock = Stopwatch()..start();
  Duration get _time => now?.call() ?? _clock.elapsed;
  String? _operation;
  final Map<String, Duration> _arrivals = {};
  bool active = true;

  static String rowId(Map ship, int index) =>
      ship['rowId'] as String? ?? 'ship-$index';
  void accept(Map<String, Object?> view, {String? phase}) {
    final operation = view['operationId'] as String?;
    if (_operation != operation) {
      _operation = operation;
      _arrivals.clear();
    }
    active =
        phase == null ||
        const [
          'reading',
          'verifying',
          'complete',
          'needsReview',
        ].contains(phase);
    if (!active) return;
    final ships = view['ships'] as List? ?? const [];
    for (var i = 0; i < ships.length; i++) {
      _arrivals.putIfAbsent(rowId(ships[i] as Map, i), () => _time);
    }
  }

  Duration elapsed(String rowId) {
    final start = _arrivals[rowId];
    return start == null || !active ? const Duration(days: 1) : _time - start;
  }
}
