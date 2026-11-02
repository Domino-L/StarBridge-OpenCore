// CX-T11: SCM's 403 means "forbidden" unless it says the scope is missing, so
// a forbidden answer never sends the user to sign in or reauthorize.
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_errors.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_profile_copy.dart';

void main() {
  test('forbidden is not a reauthorization', () {
    expect(tradeProfileNeedsReauthorize('marketplace.forbidden'), isFalse);
    expect(
      tradeProfileNeedsReauthorize('marketplace.reauthorize_required'),
      isTrue,
    );
    expect(tradeProfileCopy['marketplace.forbidden']!.first, contains('拒绝'));
    expect(
      listingErrors['marketplace.forbidden']!.first,
      isNot(contains('登录')),
    );
  });
}
