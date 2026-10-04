/// Local presentation only. Tool visibility never grants or revokes authority.
final class MenuToolbarPreferences {
  const MenuToolbarPreferences({
    this.order = ids,
    this.hidden = const [],
    this.density = 'standard',
    this.labels = 'auto',
    this.showUnreadBadges = true,
  });
  static const ids = [
    'hud',
    'organizations',
    'friends',
    'comms',
    'rooms',
    'screenshot',
    'image',
    'browser',
  ];
  final List<String> order, hidden;
  final String density, labels;
  final bool showUnreadBadges;
  static MenuToolbarPreferences? parse(Object? raw) {
    if (raw == null) return const MenuToolbarPreferences();
    if (raw is! Map ||
        (raw.length != 4 && raw.length != 5) ||
        raw.keys.any(
          (key) => !const {
            'order',
            'hidden',
            'density',
            'labels',
            'showUnreadBadges',
          }.contains(key),
        ) ||
        (raw.containsKey('showUnreadBadges') &&
            raw['showUnreadBadges'] is! bool) ||
        raw['order'] is! List ||
        raw['hidden'] is! List ||
        !const {
          'compact',
          'standard',
          'comfortable',
        }.contains(raw['density']) ||
        !const {'auto', 'iconsOnly'}.contains(raw['labels'])) {
      return null;
    }
    final order = raw['order'] as List, hidden = raw['hidden'] as List;
    if (order.length != ids.length ||
        order.toSet().length != ids.length ||
        order.any((id) => !ids.contains(id)) ||
        hidden.length >= ids.length ||
        hidden.toSet().length != hidden.length ||
        hidden.any((id) => id == 'hud' || !ids.contains(id))) {
      return null;
    }
    return MenuToolbarPreferences(
      order: List<String>.unmodifiable(order),
      hidden: List<String>.unmodifiable(hidden),
      density: raw['density'] as String,
      labels: raw['labels'] as String,
      showUnreadBadges: raw['showUnreadBadges'] as bool? ?? true,
    );
  }

  Map<String, Object?> toMap() => {
    'order': order,
    'hidden': hidden,
    'density': density,
    'labels': labels,
    'showUnreadBadges': showUnreadBadges,
  };
  MenuToolbarPreferences copyWith({
    List<String>? order,
    List<String>? hidden,
    String? density,
    String? labels,
    bool? showUnreadBadges,
  }) => MenuToolbarPreferences(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    density: density ?? this.density,
    labels: labels ?? this.labels,
    showUnreadBadges: showUnreadBadges ?? this.showUnreadBadges,
  );
}
