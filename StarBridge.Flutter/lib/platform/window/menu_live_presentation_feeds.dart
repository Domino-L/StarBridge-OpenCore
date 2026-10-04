import 'menu_attention.dart';
import 'menu_notice.dart';
import 'menu_avatar_presentation.dart';
import 'menu_social_preferences.dart';

import 'dart:convert';

/// Owns display subscriptions for exactly one visible menu opening.
final class MenuLivePresentationFeeds {
  MenuAttentionSource? _attention;
  MenuNoticeSource? _notices;
  int _epoch = 0;
  Map? _settings;
  final _avatarTargets = <MenuAvatarPresentation>{};
  bool get _showAvatars =>
      MenuSocialPreferences.fromSettings(_settings ?? const {})?.showAvatars ??
      false;
  void bindAvatars(Object? target, Map? initialSettings) {
    if (target is! MenuAvatarPresentation) return;
    _settings ??= initialSettings;
    _avatarTargets.add(target);
    target.showAvatars = _showAvatars;
  }

  bool get active => _attention != null || _notices != null;
  bool get hasNotices => _notices != null;
  void updateSettings(Map settings) {
    _settings = settings;
    _notices?.clear();
    for (final target in _avatarTargets) {
      target.showAvatars = _showAvatars;
    }
  }

  static String? contextPayload(List<String> values) =>
      (values.length == 5 || values.length == 6) &&
          values.every((value) => value.length <= 512)
      ? jsonEncode(values)
      : null;
  void start({
    MenuAttentionSource Function()? attention,
    MenuNoticeSource Function()? notices,
    String? Function()? visibleConversationKey,
    Map? settings,
    required bool Function() isCurrent,
    required void Function(Map<String, Object?>, String) publish,
  }) {
    final targets = _avatarTargets.toList();
    stop();
    _avatarTargets.addAll(targets);
    updateSettings(settings ?? const {});
    final epoch = _epoch;
    bool current() => epoch == _epoch && isCurrent();
    try {
      final counts = _attention = attention?.call();
      if (counts != null) {
        void update() {
          if (current()) publish(counts.value.toMap(), 'attentionView');
        }

        counts.addListener(update);
        update();
      }
      final messages = _notices = notices?.call();
      if (messages != null) {
        if (messages is MenuNoticeReadingContext) {
          (messages as MenuNoticeReadingContext).visibleConversationKey =
              visibleConversationKey;
          (messages as MenuNoticeReadingContext).menuSettings = settings == null
              ? null
              : () => _settings;
        }
        void update() {
          if (current()) {
            publish(
              messages.value?.toMap() ?? const {'title': '', 'message': ''},
              'noticeView',
            );
          }
        }

        messages.addListener(update);
        update();
      }
    } on Object {
      stop();
    }
  }

  void stop() {
    _epoch++;
    _settings = null;
    _avatarTargets.clear();
    _attention?.dispose();
    _notices?.dispose();
    _attention = null;
    _notices = null;
  }
}
