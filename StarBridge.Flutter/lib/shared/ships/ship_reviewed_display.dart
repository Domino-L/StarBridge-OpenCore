/// Optional, versioned Host display overlay. Never serialized into owned inventory.
class ShipReviewedDisplay {
  const ShipReviewedDisplay({
    required this.category,
    required this.sizeClass,
    required this.domain,
    this.iconKey,
  });
  final String category, sizeClass, domain;
  final String? iconKey;
  bool get isGround => domain == 'ground';
  String get role => isGround ? 'ground-$category' : category;
  String get spec => isGround ? 'ground-$sizeClass' : sizeClass;

  static ShipReviewedDisplay? parse(Object? value) {
    if (value is! Map) return null;
    final category = value['category'],
        size = value['sizeClass'],
        domain = value['domain'],
        icon = value['iconKey'];
    if (!const [
          'combat',
          'transport',
          'industrial',
          'exploration',
          'support',
          'competition',
          'multi-role',
        ].contains(category) ||
        !const ['small', 'medium', 'large', 'capital'].contains(size) ||
        !const ['spacecraft', 'ground', 'flying-utility'].contains(domain) ||
        domain == 'ground' && size == 'capital' ||
        icon != null &&
            (icon is! String ||
                !RegExp(r'^[a-z][a-z-]{0,95}$').hasMatch(icon))) {
      return null;
    }
    return ShipReviewedDisplay(
      category: category as String,
      sizeClass: size as String,
      domain: domain as String,
      iconKey: icon as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'category': category,
    'sizeClass': sizeClass,
    'domain': domain,
    'iconKey': iconKey,
  };
}

/// Shared CN/TW/EN broad labels. No slash subtypes or inference from icon shape.
const shipCategoryLabels = <String, (String, String, String)>{
  'combat': ('战斗', '戰鬥', 'Combat'),
  'transport': ('运输', '運輸', 'Transport'),
  'industrial': ('工业', '工業', 'Industrial'),
  'exploration': ('探索', '探索', 'Exploration'),
  'support': ('支援', '支援', 'Support'),
  'competition': ('竞赛', '競賽', 'Competition'),
  'multi-role': ('多用途', '多用途', 'Multi-role'),
  'ground-combat': ('地面战斗', '地面戰鬥', 'Ground combat'),
  'ground-transport': ('地面运输', '地面運輸', 'Ground transport'),
  'ground-industrial': ('地面工业', '地面工業', 'Ground industrial'),
  'ground-exploration': ('地面探索', '地面探索', 'Ground exploration'),
  'ground-support': ('地面支援', '地面支援', 'Ground support'),
  'ground-competition': ('地面竞赛', '地面競賽', 'Ground competition'),
};
const shipGroundSizeLabels = <String, (String, String, String)>{
  'ground-small': ('轻型载具', '輕型載具', 'Light vehicle'),
  'ground-medium': ('中型载具', '中型載具', 'Medium vehicle'),
  'ground-large': ('重型载具', '重型載具', 'Heavy vehicle'),
};
