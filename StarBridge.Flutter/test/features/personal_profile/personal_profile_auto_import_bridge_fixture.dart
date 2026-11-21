import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'local_personal_profile_test.dart' show LocalProfileConnection;

class AutoImportPageConnection extends LocalProfileConnection {
  AutoImportPageConnection() {
    revision = 1;
    saveIntroductionLocally('Saved locally');
  }

  int pageRevision = 7;
  int pageReads = 0;
  int style = 1;
  String wallpaper = 'none';
  String pageAbout = 'Previous page';
  String? eligibleGroup = 'introduction';
  String? rejectedGroup, explicitFavorite, readback, sourceVersion;
  String eligibleOrigin = 'default';
  bool unconfirmed = false;
  bool versioned = true;
  bool loseCommitReceipt = false;
  int staleReadsRemaining = 0;
  final pageFields = <String, Object?>{};
  final groupOrigins = <String, String>{};
  File? _localContentFile;
  ({File main, File states})? _profileFiles;
  final additionalEligible = <String>{};
  List<String> favoriteCodes = [];
  List<Object?>? modules, showcases;
  Map<String, Object?>? _beforeWrite;
  ({Completer<void> started, Completer<void> finish})? _gate;

  Iterable<BridgeEnvelope> get writes => requests.where(
    (request) => request.name == 'personalProfile.updatePresentation',
  );

  List<Object?> get writtenGroups =>
      writes.map((request) => request.payload['editedGroups']).toList();

  int get localSaveCount =>
      requests.where((r) => r.name == 'personalProfile.localSave').length;

  void saveIntroductionLocally(String value) {
    content = {
      'introduction': value,
      'preserveEmptyFields': true,
      'modules': [],
    };
  }

  void useLocalContentFile(File file) {
    _localContentFile = file;
    _persistLocalContent();
  }

  void useOperationBoundProfileFiles(Directory folder) {
    operation = 'a' * 32;
    _profileFiles = (
      main: File('${folder.path}${Platform.pathSeparator}owner.json'),
      states: File('${folder.path}${Platform.pathSeparator}owner.field-states'),
    );
    _persistLocalContent();
  }

  void saveAsOldClient(String introduction) {
    final files = _profileFiles!;
    final saved = jsonDecode(files.main.readAsStringSync()) as Map;
    final oldContent = {
      ...(saved['content'] as Map),
      'introduction': introduction,
      'preserveEmptyFields': true,
    };
    files.main.writeAsStringSync(
      jsonEncode({
        'revision': (saved['revision'] as int) + 1,
        'operationId': 'b' * 32,
        'content': oldContent,
      }),
    );
  }

  void _persistLocalContent() {
    _localContentFile?.writeAsBytesSync(utf8.encode(jsonEncode(content)));
    if (_profileFiles case final files?) {
      final disk = {
        'introduction': '',
        'avatarStyle': 0,
        'wallpaperId': 'none',
        'modules': const [],
        ...?content,
      };
      final fields = disk.remove('fieldStates') as Map?;
      files.main.writeAsStringSync(
        jsonEncode({
          'revision': revision,
          'operationId': operation,
          'content': disk,
        }),
      );
      files.states.writeAsStringSync(
        jsonEncode({
          'operationId': operation,
          'explicitlyEmpty': [
            if (fields != null)
              for (final field in fields.entries)
                if (field.value == true) field.key,
          ],
        }),
      );
    }
  }

  void _readOperationBoundFiles(File main, File states) {
    final saved = jsonDecode(main.readAsStringSync()) as Map;
    revision = saved['revision'] as int;
    operation = saved['operationId'] as String;
    final fields = jsonDecode(states.readAsStringSync()) as Map;
    // The Host suite checks the real sidefile checksum and owner validation.
    content = {
      ...(saved['content'] as Map).cast<String, Object?>(),
      if (operation == fields['operationId'] &&
          (fields['explicitlyEmpty'] as List).isNotEmpty)
        'fieldStates': {
          for (final field in fields['explicitlyEmpty'] as List) field: true,
        },
    };
  }

  ({Completer<void> started, Completer<void> finish}) blockNextWrite() =>
      _gate = (started: Completer<void>(), finish: Completer<void>());

  void notifyProfileChanged() {
    stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'event',
        'name': 'personalProfile.changed',
        'sequence': 1,
        'sessionGeneration': generation,
        'payload': {'schemaVersion': 1},
      }),
    );
  }

  @override
  Future<void> send(BridgeEnvelope request) async {
    if (request.name == 'personalProfile.getSelf') {
      requests.add(request);
      pageReads++;
      final stale = staleReadsRemaining > 0;
      if (stale) staleReadsRemaining--;
      _reply(
        request,
        _beforeWrite != null && (readback == 'older revision' || stale)
            ? _beforeWrite!
            : _page(),
        error: _beforeWrite != null && readback == 'failed read'
            ? 'bridge.timeout'
            : null,
      );
      return;
    }
    if (request.name != 'personalProfile.updatePresentation') {
      if (request.name == 'personalProfile.localSave' &&
          request.payload['expectedRevision'] != revision &&
          request.payload['operationId'] != operation) {
        requests.add(request);
        _reply(request, const {}, error: 'profile_local.conflict');
        return;
      }
      if (_localContentFile case final file?
          when request.name == 'personalProfile.localRead') {
        this.content = (jsonDecode(utf8.decode(file.readAsBytesSync())) as Map)
            .cast<String, Object?>();
      }
      if (_profileFiles case final files?
          when request.name == 'personalProfile.localRead') {
        _readOperationBoundFiles(files.main, files.states);
      }
      final before = revision;
      final sent = super.send(request);
      if (before != revision) _persistLocalContent();
      await sent;
      return;
    }
    requests.add(request);
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      gate.started.complete();
      await gate.finish.future;
    }
    if (request.sessionGeneration != generation) return;
    final groups = request.payload['editedGroups']! as List;
    if (unconfirmed) {
      _reply(request, _page(), error: 'bridge.timeout');
      return;
    }
    if (groups.contains(rejectedGroup)) {
      _reply(request, _page(), error: 'personal_profile.write_forbidden');
      return;
    }
    expect(versioned, isTrue);
    if (request.payload['expectedRevision'] != pageRevision) {
      _reply(request, _page(), error: 'personal_profile.write_conflict');
      return;
    }
    _beforeWrite = _page();
    if (groups.contains('introduction')) {
      pageAbout = (request.payload['content'] as Map)['introduction'] as String;
    }
    if (groups.contains('avatarStyle')) {
      style = request.payload['avatarStyle']! as int;
    }
    if (groups.contains('wallpaper')) {
      wallpaper = request.payload['wallpaperId']! as String;
    }
    final content = request.payload['content'] as Map;
    if (groups.contains('playStyle')) {
      for (final field in const [
        'skilledRoles',
        'participationInterests',
        'supportCapabilities',
      ]) {
        if (content.containsKey(field)) pageFields[field] = content[field];
      }
    }
    if (groups.contains('favorites')) {
      favoriteCodes = (content['favoriteShipCodes'] as List).cast<String>();
    }
    if (groups.contains('layout')) {
      modules = content['modules'] as List?;
      showcases = content['showcases'] as List?;
      explicitFavorite = null;
    }
    for (final group in groups.cast<String>()) {
      groupOrigins.remove(group);
    }
    if (groups.contains(eligibleGroup)) eligibleGroup = null;
    additionalEligible.removeAll(groups.cast<String>());
    pageRevision++;
    _reply(
      request,
      _page(),
      error: loseCommitReceipt ? 'bridge.timeout' : null,
    );
    loseCommitReceipt = false;
  }

  Map<String, Object?> _page() => {
    'schemaVersion': 1,
    'editable': true,
    'profile': {
      'revision': pageRevision,
      'avatarStyle': style,
      'wallpaperId': wallpaper,
      'visibility': 'public',
      'identity': {'callSign': 'Fixture', 'gameHandle': 'Fixture'},
      if (versioned)
        'presentation': {
          'schemaVersion': 1,
          'sourceVersion': sourceVersion,
          'origins': {
            for (final group in PersonalProfilePresentation.groups)
              group:
                  groupOrigins[group] ??
                  (group == eligibleGroup
                      ? eligibleOrigin
                      : additionalEligible.contains(group)
                      ? 'default'
                      : 'custom'),
          },
        },
      'content': {
        ...pageFields,
        'introduction': pageAbout,
        'favoriteShipCodes': favoriteCodes,
        if (modules != null) 'modules': modules,
        if (showcases != null) 'showcases': showcases,
        if (explicitFavorite case final picked?)
          'modules': [
            {
              'id': 'favorite-ships',
              'span': 3,
              'isVisible': true,
              'order': 0,
              'position': 0,
              'favoriteShipIds': [picked],
            },
          ],
      },
    },
  };

  void _reply(
    BridgeEnvelope request,
    Map<String, Object?> page, {
    String? error,
  }) {
    stream.add(
      BridgeEnvelope.fromJson({
        'protocolVersion': 1,
        'messageType': 'response',
        'name': request.name,
        'correlationId': request.correlationId,
        'sessionGeneration': generation,
        'status': error == null ? 'ok' : 'error',
        if (error != null)
          'error': {'code': error, 'message': 'fixture', 'retryable': false},
        'accountContext': {
          'environment': environment,
          'authority': authority,
          'subject': subject,
        },
        'payload': page,
      }),
    );
  }
}
