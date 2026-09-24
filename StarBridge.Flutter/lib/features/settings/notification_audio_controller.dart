import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';

final class AudioPreferences {
  const AudioPreferences(
    this.revision,
    this.enabled,
    this.volume,
    this.previewAvailable, {
    this.doNotDisturb = false,
  });
  final int revision;
  final bool enabled, previewAvailable;
  final double volume;
  final bool doNotDisturb;
}

abstract interface class NotificationAudioPort {
  Future<AudioPreferences> read();
  Future<AudioPreferences> save(
    AudioPreferences current,
    bool enabled,
    double volume, {
    bool? doNotDisturb,
  });
  Future<String> preview();
  Future<void> stop();
}

final class AudioFailure implements Exception {
  const AudioFailure(this.code);
  final String code;
}

final class BridgeNotificationAudio implements NotificationAudioPort {
  BridgeNotificationAudio(this.session);
  final BridgeClientSession session;
  Future<Map<String, Object?>> _call(
    String name, [
    Map<String, Object?> fields = const {},
  ]) async {
    if (!session.hostCapabilities.contains('notificationAudio.$name')) {
      throw const AudioFailure('unavailable');
    }
    try {
      final response = await session.request(
        'notificationAudio.$name',
        payload: {'schemaVersion': 1, ...fields},
      );
      if (response.payload['schemaVersion'] != 1) {
        throw const AudioFailure('invalidResponse');
      }
      return response.payload;
    } on BridgeClientException catch (e) {
      throw AudioFailure(switch (e.code) {
        'notificationAudio.write_conflict' => 'conflict',
        'notificationAudio.integrity_failed' => 'integrity',
        'notificationAudio.cue_unavailable' => 'assets',
        'notificationAudio.output_unavailable' => 'output',
        _ => 'failed',
      });
    }
  }

  AudioPreferences _parse(Map<String, Object?> data) {
    final revision = data['revision'],
        enabled = data['enabled'],
        volume = data['volume'],
        available = data['previewAvailable'];
    if (revision is! int ||
        revision < 0 ||
        enabled is! bool ||
        volume is! num ||
        !volume.isFinite ||
        volume < 0 ||
        volume > 1 ||
        available is! bool ||
        (data.containsKey('doNotDisturb') && data['doNotDisturb'] is! bool)) {
      throw const AudioFailure('invalidResponse');
    }
    return AudioPreferences(
      revision,
      enabled,
      volume.toDouble(),
      available,
      doNotDisturb: data['doNotDisturb'] as bool? ?? false,
    );
  }

  @override
  Future<AudioPreferences> read() async => _parse(await _call('read'));
  @override
  Future<AudioPreferences> save(
    AudioPreferences current,
    bool enabled,
    double volume, {
    bool? doNotDisturb,
  }) async => _parse(
    await _call('save', {
      'expectedRevision': current.revision,
      'enabled': enabled,
      'volume': volume,
      'doNotDisturb': doNotDisturb ?? current.doNotDisturb,
    }),
  );
  @override
  Future<String> preview() async {
    final result = await _call('preview', {'cueId': 'notify.soft'});
    if (result['cueId'] != 'notify.soft' ||
        !const {'played', 'muted'}.contains(result['status'])) {
      throw const AudioFailure('invalidResponse');
    }
    return result['status']! as String;
  }

  @override
  Future<void> stop() async {
    if ((await _call('stop'))['status'] != 'stopped') {
      throw const AudioFailure('invalidResponse');
    }
  }
}

final class NotificationAudioController extends ChangeNotifier {
  NotificationAudioController(this.port);
  final NotificationAudioPort port;
  AudioPreferences? value;
  String? error, status;
  bool busy = false, _disposed = false;
  int _previewEpoch = 0;
  bool get canPreview =>
      !busy &&
      value?.enabled == true &&
      value!.volume > 0 &&
      value!.previewAvailable;
  Future<void> refresh() => _run(() async {
    value = await port.read();
  });
  Future<void> save({bool? enabled, double? volume, bool? doNotDisturb}) =>
      _run(() async {
        final current = value;
        if (current == null) return;
        value = await port.save(
          current,
          enabled ?? current.enabled,
          volume ?? current.volume,
          doNotDisturb: doNotDisturb ?? current.doNotDisturb,
        );
        status = 'saved';
      });
  Future<void> preview() async {
    if (!canPreview) return;
    final epoch = ++_previewEpoch;
    await _run(() async {
      final result = await port.preview();
      if (!_disposed && epoch == _previewEpoch) status = result;
    });
  }

  Future<void> stop() async {
    _previewEpoch++;
    try {
      await port.stop();
      if (!_disposed) {
        status = 'stopped';
        notifyListeners();
      }
    } catch (e) {
      if (!_disposed) {
        error = e is AudioFailure ? e.code : 'failed';
        notifyListeners();
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    status = null;
    notifyListeners();
    try {
      await operation();
    } catch (e) {
      if (!_disposed) error = e is AudioFailure ? e.code : 'failed';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _previewEpoch++;
    unawaited(port.stop().catchError((Object _) {}));
    super.dispose();
  }
}
