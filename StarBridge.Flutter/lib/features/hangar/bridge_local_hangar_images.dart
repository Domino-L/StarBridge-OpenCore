import 'dart:convert';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../communities/community_logo_port.dart';
import 'local_hangar_images.dart';
import 'local_hangar_port.dart';

final class BridgeLocalHangarImages implements LocalHangarImagePort {
  BridgeLocalHangarImages(
    this.session,
    this.owner,
    this.generation,
    this.shipId,
    this.revision,
  );
  final BridgeClientSession session;
  final BridgeAccountContext owner;
  final int generation;
  final String shipId;
  int revision;
  String? _draft;
  @override
  bool get canPickLogo =>
      session.activeGeneration == generation &&
      session.hostCapabilities.contains('hangar.localImages');
  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> body,
  ) async {
    if (!canPickLogo) throw const LocalHangarFailure('hangar.account_changed');
    try {
      final response = await session.request(
        'hangarImage.$name',
        accountContext: owner,
        payload: {'schemaVersion': 1, ...body},
        timeout: name == 'pick'
            ? const Duration(minutes: 5)
            : const Duration(seconds: 30),
      );
      final returned = response.accountContext;
      if (session.activeGeneration != generation ||
          response.sessionGeneration != generation ||
          returned?.environment != owner.environment ||
          returned?.authority != owner.authority ||
          returned?.subject != owner.subject) {
        throw const LocalHangarFailure('hangar.account_changed');
      }
      if (response.payload['schemaVersion'] != 1) throw const FormatException();
      return response.payload;
    } on BridgeRemoteException catch (error) {
      throw LocalHangarFailure(error.code);
    }
  }

  @override
  Future<CommunityLogoSource?> pickLogo() async {
    _draft = null;
    final value = await _request('pick', {
      'shipId': shipId,
      'expectedRevision': revision,
    });
    if (value['status'] == 'cancelled') return null;
    if (value['status'] != 'selected') throw const FormatException();
    final reference = value['draftRef'] as String;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(reference)) {
      throw const FormatException();
    }
    final data = _image(value['previewImageData']);
    final width = value['width'] as int, height = value['height'] as int;
    if (width <= 0 || height <= 0) throw const FormatException();
    _draft = reference;
    return CommunityLogoSource(reference, data, width, height);
  }

  @override
  Future<String> cropLogo(
    String sourceRef,
    double x,
    double y,
    double size,
  ) async {
    if (_draft == null || sourceRef != _draft) {
      throw const LocalHangarFailure('hangar.image_draft_expired');
    }
    final value = await _request('crop', {
      'draftRef': _draft,
      'x': x,
      'y': y,
      'size': size,
    });
    if (value['status'] != 'prepared' || value['draftRef'] != _draft) {
      throw const FormatException();
    }
    return _image(value['previewImageData']);
  }

  @override
  Future<String?> readImage() async {
    final value = await _request('read', {
      'shipId': shipId,
      'expectedRevision': revision,
    });
    if (value['status'] == 'none') return null;
    if (value['status'] != 'ready') throw const FormatException();
    return _image(value['imageData']);
  }

  @override
  Future<void> saveImage() async {
    if (_draft == null) {
      throw const LocalHangarFailure('hangar.image_draft_expired');
    }
    final value = await _request('save', {'draftRef': _draft});
    if (value['status'] != 'saved' || value['revision'] != revision + 1) {
      throw const FormatException();
    }
    revision++;
    _draft = null;
  }

  @override
  Future<void> restoreImage() async {
    final value = await _request('restore', {
      'shipId': shipId,
      'expectedRevision': revision,
    });
    if (value['status'] != 'restored' || value['revision'] != revision + 1) {
      throw const FormatException();
    }
    revision++;
    _draft = null;
  }

  @override
  Future<void> clearLogo() async {
    if (_draft == null) return;
    try {
      await _request('clear', const {});
    } finally {
      _draft = null;
    }
  }

  static String _image(Object? value) {
    if (value is! String ||
        value.length > 700000 ||
        !value.startsWith('data:image/png;base64,')) {
      throw const FormatException();
    }
    final bytes = base64Decode(
      value.substring('data:image/png;base64,'.length),
    );
    if (bytes.isEmpty || bytes.length > 512 * 1024) {
      throw const FormatException();
    }
    return value;
  }
}
