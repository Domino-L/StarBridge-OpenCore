import 'dart:async';

/// Display provenance only. Neither origin nor request serial grants an action,
/// read permission, freshness, result, or an account/transport identity.
enum MenuReadOrigin { programmatic, pointer, keyboard }

/// Known read-capable intents only; opaque feature grants complete through
/// their original asynchronous task/revalidation path, never a guessed label.
bool isMenuReadIntent(String method, Object? argument) {
  if (argument is! Map) return false;
  return switch (method) {
    'featureVisible' ||
    'friendsVisible' ||
    'commsVisible' => argument['visible'] == true,
    'featureAction' => argument['key'] == 'refresh',
    'friendsAction' => const {
      'refresh',
      'section',
      'search',
      'chat',
      'messages',
      'profile',
    }.contains(argument['action']),
    'commsCompose' => argument['action'] == 'check',
    'commsAction' => const {
      'select',
      'back',
      'retry',
      'older',
      'latest',
      'friend',
      'attachment',
      'inviteSend',
      'inviteRecords',
    }.contains(argument['action']),
    _ => false,
  };
}

final _readCommandKey = Object();

class _ReadCommand {
  _ReadCommand(this.origin);
  final MenuReadOrigin origin;
  bool active = true;
}

MenuReadOrigin get currentMenuReadOrigin {
  final command = Zone.current[_readCommandKey] as _ReadCommand?;
  return command?.active == true
      ? command!.origin
      : MenuReadOrigin.programmatic;
}

/// Only the synchronous, validated handoff is associated with this source.
/// Timers and continuations after it returns cannot lend it to another read.
T withMenuReadOrigin<T>(Object? source, T Function() action) {
  final origin = switch (source) {
    'pointer' => MenuReadOrigin.pointer,
    'keyboard' => MenuReadOrigin.keyboard,
    _ => MenuReadOrigin.programmatic,
  };
  final command = _ReadCommand(origin);
  try {
    return runZoned(action, zoneValues: {_readCommandKey: command});
  } finally {
    command.active = false;
  }
}

final class MenuReadFeedback {
  const MenuReadFeedback(this.request, this.origin);
  final int request;
  final MenuReadOrigin origin;
  Map<String, Object?> get wire => {'request': request, 'source': origin.name};

  /// Unknown/bad optional decoration falls back to static, not a business error.
  static MenuReadFeedback? parse(Object? raw) {
    if (raw is! Map ||
        raw['request'] is! int ||
        (raw['request'] as int) < 1 ||
        (raw['request'] as int) > 1000000000) {
      return null;
    }
    final origin = switch (raw['source']) {
      'pointer' => MenuReadOrigin.pointer,
      'keyboard' => MenuReadOrigin.keyboard,
      'programmatic' => MenuReadOrigin.programmatic,
      _ => null,
    };
    return origin == null
        ? null
        : MenuReadFeedback(raw['request'] as int, origin);
  }
}
