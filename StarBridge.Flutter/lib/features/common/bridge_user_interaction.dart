import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../friends/bridge_friends_adapter.dart';
import '../friends/friends_module.dart';
import '../personal_profile/bridge_personal_profile_adapter.dart';
import '../personal_profile/personal_profile_models.dart';
import 'user_interaction.dart';

final class BridgeUserInteraction implements UserInteractionPort {
  BridgeUserInteraction(this.session)
    : friends = BridgeFriendsAdapter(session) {
    subscription = session.events.listen(
      (event) {
        if (event.name == 'account.changed' ||
            event.name == 'bootstrap.invalidated') {
          epoch++;
          changes.add(null);
        }
      },
      onDone: () {
        if (!closed) {
          epoch++;
          changes.add(null);
        }
      },
    );
  }
  final BridgeClientSession session;
  final BridgeFriendsAdapter friends;
  final changes = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> subscription;
  bool closed = false;
  int epoch = 0;
  final _pending = <BridgeRequestOperation>{};
  Future<BridgeEnvelope> _await(BridgeRequestOperation operation) async {
    _pending.add(operation);
    try {
      return await operation.future;
    } finally {
      _pending.remove(operation);
    }
  }

  @override
  Stream<void> get invalidations => changes.stream;
  Future<Map<String, Object?>> request(String name, UserTarget target) async {
    final current = epoch;
    if (closed || !session.hostCapabilities.contains('users.interaction')) {
      throw const FormatException();
    }
    final account = await _await(
      session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      ),
    );
    if (closed ||
        current != epoch ||
        !hasRelayAccount(account) ||
        account.accountContext == null) {
      throw const FormatException();
    }
    final response = await _await(
      session.beginRequest(
        name,
        accountContext: account.accountContext,
        payload: {'schemaVersion': 1, ...target.payload},
      ),
    );
    if (closed || current != epoch) throw const FormatException();
    return response.payload;
  }

  @override
  Future<PersonalProfileSnapshot> profile(UserTarget target) async {
    try {
      final data = await request('users.profile', target);
      if (data['editable'] != false) throw const FormatException();
      return parsePersonalProfileSnapshot(data);
    } on BridgeClientException catch (error) {
      return PersonalProfileSnapshot.unavailable(
        failureKey: switch (error.code) {
          'profile.visitor_not_visible' => 'profile.visitor.notVisible',
          'users.targetChanged' ||
          'communities.refreshRequired' => 'profile.visitor.refreshSource',
          'account.reauthorization_required' =>
            'profile.visitor.accountRequired',
          'bridge.timeout' => 'profile.visitor.readTimeout',
          _ => 'profile.error.unavailable',
        },
      );
    } on Object catch (error) {
      return PersonalProfileSnapshot.unavailable(
        failureKey:
            error is FormatException ||
                error is BridgeFormatException ||
                error is TypeError
            ? 'profile.error.invalidResponse'
            : 'profile.error.unavailable',
      );
    }
  }

  @override
  Future<FriendRow?> social(UserTarget target) async {
    final snapshot = parseFriendsSnapshot(
      await request('users.social', target),
      avatarContext: true,
    );
    final rows = [
      ...snapshot.results,
      ...snapshot.groups.values.expand((v) => v),
    ];
    return rows.length == 1 ? rows.single : null;
  }

  @override
  Future<FriendCommandResult> execute(String action, String reference) =>
      friends.execute(action, reference);
  @override
  Future<void> close() async {
    closed = true;
    epoch++;
    await Future.wait(_pending.toList().map((operation) => operation.cancel()));
    await subscription.cancel();
    await friends.close();
    await changes.close();
  }
}
