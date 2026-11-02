/// Local menu presentation. Legacy fractional coordinates remain on the wire
/// for compatibility; the current widget layout is fixed below the clock.
final class MenuDesktopWidgets {
  const MenuDesktopWidgets({this.hangar = true, this.x = .04, this.y = .18});
  final bool hangar;
  final double x, y;
  static MenuDesktopWidgets? parse(Object? raw) {
    if (raw == null) return const MenuDesktopWidgets();
    if (raw is! Map ||
        raw.length != 2 ||
        raw['hangar'] is! bool ||
        raw['position'] is! List) {
      return null;
    }
    final position = raw['position'] as List;
    if (position.length != 2 ||
        position.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
      return null;
    }
    return MenuDesktopWidgets(
      hangar: raw['hangar'],
      x: (position[0] as num).toDouble(),
      y: (position[1] as num).toDouble(),
    );
  }

  Map<String, Object?> toMap() => {
    'hangar': hangar,
    'position': [x, y],
  };
  MenuDesktopWidgets copyWith({bool? hangar, double? x, double? y}) =>
      MenuDesktopWidgets(
        hangar: hangar ?? this.hangar,
        x: x ?? this.x,
        y: y ?? this.y,
      );
}
