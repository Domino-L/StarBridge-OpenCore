import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';

import 'menu_friends_session_test.dart' show Port, ready;

void main() {
  testWidgets(
    'background refresh skips identical views, never changed or reopened ones',
    (tester) async {
      final port = Port(), views = <Map<String, Object?>>[];
      final session = MenuFriendsSession(port, views.add);
      session.show(true);
      port.reads.last.complete(ready('Alpha'));
      await tester.pump();
      final shown = views.length;
      expect(views.last.toString(), contains('Alpha'));

      await tester.pump(const Duration(seconds: 10));
      expect(port.reads, hasLength(2), reason: 'silent refresh still reads');
      port.reads.last.complete(ready('Alpha'));
      await tester.pump();
      expect(views, hasLength(shown), reason: 'identical refresh not resent');

      await tester.pump(const Duration(seconds: 10));
      port.reads.last.complete(ready('Beta'));
      await tester.pump();
      expect(views, hasLength(shown + 1));
      expect(views.last.toString(), contains('Beta'));

      await tester.pump(const Duration(seconds: 10));
      port.reads.last.complete(ready('Beta', presence: 'InGame'));
      await tester.pump();
      expect(views, hasLength(shown + 2), reason: 'presence change is sent');

      // A new menu opening always receives the current view again.
      session.show(false);
      final hidden = views.length;
      session.show(true);
      port.reads.last.complete(ready('Beta', presence: 'InGame'));
      await tester.pump();
      expect(views.length, greaterThan(hidden));
      expect(views.last.toString(), contains('Beta'));

      session.show(false);
      session.dispose();
    },
  );
}
