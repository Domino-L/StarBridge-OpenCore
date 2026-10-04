import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/notifications/local_notification_content.dart';
import '../../features/settings/bridge_notification_settings_adapter.dart';
import '../../features/settings/notification_settings_models.dart';
import '../../platform/window/menu_notice.dart';
import '../../platform/window/menu_social_preferences.dart';
import '../localization/app_strings.dart';

/// One visible-menu lease over the existing Host-approved reminder stream.
/// Never polls, queues history, reads message bodies or acquires account access.
final class MenuSocialNoticeSource extends ChangeNotifier
    implements MenuNoticeSource, MenuNoticeReadingContext {
  MenuSocialNoticeSource({
    required Stream<LocalRoomReminder?> events,
    required this.settings,
    required this.authorization,
    required this.isCurrent,
    required this.strings,
    this.enabled,
    this.preview,
    this.visibleConversationKey,
    Stream<void>? invalidations,
  }) {
    settings.addListener(clear);
    authorization.addListener(_authorizationChanged);
    _invalidations = invalidations?.listen((_) {
      _revoked = true;
      clear();
    });
    _subscription = events.listen(
      _receive,
      onError: (Object _) => clear(),
      onDone: clear,
    );
  }
  final ValueListenable<NotificationSettingsProjection> settings;
  final Listenable authorization;
  final bool Function() isCurrent;
  final AppStrings Function() strings;
  final bool Function()? enabled;
  final NotificationPreviewMode Function()? preview;
  @override
  String? Function()? visibleConversationKey;
  @override
  Map? Function()? menuSettings;
  late final StreamSubscription<LocalRoomReminder?> _subscription;
  StreamSubscription<void>? _invalidations;
  Timer? _expiry;
  bool _disposed = false, _revoked = false;
  MenuNotice? _value;
  @override
  MenuNotice? get value => _value;

  bool get _authorized {
    if (!isCurrent()) _revoked = true;
    return !_disposed && !_revoked;
  }

  void _authorizationChanged() {
    if (!_authorized) clear();
  }

  void _receive(LocalRoomReminder? event) {
    clear();
    final raw = menuSettings?.call();
    final social = raw == null ? null : MenuSocialPreferences.fromSettings(raw);
    if (menuSettings != null && (social == null || !social.notifications)) {
      return;
    }
    if (!_authorized ||
        event == null ||
        event.overlayHandled ||
        event.desktopEligible ||
        (event.kind != 'direct' && event.kind != 'friend') ||
        enabled?.call() == false) {
      return;
    }
    final projection = settings.value, current = projection.settings;
    if (!projection.canEdit ||
        current == null ||
        !current.channels.inAppEnabled ||
        event.revision != projection.revision) {
      return;
    }
    final visible = visibleConversationKey?.call();
    if (event.kind == 'direct' &&
        visible != null &&
        event.conversationKeys.isNotEmpty &&
        event.conversationKeys.every((key) => key == visible)) {
      return;
    }
    // Menu-specific preferences may redact further, never broaden global privacy.
    final modes = [
      NotificationPreviewMode.fullContent,
      NotificationPreviewMode.sourceOnly,
      NotificationPreviewMode.hiddenDetails,
    ];
    final local = social == null
        ? preview?.call() ?? NotificationPreviewMode.sourceOnly
        : NotificationPreviewMode.values.byName(social.preview);
    final effective = modes.indexOf(local) > modes.indexOf(current.previewMode)
        ? local
        : current.previewMode;
    final content = localNotificationContent(strings(), event, effective);
    final notice = MenuNotice(content.title, content.message);
    // Refuse malformed or oversized display payloads instead of truncating secrets.
    if (notice.title.length > 1024 || notice.message.length > 8192) return;
    _value = notice;
    _expiry = Timer(const Duration(seconds: 4), clear);
    notifyListeners();
  }

  @override
  void clear() {
    _expiry?.cancel();
    _expiry = null;
    if (_disposed || _value == null) return;
    _value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _expiry?.cancel();
    _value = null;
    _disposed = true;
    settings.removeListener(clear);
    authorization.removeListener(_authorizationChanged);
    unawaited(_subscription.cancel());
    unawaited(_invalidations?.cancel());
    super.dispose();
  }
}
