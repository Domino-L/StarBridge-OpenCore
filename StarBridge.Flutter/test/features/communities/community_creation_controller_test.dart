import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_creation_controller.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';

import 'community_creation_bridge_test.dart' show optionsPayload;

class CreationPort implements CommunityCreationPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final writes = <(String, Map<String, Object?>)>[];
  Completer<CommunityCreationOutcome>? pending;
  bool failOptions = false;
  CommunityCreationOutcome result = const CommunityCreationOutcome(
    'rejected',
    error: 'invalidDraft',
  );
  @override
  Future<CommunityCreationOptions> creationOptions() async {
    if (failOptions) throw StateError('fixture offline');
    return CommunityCreationOptions.parse(optionsPayload());
  }

  @override
  Future<CommunityCreationOutcome> createCommunity(
    String requestId,
    Map<String, Object?> draft,
  ) async {
    writes.add((requestId, draft));
    return pending?.future ?? result;
  }
}

void main() {
  late CreationPort port;
  late CommunityCreationController model;
  setUp(() {
    port = CreationPort();
    model = CommunityCreationController(port, port.changes.stream);
  });
  tearDown(() async {
    model.dispose();
    await port.changes.close();
  });

  test(
    'WPF defaults and immutable account-local draft; no writes on edit',
    () async {
      await model.load();
      expect(model.draft!['activeFrom'], '19:00');
      expect(model.draft!['joinPolicy'], 'Open');
      expect(model.draft!['activeSystemIds'], ['stanton']);
      expect(model.dirty, isFalse);
      model.update('name', 'Test Organization');
      expect(model.dirty, isTrue);
      expect(port.writes, isEmpty);
      expect(
        () => model.draft!['name'] = 'outside mutation',
        throwsUnsupportedError,
      );
      expect(model.update('ownerAccount', 'someone'), isFalse);
      expect(model.update('bannerImageData', 'disabled WPF feature'), isFalse);
      expect(model.update('tagIds', ['unknown']), isFalse);
      expect(model.update('tagIds', ['scouting', 'scouting']), isFalse);
      final tags = ['scouting'];
      model.update('tagIds', tags);
      tags.clear();
      expect(model.draft!['tagIds'], ['scouting']);
    },
  );

  test(
    'Explicit rejection preserves all input and permits a corrected intent',
    () async {
      await model.load();
      model.update('name', '  Test Organization  ');
      model.update('code', ' test ');
      model.update('logoImageData', 'data:image/png;base64,fixture');
      await model.submit();
      expect(port.writes.single.$2['name'], 'Test Organization');
      expect(port.writes.single.$2['code'], 'TEST');
      expect(port.writes.single.$1, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(model.draft!['code'], ' test ');
      expect(model.draft!['logoImageData'], 'data:image/png;base64,fixture');
      expect(model.locked, isFalse);
      model.update('code', 'changed');
      await model.submit();
      expect(port.writes, hasLength(2));
      expect(port.writes[0].$1, isNot(port.writes[1].$1));
    },
  );

  test(
    'Double submit and uncertain acknowledgment cannot duplicate a create',
    () async {
      await model.load();
      port.pending = Completer();
      final submission = model.submit();
      await model.submit();
      expect(model.update('name', 'different'), isFalse);
      expect(port.writes, hasLength(1));
      port.pending!.complete(const CommunityCreationOutcome('unknown'));
      await submission;
      expect(model.locked, isTrue);
      await model.submit();
      expect(port.writes, hasLength(1));
    },
  );

  test(
    'Account invalidation erases draft/images and ignores a late success',
    () async {
      await model.load();
      model.update('name', 'Private Draft');
      model.update('logoImageData', 'private-image');
      port.pending = Completer();
      final submission = model.submit();
      port.changes.add(null);
      port.pending!.complete(
        const CommunityCreationOutcome(
          'accepted',
          organization: CommunityCard(
            targetRef: 'a',
            name: 'Old account organization',
            relationship: 'owner',
          ),
        ),
      );
      await submission;
      expect(model.invalidated, isTrue);
      expect(model.draft, isNull);
      expect(model.options, isNull);
      expect(model.outcome, isNull);
      await model.load();
      expect(model.draft, isNull);
    },
  );

  test(
    'Options failure may be retried without creating a default fake catalog',
    () async {
      port.failOptions = true;
      await model.load();
      expect(model.options, isNull);
      expect(model.error, 'optionsUnavailable');
      port.failOptions = false;
      await model.load();
      expect(model.options, isNotNull);
      expect(port.writes, isEmpty);
    },
  );

  test(
    'Only confirmed ownership clears dirty state and ends editing',
    () async {
      await model.load();
      model.update('name', 'Test Organization');
      port.result = const CommunityCreationOutcome(
        'accepted',
        organization: CommunityCard(
          targetRef: 'a',
          name: 'Test Organization',
          relationship: 'owner',
        ),
      );
      await model.submit();
      expect(model.dirty, isFalse);
      expect(model.locked, isTrue);
      expect(model.outcome?.organization?.name, 'Test Organization');
    },
  );
}
