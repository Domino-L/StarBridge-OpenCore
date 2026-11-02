import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_port.dart';

const fixtureRoot = 'test/fixtures/official_fleet_announcement_host';
Map<String, Object?> hostWire(String name) =>
    (jsonDecode(File('$fixtureRoot/$name.json').readAsStringSync()) as Map)
        .cast<String, Object?>();

void main() {
  test('all24 exact Host payloads retain producer SHA and provenance', () {
    final manifest = hostWire('producer-manifest');
    expect(
      manifest['producerManifestSha256'],
      'a620395cda5147250e1cf8c0eaa41ed39526db1cd4becafadcbe7ad3e02d74f4',
    );
    expect(manifest['syntheticEnvelopeInConsumer'], isTrue);
    final files = manifest['files'] as List;
    expect(files, hasLength(24));
    var bytes = 0;
    for (final entry in files.cast<Map>()) {
      final value = File('$fixtureRoot/${entry['name']}').readAsBytesSync();
      expect(sha256.convert(value).toString(), entry['sha256']);
      expect(value.length, entry['bytes']);
      bytes += value.length;
    }
    expect(bytes, 4165);
  });

  test('actual editor plus three actions use exact original opaque refs', () {
    var previous = 0;
    for (final (editorScene, actionScene) in [
      ('lifecycle-01-editor', 'lifecycle-02-publish'),
      ('lifecycle-03-editor', 'lifecycle-04-edit'),
      ('lifecycle-05-editor', 'lifecycle-06-withdraw'),
    ]) {
      final request = hostWire('$editorScene-request');
      expect(request.keys.toSet(), {'schemaVersion', 'sourceRef'});
      final editor = OrganizationAnnouncementEditor.parse(
        hostWire('$editorScene-response'),
        request['sourceRef'] as String,
      );
      expect(editor.revision, previous);
      final wireIntent = hostWire('$actionScene-request');
      final intent = OrganizationAnnouncementIntent.parse(wireIntent);
      expect(intent.toPayload(), wireIntent);
      expect(intent.editRef, editor.editRef);
      expect(intent.sourceRef, editor.sourceRef);
      if (intent.action != 'publish') {
        expect(intent.announcementRef, editor.current!.announcementRef);
      }
      final result = OrganizationAnnouncementOutcome.parseManage(
        hostWire('$actionScene-response'),
        intent,
      );
      expect(result.status, 'accepted');
      expect(result.revision, ++previous);
    }
  });

  for (final scene in ['lost-ack', 'local-ack']) {
    test(
      'actual $scene unknown→pending→reconstructed query keeps originalID',
      () {
        final intent = OrganizationAnnouncementIntent.parse(
          hostWire('$scene-01-unknown-request'),
        );
        final unknown = OrganizationAnnouncementOutcome.parseManage(
          hostWire('$scene-01-unknown-response'),
          intent,
        );
        expect(unknown.unresolved, isTrue);
        expect(unknown.revision, isNull);
        expect(hostWire('$scene-02-pending-request'), {
          'schemaVersion': 1,
          'kind': 'pending',
          'offset': 0,
        });
        final pending = OrganizationAnnouncementPendingPage.parse(
          hostWire('$scene-02-pending-response'),
          expectedOffset: 0,
        );
        expect(pending.totalCount, 1);
        expect(
          pending.next,
          isNull,
          reason: 'Only the proven terminal page omits next',
        );
        expect(pending.items.single.requestId, intent.requestId);
        expect(hostWire('$scene-03-restarted-query-request'), {
          'schemaVersion': 1,
          'kind': 'query',
          'requestId': intent.requestId,
        });
        final recovered = OrganizationAnnouncementOutcome.parseQuery(
          hostWire('$scene-03-restarted-query-response'),
          intent.requestId,
          expectedSourceRef: intent.sourceRef,
          expectedAction: intent.action,
        );
        expect(recovered.status, 'accepted');
        expect(recovered.revision, 2);
      },
    );
  }

  test('editor malformed/missing/extra authorization facts are rejected', () {
    final row = hostWire('lifecycle-01-editor-response');
    for (final changed in <Map<String, Object?>>[
      {...row}..remove('current'),
      {...row, 'current': {}},
      {...row, 'schemaVersion': 1.0},
      {...row, 'revision': -1},
      {...row, 'revision': 1.5},
      {...row, 'editRef': 'A' * 32},
      {...row, 'sourceRef': 'officialFleet:8'},
      {
        ...row,
        'allowedActions': ['publish', 'edit'],
      },
      {...row, 'rootProof': 'caller'},
    ]) {
      expect(
        () => OrganizationAnnouncementEditor.parse(changed, 'officialFleet:7'),
        throwsFormatException,
      );
    }
  });

  test('strict intent union and receipt echo cannot change meaning', () {
    final row = hostWire('lifecycle-02-publish-request');
    final intent = OrganizationAnnouncementIntent.parse(row);
    for (final changed in <Map<String, Object?>>[
      {...row, 'announcementRef': null},
      {...row, 'operationId': 'caller'},
      {...row, 'action': 'withdraw'},
      {...row, 'sourceRef': 'officialFleet:9223372036854775808'},
    ]) {
      expect(
        () => OrganizationAnnouncementIntent.parse(changed),
        throwsFormatException,
      );
    }
    final response = hostWire('lifecycle-02-publish-response');
    for (final changed in <Map<String, Object?>>[
      {...response, 'requestId': 'f' * 32},
      {...response, 'editRef': 'f' * 32},
      {...response, 'status': 'unknown'},
      {...response, 'error': 'failure'},
      {...response, 'revision': 0},
      {...response, 'policyRevision': 3},
    ]) {
      expect(
        () => OrganizationAnnouncementOutcome.parseManage(changed, intent),
        throwsFormatException,
      );
    }
    final withdraw = hostWire('lifecycle-06-withdraw-request');
    expect(
      () => OrganizationAnnouncementIntent.parse({...withdraw, 'title': null}),
      throwsFormatException,
    );
  });

  test(
    'only actual terminal count permits absent next; types remain strict',
    () {
      final terminal = hostWire('lost-ack-02-pending-response');
      expect(
        OrganizationAnnouncementPendingPage.parse(
          terminal,
          expectedOffset: 0,
        ).next,
        isNull,
      );
      for (final changed in <Map<String, Object?>>[
        {...terminal, 'totalCount': 21},
        {...terminal, 'next': 20},
        {...terminal, 'next': 20.0},
        {...terminal, 'offset': 20},
        {...terminal, 'items': []},
        {...terminal, 'rawSubject': 'private'},
      ]) {
        expect(
          () => OrganizationAnnouncementPendingPage.parse(
            changed,
            expectedOffset: 0,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
