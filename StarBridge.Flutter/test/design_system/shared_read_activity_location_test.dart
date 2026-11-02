import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/social_read_activity.dart'
    as shared;
import 'package:starbridge_flutter/features/common/social_read_activity.dart'
    as legacy;

void main() {
  test('feature callers and shell share one read activity implementation', () {
    expect(legacy.SocialReadActivity, same(shared.SocialReadActivity));
    expect(
      legacy.SocialReadActivityBinding,
      same(shared.SocialReadActivityBinding),
    );
  });
}
