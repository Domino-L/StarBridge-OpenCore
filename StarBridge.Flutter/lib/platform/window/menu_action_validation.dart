/// Strict menu-surface intents, before dispatching into an account-owned lease.
bool validMenuFriendsAction(Object? args, int? opening) =>
    args is Map &&
    args['opening'] == opening &&
    const {
      'prepare',
      'confirm',
      'dismiss',
      'refresh',
      'section',
      'search',
      'presence',
    }.contains(args['action']) &&
    args['key'] is String &&
    (args['key'] as String).length <= 64 &&
    args['value'] is String &&
    (args['value'] as String).length <= 128;

bool validMenuCommsCompose(Object? args, int? opening) =>
    args is Map &&
    args['opening'] == opening &&
    args['action'] is String &&
    const {'edit', 'send', 'check'}.contains(args['action']) &&
    args['key'] is String &&
    (args['key'] as String).length <= 64 &&
    args['text'] is String &&
    (args['text'] as String).length <= 1000 &&
    args['revision'] is int &&
    (args['revision'] as int) >= 0 &&
    (args['revision'] as int) <= 1000000000;
