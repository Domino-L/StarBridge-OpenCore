import 'friends_module.dart';

/// Isolated UI examples. Relations change only in this page's memory.
final class ExampleFriendsAdapter implements FriendsPort, FriendsCommandPort {
  final _people = [
    for (final entry in [
      'friend',
      'incoming',
      'outgoing',
      'blocked',
      'none',
    ].asMap().entries)
      FriendRow(
        ['示例好友', '示例申请', '示例邀请', '示例屏蔽', '示例用户'][entry.key],
        'Example',
        entry.value,
        DateTime.utc(2026, 9, 6, 12),
        targetRef: (entry.key + 1).toRadixString(16).padLeft(32, '0'),
        chatTargetRef: entry.value == 'friend'
            ? '00000000000000000000000000000001'
            : null,
        conversationKey: entry.value == 'friend' ? '1'.padLeft(64, '0') : null,
        actions: friendActionsFor(entry.value),
      ),
  ];
  @override
  bool get commandsAvailable => true;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<FriendsReadResult> read({String? query}) async => FriendsReadResult(
    FriendsReadState.ready,
    snapshot: FriendsSnapshot(
      groups: {
        for (final section in FriendsSection.values)
          section: query != null
              ? []
              : _people
                    .where(
                      (r) =>
                          r.relationship ==
                          (section == FriendsSection.friends
                              ? 'friend'
                              : section.name),
                    )
                    .toList(),
      },
      results: query == null
          ? []
          : _people
                .where(
                  (r) =>
                      r.relationship != 'blocked' &&
                      r.name.toLowerCase().contains(query.toLowerCase()),
                )
                .toList(),
      query: query,
      refreshedAt: query == null ? DateTime.utc(2026, 9, 6, 12) : null,
    ),
  );
  @override
  Future<FriendCommandResult> execute(String action, String targetRef) async {
    final index = _people.indexWhere((r) => r.targetRef == targetRef);
    if (index < 0 || !_people[index].actions.contains(action)) {
      return const FriendCommandResult('rejected', error: 'targetChanged');
    }
    final old = _people[index];
    final relation = switch (action) {
      'send' => 'outgoing',
      'accept' => 'friend',
      'block' => 'blocked',
      _ => 'none',
    };
    _people[index] = FriendRow(
      old.callsign,
      old.gameId,
      relation,
      old.updatedAt,
      targetRef: old.targetRef,
      chatTargetRef: relation == 'friend' ? old.targetRef : null,
      conversationKey: relation == 'friend' ? old.conversationKey : null,
      actions: friendActionsFor(relation),
    );
    return FriendCommandResult('accepted', directory: (await read()).snapshot);
  }

  @override
  void cancelPending() {}
  @override
  Future<void> close() async {}
}
