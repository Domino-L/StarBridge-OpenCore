import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_profile_rules.dart';

import 'community_profile_dialog_test.dart' show EditorPort, open, enter, save;

void main() {
  testWidgets(
    'organization name is editable above logo text and uses profile save',
    (tester) async {
      final port = EditorPort();
      final published = <String>[];
      await open(
        tester,
        port,
        onNameConfirmed: (code, name) => published.add('$code:$name'),
      );
      Finder field(String name) => find.byWidgetPredicate(
        (w) => w is TextFormField && w.key.toString().contains('-$name'),
      );
      expect(field('name'), findsOneWidget);
      expect(
        tester.getTopLeft(field('name')).dy,
        lessThan(tester.getTopLeft(field('logoText')).dy),
      );
      expect(
        tester.widget<TextFormField>(field('name')).initialValue,
        'Organization A',
      );
      await enter(tester, 'name', '星海 Équipe 探索');
      await save(tester);
      expect(port.saves.single, {'name': '星海 Équipe 探索'});
      expect(published, ['A:星海 Équipe 探索']);
    },
  );
  test(
    'organization names accept Unicode but not empty or oversized names',
    () {
      expect(communityProfileTextFits('name', '星海 Équipe 探索'), isTrue);
      expect(communityProfileTextFits('name', ' '), isFalse);
      expect(communityProfileTextFits('name', '船' * 33), isFalse);
      expect(communityProfileTextFits('name', 'A\nB'), isFalse);
    },
  );
}
