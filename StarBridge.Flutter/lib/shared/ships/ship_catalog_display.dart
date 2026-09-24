/// Shared display rules for hangar and personal-page projections. No ownership,
/// network calls, stored inventory or current-market-price claims.
abstract final class ShipCatalogDisplay {
  static const categories = [
    'combat',
    'transport',
    'industrial',
    'exploration',
    'support',
    'competition',
    'multi-role',
    'ground-combat',
    'ground-transport',
    'ground-industrial',
    'ground-exploration',
    'ground-support',
    'ground-competition',
    'utility',
    'unknown',
  ];
  static String category(String? value) =>
      categories.contains(value) ? value! : 'unknown';
  static int? cents(num? value) =>
      value == null || !value.isFinite || value < 0 || value > 1e9
      ? null
      : (value * 100).round();
  static String? image(String? path) =>
      path != null &&
          RegExp(r'^assets/ships/[a-zA-Z0-9_-]+\.(?:png|jpg|jpeg|webp)$')
              .hasMatch(path)
      ? path
      : null;
  static String usd(int cents) {
    final parts = (cents / 100)
        .toStringAsFixed(cents % 100 == 0 ? 0 : 2)
        .split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return '\$$whole${parts.length > 1 ? '.${parts.last}' : ''}';
  }

  /// Normalize the existing USD wire field, not arbitrary currencies or labels.
  static int? usdCents(String? value) => cents(
    num.tryParse(
      (value ?? '')
          .trim()
          .replaceFirst(RegExp(r'^\$\s*'), '')
          .replaceFirst(RegExp(r'\s*USD$', caseSensitive: false), '')
          .replaceAll(',', '')
          .trim(),
    ),
  );

  static String? usdText(String? value) {
    final amount = usdCents(value);
    return amount == null ? null : usd(amount);
  }
}
