import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/friend_request_refresh.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';

import '../features/friends/friends_test.dart' show PendingPort, directory, row;

FriendsReadResult incoming(int count, {String? query}) => FriendsReadResult(
  FriendsReadState.ready,
  snapshot: parseFriendsSnapshot(
    directory(query: query)
      ..['incoming'] = [
        for (var i = 0; i < count; i++)
          row('Request $i')..['relationship'] = 'incoming',
      ],
  ),
);
void main() {
  testWidgets(
    'off-page requests survive transient failures; confirmed handling/account switch clear',
    (tester) async {
      final account = ValueNotifier(
        const AccountProjection.loading().copyWith(
          sessionState: AccountSessionState.signedIn,
          operation: AccountOperation.none,
          generation: 1,
        ),
      );
      final port = PendingPort();
      final attention = FriendRequestRefresh(port, account);
      await tester.pump(const Duration(milliseconds: 1));
      expect(port.queries, [null]);
      port.requests.last.complete(incoming(2));
      await tester.pump();
      expect(attention.count.value, 2);
      await tester.pump(const Duration(seconds: 15));
      port.requests.last.complete(
        const FriendsReadResult(FriendsReadState.unavailable),
      );
      await tester.pump();
      expect(attention.count.value, 2);
      await tester.pump(const Duration(seconds: 30));
      port.requests.last.complete(incoming(0));
      await tester.pump();
      expect(attention.count.value, 0);
      await tester.pump(const Duration(seconds: 15));
      final old = port.requests.last;
      account.value = account.value.copyWith(generation: 2);
      old.complete(incoming(8));
      await tester.pump();
      expect(attention.count.value, 0);
      account.value = account.value.copyWith(
        sessionState: AccountSessionState.signedOut,
      );
      attention.dispose();
      account.dispose();
      await tester.pump();
    },
  );
  test(
    'friends UI search and failed refresh do not acknowledge requests',
    () async {
      final port = PendingPort();
      final module = FriendsModule(port);
      var reading = module.refresh();
      port.requests.last.complete(incoming(2));
      await reading;
      expect(module.incomingAttention.value, 2);
      module.editQuery('search');
      expect(module.incomingAttention.value, 2);
      reading = module.refresh();
      port.requests.last.complete(incoming(0, query: 'search'));
      await reading;
      expect(module.incomingAttention.value, 2);
      module.editQuery('');
      port.requests.last.complete(
        const FriendsReadResult(FriendsReadState.unavailable),
      );
      await Future<void>.delayed(Duration.zero);
      expect(module.incomingAttention.value, 2);
      reading = module.refresh();
      port.requests.last.complete(incoming(0));
      await reading;
      expect(module.incomingAttention.value, 0);
      module.dispose();
    },
  );
}
