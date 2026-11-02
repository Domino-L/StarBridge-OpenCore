import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum MenuInteractionStyle { standard, rail, scan, glow }

/// Display-only envelope. No account, layout, capability or persistence data.
@immutable
final class MenuInteractionPresentation {
  const MenuInteractionPresentation({
    this.style = MenuInteractionStyle.standard,
    this.reduceMotion = false,
    this.language,
    this.holiday,
  });

  final MenuInteractionStyle style;
  final bool reduceMotion;
  final String? language;

  /// 现在生效的节日，不在节日里或开关关了就没有。
  final String? holiday;
  static const defaults = MenuInteractionPresentation();
  static const maxPayloadLength = 128;

  String encode() => jsonEncode({
    'schemaVersion': 1,
    'style': style.name,
    'reduceMotion': reduceMotion,
    if (language != null) 'language': language,
    if (holiday != null) 'holiday': holiday,
  });

  static MenuInteractionPresentation? parse(Object? payload) {
    if (payload is! String || payload.length > maxPayloadLength) return null;
    try {
      final value = jsonDecode(payload);
      if (value is! Map ||
          value.length < 3 ||
          value.length > 5 ||
          value.keys.any(
            (key) => !const {
              'schemaVersion',
              'style',
              'reduceMotion',
              'language',
              'holiday',
            }.contains(key),
          ) ||
          value.containsKey('language') &&
              !const {
                'zh-CN',
                'zh-TW',
                'en-US',
                'en',
              }.contains(value['language']) ||
          value.containsKey('holiday') && !_validHoliday(value['holiday']) ||
          value['schemaVersion'] is! int ||
          value['schemaVersion'] != 1 ||
          value['reduceMotion'] is! bool) {
        return null;
      }
      final style = MenuInteractionStyle.values
          .where((item) => item.name == value['style'])
          .firstOrNull;
      if (style == null) return null;
      return MenuInteractionPresentation(
        style: style,
        language: value['language'] as String?,
        holiday: value['holiday'] as String?,
        reduceMotion: value['reduceMotion'] as bool,
      );
    } on Object {
      return null;
    }
  }

  static bool _validHoliday(Object? value) =>
      value is String && RegExp(r'^[a-z0-9-]{1,32}$').hasMatch(value);
}

/// Borrows the existing preference owner's notification, for one opening only.
/// No polling or second settings store; unchanged projections send no message.
final class MenuInteractionFeed {
  MenuInteractionFeed({required this.changes, required this.read});
  final Listenable changes;
  final MenuInteractionPresentation Function() read;
  VoidCallback? _listener;
  int _epoch = 0;
  int _sequence = 0;

  void startForOpening(
    MethodChannel channel,
    int opening, {
    required bool Function() isCurrent,
  }) {
    Future<void> send(String payload) async {
      final epoch = _epoch;
      try {
        await channel.invokeMethod<void>('interactionPresentation', {
          'opening': opening,
          'revision': ++_sequence,
          'payload': payload,
        });
      } on PlatformException {
        if (epoch == _epoch) stop();
      } on MissingPluginException {
        if (epoch == _epoch) stop();
      }
    }

    start(isCurrent: isCurrent, publish: (payload) => unawaited(send(payload)));
  }

  void start({
    required bool Function() isCurrent,
    required void Function(String) publish,
  }) {
    stop();
    final epoch = _epoch;
    String? previous;
    void update() {
      if (epoch != _epoch || !isCurrent()) return;
      final next = read().encode();
      if (next == previous) return;
      previous = next;
      publish(next);
    }

    _listener = update;
    changes.addListener(update);
    update(); // Includes changes that happened during native preparation.
  }

  void stop() {
    _epoch++;
    final listener = _listener;
    _listener = null;
    if (listener != null) changes.removeListener(listener);
  }
}

/// Secondary-engine display state. Late updates never cross an opening, and
/// invalid payloads do not consume the revision of a later valid update.
final class MenuInteractionReceiver {
  int _opening = -1, _revision = -1;
  bool _wanted = false;
  MenuInteractionPresentation value = MenuInteractionPresentation.defaults;

  void open(int opening, bool wanted, Object? payload) {
    if (opening != _opening || !wanted) {
      _revision = -1;
      value = wanted
          ? MenuInteractionPresentation.parse(payload) ??
                MenuInteractionPresentation.defaults
          : MenuInteractionPresentation.defaults;
    }
    _opening = opening;
    _wanted = wanted;
  }

  bool accept(Object? arguments) {
    if (!_wanted || arguments is! Map || arguments['opening'] != _opening) {
      return false;
    }
    final revision = arguments['revision'];
    if (revision is! int || revision < 0 || revision <= _revision) return false;
    final next = MenuInteractionPresentation.parse(arguments['payload']);
    if (next == null) return false;
    value = next;
    _revision = revision;
    return true;
  }
}
