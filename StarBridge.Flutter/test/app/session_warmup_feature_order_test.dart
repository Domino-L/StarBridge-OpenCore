import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/session_warmup_listener.dart';

void main() {
  test('the marketplace badge read joins the warmup queue before achievements', () {
    // One bounded job at a time after account, hangar, friends and communities;
    // the trading hall badge must not run on its own post-login timer.
    expect(sessionWarmupFeatureIds, [
      'marketplace',
      'achievements',
      'party-rooms',
    ]);
  });
}
