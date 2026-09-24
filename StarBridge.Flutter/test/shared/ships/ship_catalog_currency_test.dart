import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/ships/ship_catalog_display.dart';

void main() {
  test('USD wire amounts have one dollar sign and shared grouping', () {
    for (final raw in [
      '1234.5',
      r'$1,234.50',
      '1234.50 USD',
      r'$1,234.50 USD',
    ]) {
      expect(ShipCatalogDisplay.usdCents(raw), 123450);
      expect(ShipCatalogDisplay.usdText(raw), r'$1,234.50');
    }
    expect(ShipCatalogDisplay.usdText('0'), r'$0');
    expect(ShipCatalogDisplay.usdText('1000'), r'$1,000');
  });

  test('unknown, invalid and other currencies do not become priced', () {
    for (final raw in [
      null,
      '',
      'unknown',
      '—',
      '-1',
      'NaN',
      'Infinity',
      r'$$50',
      '50 EUR',
      '¥50',
      '1000000001',
    ]) {
      expect(ShipCatalogDisplay.usdText(raw), isNull, reason: '$raw');
    }
  });
}
