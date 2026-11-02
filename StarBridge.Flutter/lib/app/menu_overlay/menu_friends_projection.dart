import 'dart:convert';

import '../../platform/window/menu_read_feedback.dart';

import 'menu_friend_details.dart';

typedef MenuFriend = ({
  String name,
  String presence,
  String? key,
  String? avatar,
});

final class MenuFriendsView {
  const MenuFriendsView(
    this.state, {
    this.incoming = 0,
    this.rows = const [],
    this.requests = const [],
    this.identity,
    this.scope = '',
    this.interactive = false,
    this.busy = false,
    this.refreshing = false,
    this.readFeedback,
    this.requiresRefresh = false,
    this.section = 'friends',
    this.query = '',
    this.feedback = '',
    this.actions = const {},
    this.chatKeys = const {},
    this.self,
    this.confirmation,
    this.details = const {},
    this.gameIds = const {},
    this.matched = 0,
    this.notAddable = const {},
    this.canEnterOffline = false,
    this.canRestoreOnline = false,
  });
  final String state;
  final bool canEnterOffline;
  final bool canRestoreOnline;
  final String scope;
  final int incoming;
  final List<MenuFriend> rows;
  final List<MenuFriend> requests;
  final Map<String, MenuFriendDetails> details;
  final Map<String, String> gameIds;

  /// In a search, how many of the first rows are friends it also applies to.
  final int matched;
  final Set<String> notAddable;
  final ({String name, String handle, String? avatar})? identity;
  final bool interactive, busy, requiresRefresh;
  final bool refreshing;
  final MenuReadFeedback? readFeedback;
  final String section, query, feedback;
  final Map<String, List<String>> actions;
  final Set<String> chatKeys;
  final ({String key, String status, bool change, bool busy, bool failed})?
  self;
  final ({String token, String name, String action})? confirmation;
  static const commandNames = {
    'send',
    'accept',
    'reject',
    'cancel',
    'remove',
    'block',
    'unblock',
  };
  static MenuFriendsView parse(Object? wire) {
    try {
      if (wire is! String || wire.length > 1048576) {
        throw const FormatException();
      }
      final data = jsonDecode(wire);
      if (data is! Map ||
          !const [
            'idle',
            'loading',
            'ready',
            'signedOut',
            'unavailable',
          ].contains(data['state'])) {
        throw const FormatException();
      }
      final interactive = data['interactive'] == true;
      final scope = data['scope'] ?? '';
      if (scope is! String ||
          (scope.isNotEmpty &&
              !RegExp(r'^friends[0-9]{1,13}$').hasMatch(scope))) {
        throw const FormatException();
      }
      final section = interactive ? data['section'] : 'friends';
      final query = interactive ? data['query'] : '';
      final feedback = interactive ? data['feedback'] : '';
      final busy = interactive ? data['busy'] : false;
      final refresh = interactive ? data['requiresRefresh'] : false;
      final allowed = <String, List<String>>{};
      ({String token, String name, String action})? confirmation;
      if (!const {
            'friends',
            'incoming',
            'outgoing',
            'blocked',
            'search',
          }.contains(section) ||
          query is! String ||
          query.length > 128 ||
          feedback is! String ||
          !{
            '',
            'invalidSearch',
            'expired',
            'rejected',
            'unknown',
            'reviewed',
            for (final action in commandNames) 'success.$action',
          }.contains(feedback) ||
          busy is! bool ||
          refresh is! bool) {
        throw const FormatException();
      }
      if (interactive) {
        final raw = data['actions'];
        if (raw is! Map || raw.length > 5000) throw const FormatException();
        for (final entry in raw.entries) {
          if (entry.key is! String ||
              (entry.key as String).isEmpty ||
              (entry.key as String).length > 64 ||
              entry.value is! List ||
              (entry.value as List).length > 7 ||
              (entry.value as List).any((v) => !commandNames.contains(v))) {
            throw const FormatException();
          }
          allowed[entry.key as String] = List<String>.unmodifiable(
            entry.value as List,
          );
        }
        final pending = data['confirmation'];
        if (pending != null) {
          if (pending is! Map ||
              pending['token'] is! String ||
              !RegExp(r'^confirm[1-9][0-9]{0,12}$')
                  .hasMatch(pending['token'] as String) ||
              pending['name'] is! String ||
              (pending['name'] as String).length > 128 ||
              !commandNames.contains(pending['action'])) {
            throw const FormatException();
          }
          confirmation = (
            token: pending['token'] as String,
            name: pending['name'] as String,
            action: pending['action'] as String,
          );
        }
      }
      final ready = data['state'] == 'ready';
      final rows = ready ? data['rows'] : const [],
          incoming = ready ? data['incoming'] : 0;
      if (rows is! List ||
          rows.length > 5000 ||
          incoming is! int ||
          incoming < 0) {
        throw const FormatException();
      }
      final parsed = [for (final row in rows) _row(row)];
      final matched = ready ? data['matched'] ?? 0 : 0;
      if (matched is! int || matched < 0 || matched > parsed.length) {
        throw const FormatException();
      }
      final details = <String, MenuFriendDetails>{};
      final gameIds = <String, String>{};
      final notAddable = <String>{};
      final listed = section == 'friends' || section == 'search';
      for (var i = 0; i < parsed.length; i++) {
        final row = parsed[i];
        final raw = rows[i] as Map;
        if (raw['notAddable'] == true && row.key != null) {
          notAddable.add(row.key!);
        }
        if (listed && row.key != null) {
          final gameId = raw['gameId'];
          if (gameId != null) {
            if (gameId is! String ||
                gameId.length > 128 ||
                gameId.runes.any((code) => code < 32 || code == 127)) {
              throw const FormatException();
            }
            gameIds[row.key!] = gameId;
          }
        }
        if (row.presence == 'inGame' && row.key != null && listed) {
          final detail = MenuFriendDetails.parse(
            raw['details'],
            raw['detailLabels'],
          );
          if (detail != null) details[row.key!] = detail;
        }
      }
      final requests = ready ? data['requests'] ?? const [] : const [];
      if (requests is! List || requests.length + rows.length > 5000) {
        throw const FormatException();
      }
      final parsedRequests = [for (final row in requests) _row(row)];
      final keys = <String>{};
      if ([
        ...parsed,
        ...parsedRequests,
      ].any((r) => r.key != null && !keys.add(r.key!))) {
        throw const FormatException();
      }
      final chats = data['chatKeys'] ?? const [];
      if (chats is! List ||
          chats.length > 5000 ||
          chats.any((key) => key is! String || !keys.contains(key))) {
        throw const FormatException();
      }
      final own = data['self'];
      final identity = data['identity'];
      MenuFriend? identityRow;
      if (identity != null) {
        if (identity is! Map ||
            identity['handle'] is! String ||
            (identity['handle'] as String).length > 128) {
          throw const FormatException();
        }
        identityRow = _row({...identity, 'key': null, 'presence': 'unknown'});
      }
      if (own != null &&
          (own is! Map ||
              own['key'] is! String ||
              !RegExp(r'^self[0-9]{1,13}$').hasMatch(own['key'] as String) ||
              !const {
                'presence.online',
                'presence.inGame',
                'presence.away',
                'presence.offline',
                'presence.unknown',
                'presence.invisible',
                'presence.manualOffline',
              }.contains(own['status']) ||
              own['change'] is! bool ||
              own['busy'] is! bool ||
              own['failed'] is! bool)) {
        throw const FormatException();
      }
      if (data.containsKey('canEnterOffline') &&
          data['canEnterOffline'] is! bool) {
        throw const FormatException();
      }
      if (data.containsKey('canRestoreOnline') &&
          data['canRestoreOnline'] is! bool) {
        throw const FormatException();
      }
      return MenuFriendsView(
        data['state'] as String,
        incoming: incoming,
        canEnterOffline: data['canEnterOffline'] == true,
        canRestoreOnline: data['canRestoreOnline'] == true,
        scope: scope,
        rows: List.unmodifiable(parsed),
        details: Map.unmodifiable(details),
        gameIds: Map.unmodifiable(gameIds),
        matched: matched,
        notAddable: Set.unmodifiable(notAddable),
        requests: List.unmodifiable(parsedRequests),
        identity: identityRow == null
            ? null
            : (
                name: identityRow.name,
                handle: identity['handle'] as String,
                avatar: identityRow.avatar,
              ),
        interactive: interactive,
        section: section as String,
        query: query,
        feedback: feedback,
        busy: busy,
        refreshing: data['refreshing'] == true,
        readFeedback: MenuReadFeedback.parse(data['readFeedback']),
        requiresRefresh: refresh,
        actions: Map.unmodifiable(allowed),
        confirmation: confirmation,
        chatKeys: Set<String>.unmodifiable(chats.cast<String>()),
        self: own == null
            ? null
            : (
                key: own['key'] as String,
                status: own['status'] as String,
                change: own['change'] as bool,
                busy: own['busy'] as bool,
                failed: own['failed'] as bool,
              ),
      );
    } on Object {
      return const MenuFriendsView('unavailable');
    }
  }

  static MenuFriend _row(dynamic row) {
    if (row is! Map ||
        row['name'] is! String ||
        (row['name'] as String).length > 128 ||
        !const [
          'inGame',
          'online',
          'away',
          'offline',
          'unknown',
        ].contains(row['presence'])) {
      throw const FormatException();
    }
    final key = row['key'], avatar = row['avatar'];
    if ((key != null && (key is! String || key.isEmpty || key.length > 64)) ||
        (avatar != null &&
            (avatar is! String ||
                avatar.length > 128 * 1024 ||
                !(avatar.startsWith('data:image/png;base64,') ||
                    avatar.startsWith('data:image/jpeg;base64,'))))) {
      throw const FormatException();
    }
    return (
      name: row['name'] as String,
      presence: row['presence'] as String,
      key: key as String?,
      avatar: avatar as String?,
    );
  }
}
