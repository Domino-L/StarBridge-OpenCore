import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../features/hangar/hangar_reader_port.dart';

final class MethodChannelHangarBrowser implements HangarBrowserPort {
  MethodChannelHangarBrowser({
    this.timeout = const Duration(seconds: 30),
    this.clearTimeout = const Duration(minutes: 3),
  });
  static const _channel = MethodChannel('starbridge/hangar-browser');
  final Duration timeout;

  /// Calls that may clear the sign-in data. Native waits for the browser
  /// process to exit (up to 15 s), then deletes thousands of cache files off
  /// the UI thread; the page stays responsive and shows the clearing state.
  final Duration clearTimeout;
  int _id = 0;
  int _openEpoch = 0;
  void Function(bool)? _focusExit;
  @override
  void setFocusExitHandler(void Function(bool previous)? handler) {
    _focusExit = handler;
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      throw HangarReaderFailure(error.code);
    } on MissingPluginException {
      throw const HangarReaderFailure('runtime');
    }
  }

  Future<T?> _call<T>(String method, [Map<String, Object?> args = const {}]) =>
      _invoke<T>(method, {'viewId': _id, ...args}).timeout(timeout);

  Future<void> _closeId(int id) async {
    try {
      await _invoke<void>('close', {'viewId': id}).timeout(clearTimeout);
    } on Object {
      // The native owner may already have closed this exact view.
    }
  }

  @override
  Future<void> open({required String profileKey}) async {
    final epoch = ++_openEpoch;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'leaveFocus' &&
          call.arguments is Map &&
          call.arguments['viewId'] == _id) {
        _focusExit?.call(call.arguments['previous'] == true);
      }
    });
    final opening = _invoke<int>('open', {
      'viewId': 0,
      'profileKey': profileKey,
    });
    // Keep the underlying completion after a timeout/cancel so a late-created
    // native view is closed by its own ID, never by the new page's current ID.
    unawaited(
      opening
          .then<void>((id) async {
            if (epoch != _openEpoch && id != null && id > 0) await _closeId(id);
          })
          .catchError((Object _) {}),
    );
    try {
      final id = await opening.timeout(timeout);
      if (epoch != _openEpoch) throw const HangarReaderFailure('closed');
      if (id == null || id < 1) throw const HangarReaderFailure('runtime');
      _id = id;
    } on Object {
      if (epoch == _openEpoch) ++_openEpoch;
      rethrow;
    }
  }

  @override
  Future<void> page(int page) async {
    await _call<void>('page', {'page': page});
  }

  @override
  Future<Map<String, Object?>> capture() async {
    return _capture('capture');
  }

  @override
  Future<Map<String, Object?>> lock() => _capture('lock');

  @override
  Future<void> unlock() async {
    if (_id > 0) await _call<void>('unlock');
  }

  Future<Map<String, Object?>> _capture(String method) async {
    final raw = await _call<Map>(method);
    if (raw == null ||
        raw['json'] is! String ||
        (raw['json'] as String).length > 600 * 1024) {
      throw const HangarReaderFailure('read');
    }
    return {
      'source': raw['source'],
      'scanId': raw['scanId'],
      'locked': raw['locked'],
      'documentGeneration': raw['documentGeneration'],
      'observation': jsonDecode(raw['json'] as String),
    };
  }

  @override
  Future<void> bounds(Rect rect, {required bool visible}) async {
    await _call<void>('bounds', {
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
      'visible': visible,
    });
  }

  @override
  Future<void> focus() async {
    await _call<void>('focus');
  }

  @override
  Future<void> clearData() async {
    ++_openEpoch;
    _id = 0;
    // Native closes any current view. No profile key or filesystem path crosses this call.
    await _invoke<void>('clearData', const {}).timeout(clearTimeout);
  }

  @override
  Future<HangarSignIn> readSignIn() async {
    final raw = await _invoke<Map>('readChoice', const {}).timeout(timeout);
    return (
      remember: raw?['remember'] == true,
      uncleared: raw?['uncleared'] == true,
      unknown: raw?['unknown'] == true,
    );
  }

  @override
  Future<void> setRemember(bool remember) async {
    await _invoke<void>('setChoice', {
      'remember': remember,
    }).timeout(clearTimeout);
    // Native closes the page only once the choice is saved; until then the
    // current view keeps its ID, so it can still be closed.
    ++_openEpoch;
    _id = 0;
  }

  @override
  Future<void> close() async {
    ++_openEpoch;
    final id = _id;
    _id = 0;
    if (id > 0) await _closeId(id);
  }
}
