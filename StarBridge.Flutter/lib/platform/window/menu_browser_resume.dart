import '../bridge/bridge_client_session.dart';
import 'menu_settings_read.dart';

/// Explicit, account-local permission plus a single last page. Kept separate
/// from device window preferences and never included in shareable presets.
final class MenuBrowserResume {
  const MenuBrowserResume(this.revision, this.enabled, this.url);
  final int revision;
  final bool enabled;
  final String? url;
  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'revision': revision,
    'enabled': enabled,
    'url': url,
  };
  static bool validUrl(String url) {
    final uri = Uri.tryParse(url);
    return url.isNotEmpty &&
        url.length <= 4096 &&
        url.trim() == url &&
        !RegExp(r'[\x00-\x20\x7f\\]').hasMatch(url) &&
        uri != null &&
        const ['https', 'http'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        !uri.host.contains('%') &&
        uri.userInfo.isEmpty;
  }

  factory MenuBrowserResume.parse(Object? raw) {
    if (raw is! Map ||
        raw.length != 4 ||
        raw['schemaVersion'] != 1 ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 0 ||
        raw['enabled'] is! bool ||
        !raw.containsKey('url') ||
        (raw['url'] != null &&
            (raw['url'] is! String || !validUrl(raw['url'] as String))) ||
        (raw['enabled'] == false && raw['url'] != null)) {
      throw const FormatException('Invalid browser resume settings');
    }
    return MenuBrowserResume(raw['revision'], raw['enabled'], raw['url']);
  }
}

abstract interface class MenuBrowserResumePort {
  Future<MenuBrowserResume> read();
  Future<MenuBrowserResume> setEnabled(MenuBrowserResume saved, bool enabled);
  Future<MenuBrowserResume> remember(MenuBrowserResume saved, String url);
}

abstract interface class MenuBrowserResumeProvider {
  MenuBrowserResumePort? get browserResume;
}

final class BridgeMenuBrowserResume implements MenuBrowserResumePort {
  BridgeMenuBrowserResume(this.session)
    : _generation = session.activeGeneration;
  final BridgeClientSession session;
  final int _generation;
  @override
  Future<MenuBrowserResume> read() => _send('read', const {});
  @override
  Future<MenuBrowserResume> setEnabled(MenuBrowserResume saved, bool enabled) =>
      _send('update', {'expectedRevision': saved.revision, 'enabled': enabled});
  @override
  Future<MenuBrowserResume> remember(MenuBrowserResume saved, String url) {
    if (!saved.enabled || !MenuBrowserResume.validUrl(url)) {
      throw const FormatException('Browser address saving is not permitted');
    }
    return _send('remember', {'expectedRevision': saved.revision, 'url': url});
  }

  Future<MenuBrowserResume> _send(
    String action,
    Map<String, Object?> payload,
  ) async {
    if (session.activeGeneration != _generation) {
      throw const BridgeClientException(
        'menuBrowserResume.session_unavailable',
      );
    }
    final result = action == 'read'
        ? await readMenuSettings(
            session,
            'menuBrowserResume.read',
            unavailableCode: 'menuBrowserResume.session_unavailable',
            isCurrent: () => session.activeGeneration == _generation,
          )
        : await session.request(
            'menuBrowserResume.$action',
            payload: {'schemaVersion': 1, ...payload},
            timeout: const Duration(seconds: 3),
          );
    if (session.activeGeneration != _generation) {
      throw const BridgeClientException(
        'menuBrowserResume.session_unavailable',
      );
    }
    return MenuBrowserResume.parse(result.payload);
  }
}
