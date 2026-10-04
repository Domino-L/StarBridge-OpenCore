import 'dart:async';

import '../bridge/bridge_client_session.dart';
import 'menu_settings_read.dart';

/// A committed device destination, kept out of shareable menu preferences.
/// The renderer never supplies a destination or writes files itself.
final class MenuScreenshotDirectory {
  const MenuScreenshotDirectory({
    required this.revision,
    required this.directory,
    required this.isDefault,
    this.cancelled = false,
    this.opened = false,
  });
  final int revision;
  final String directory;
  final bool isDefault, cancelled, opened;

  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'revision': revision,
    'directory': directory,
    'isDefault': isDefault,
    'cancelled': cancelled,
    'opened': opened,
  };

  factory MenuScreenshotDirectory.parse(Object? raw) {
    if (raw is! Map ||
        raw.length != 6 ||
        raw['schemaVersion'] != 1 ||
        raw['revision'] is! int ||
        (raw['revision'] as int) < 0 ||
        raw['directory'] is! String ||
        (raw['directory'] as String).isEmpty ||
        (raw['directory'] as String).length > 32767 ||
        (raw['directory'] as String).trim() != raw['directory'] ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(raw['directory'] as String) ||
        !RegExp(r'^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+(?:\\|$))')
            .hasMatch(raw['directory'] as String) ||
        RegExp(r'^\\\\[?.]\\').hasMatch(raw['directory'] as String) ||
        RegExp(r'(?:^|\\)\.{1,2}(?:\\|$)')
            .hasMatch(raw['directory'] as String) ||
        raw['isDefault'] is! bool ||
        raw['cancelled'] is! bool ||
        raw['opened'] is! bool ||
        (raw['cancelled'] == true && raw['opened'] == true)) {
      throw const FormatException('Invalid screenshot destination reply');
    }
    return MenuScreenshotDirectory(
      revision: raw['revision'],
      directory: raw['directory'],
      isDefault: raw['isDefault'],
      cancelled: raw['cancelled'],
      opened: raw['opened'],
    );
  }
}

abstract interface class MenuScreenshotDirectoryPort {
  Future<MenuScreenshotDirectory> read();
  Future<MenuScreenshotDirectory> choose(MenuScreenshotDirectory saved);
  Future<MenuScreenshotDirectory> reset(MenuScreenshotDirectory saved);
  Future<MenuScreenshotDirectory> open(MenuScreenshotDirectory saved);
}

abstract interface class MenuScreenshotDirectoryProvider {
  MenuScreenshotDirectoryPort? get screenshotDirectory;
}

/// A native chooser result held only until explicit settings Save. The token
/// grants no filesystem access and cannot be reused in another account scope.
final class MenuScreenshotDirectorySelection {
  const MenuScreenshotDirectorySelection({
    required this.revision,
    required this.directory,
    required this.token,
    required this.cancelled,
  });
  final int revision;
  final String directory;
  final String? token;
  final bool cancelled;
  factory MenuScreenshotDirectorySelection.parse(Object? raw) {
    if (raw is! Map ||
        raw.length != 5 ||
        raw['cancelled'] is! bool ||
        !raw.containsKey('token') ||
        (raw['cancelled'] == true
            ? raw['token'] != null
            : raw['token'] is! String ||
                  !RegExp(r'^[a-f0-9]{32}$')
                      .hasMatch(raw['token'] as String))) {
      throw const FormatException('Invalid screenshot selection');
    }
    final checked = MenuScreenshotDirectory.parse({
      'schemaVersion': raw['schemaVersion'],
      'revision': raw['revision'],
      'directory': raw['directory'],
      'isDefault': false,
      'cancelled': raw['cancelled'],
      'opened': false,
    });
    return MenuScreenshotDirectorySelection(
      revision: checked.revision,
      directory: checked.directory,
      token: raw['token'],
      cancelled: checked.cancelled,
    );
  }
}

abstract interface class StagedMenuScreenshotDirectoryPort
    implements MenuScreenshotDirectoryPort {
  Future<MenuScreenshotDirectorySelection> chooseDraft(
    MenuScreenshotDirectory saved,
  );
  Future<MenuScreenshotDirectory> commitDraft(
    MenuScreenshotDirectorySelection selection,
  );
}

/// Each menu opening owns its pending chooser independently of the client page.
abstract interface class ScopedMenuScreenshotDirectory
    implements MenuScreenshotDirectoryPort {
  ScopedMenuScreenshotDirectory fork();
  void dispose();
}

final class BridgeMenuScreenshotDirectory
    implements
        ScopedMenuScreenshotDirectory,
        StagedMenuScreenshotDirectoryPort {
  BridgeMenuScreenshotDirectory(this.session)
    : _generation = session.activeGeneration;
  final BridgeClientSession session;
  final int _generation;
  bool _closed = false;
  final _pending = <BridgeRequestOperation>{};
  @override
  BridgeMenuScreenshotDirectory fork() {
    if (_closed || session.activeGeneration != _generation) {
      throw const BridgeClientException(
        'menuScreenshotDirectory.session_unavailable',
      );
    }
    return BridgeMenuScreenshotDirectory(session);
  }

  @override
  void dispose() {
    _closed = true;
    for (final operation in _pending.toList()) {
      unawaited(operation.cancel());
    }
    _pending.clear();
  }

  @override
  Future<MenuScreenshotDirectory> read() => _send('read');
  @override
  Future<MenuScreenshotDirectory> choose(MenuScreenshotDirectory saved) =>
      _send('choose', saved: saved);
  @override
  Future<MenuScreenshotDirectory> reset(MenuScreenshotDirectory saved) =>
      _send('reset', saved: saved);
  @override
  Future<MenuScreenshotDirectory> open(MenuScreenshotDirectory saved) =>
      _send('open', saved: saved);

  @override
  Future<MenuScreenshotDirectorySelection> chooseDraft(
    MenuScreenshotDirectory saved,
  ) async {
    if (_closed || session.activeGeneration != _generation) {
      throw const BridgeClientException(
        'menuScreenshotDirectory.session_unavailable',
      );
    }
    if (saved.revision < 0) {
      throw const FormatException('Invalid screenshot destination revision');
    }
    final operation = session.beginRequest(
      'menuScreenshotDirectory.chooseDraft',
      payload: {'schemaVersion': 1, 'expectedRevision': saved.revision},
      timeout: const Duration(minutes: 5),
    );
    _pending.add(operation);
    try {
      final result = await operation.future;
      if (_closed || session.activeGeneration != _generation) {
        throw const BridgeClientException(
          'menuScreenshotDirectory.session_unavailable',
        );
      }
      final selection = MenuScreenshotDirectorySelection.parse(result.payload);
      if (selection.revision != saved.revision) {
        throw const FormatException('Invalid selection revision');
      }
      return selection;
    } finally {
      _pending.remove(operation);
    }
  }

  @override
  Future<MenuScreenshotDirectory> commitDraft(
    MenuScreenshotDirectorySelection selection,
  ) {
    if (selection.cancelled ||
        selection.token == null ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(selection.token!)) {
      throw const FormatException('No pending screenshot selection');
    }
    return _send(
      'commitDraft',
      saved: MenuScreenshotDirectory(
        revision: selection.revision,
        directory: selection.directory,
        isDefault: false,
      ),
      token: selection.token,
    );
  }

  Future<MenuScreenshotDirectory> _send(
    String action, {
    MenuScreenshotDirectory? saved,
    String? token,
  }) async {
    void current() {
      if (_closed || session.activeGeneration != _generation) {
        throw const BridgeClientException(
          'menuScreenshotDirectory.session_unavailable',
        );
      }
    }

    current();
    if (saved != null && saved.revision < 0) {
      throw const FormatException('Invalid screenshot destination revision');
    }
    if (action == 'read') {
      final result = await readMenuSettings(
        session,
        'menuScreenshotDirectory.read',
        unavailableCode: 'menuScreenshotDirectory.session_unavailable',
        isCurrent: () => !_closed && session.activeGeneration == _generation,
        onBegin: _pending.add,
        onEnd: _pending.remove,
      );
      current();
      final value = MenuScreenshotDirectory.parse(result.payload);
      if (value.opened || value.cancelled) {
        throw const FormatException('Invalid screenshot destination outcome');
      }
      return value;
    }
    final operation = session.beginRequest(
      'menuScreenshotDirectory.$action',
      payload: {
        'schemaVersion': 1,
        if (saved != null) 'expectedRevision': saved.revision,
        'token': ?token,
      },
      // A user-driven native picker must not expire like a short metadata read.
      // The shared bridge still delivers cancellation and retires old generations.
      timeout: action == 'choose'
          ? const Duration(minutes: 5)
          : const Duration(seconds: 3),
    );
    _pending.add(operation);
    try {
      final result = await operation.future;
      current();
      final value = MenuScreenshotDirectory.parse(result.payload);
      if ((saved != null && value.revision < saved.revision) ||
          (action != 'choose' && value.cancelled) ||
          (action == 'open' ? !value.opened : value.opened) ||
          (action == 'open' &&
              (value.revision != saved!.revision ||
                  value.directory != saved.directory))) {
        throw const FormatException('Invalid screenshot destination outcome');
      }
      return value;
    } finally {
      _pending.remove(operation);
    }
  }
}
