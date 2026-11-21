import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_auto_import.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_local_projection.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_request_operation.dart';

import 'local_personal_profile_test.dart'
    show Harness, LocalProfileConnection, shipA, shipB;

void main() {
  group('import plan', () {
    test('different nonempty default introduction is eligible', () {
      expect(_plan(_saved()).edits, {
        'introduction': {'introduction': 'Local revision'},
      });
    });

    for (final origin in ['custom', 'imported', 'unknown']) {
      test('$origin origin never imports', () {
        expect(_plan(_saved(), origin: origin).edits, isEmpty);
      });
    }

    test('empty local group is skipped', () {
      expect(_plan(_saved(about: '  ')).edits, isEmpty);
    });

    test('early S2 empty fields are skipped', () {
      expect(
        _plan({
          ..._saved(about: '', preserveEmpty: false),
          'avatarStyle': 0,
          'wallpaperId': 'none',
          'playStyle': {'roles': <String>[], 'interests': <String>[]},
          'mainRole': '',
          'favoriteShipIds': <String>[],
          'modules': [
            {
              'id': 'favorite-ships',
              'span': 3,
              'isVisible': true,
              'position': 0,
              'favoriteShipIds': <String>[],
            },
          ],
          'schedule': {'windows': [], 'rhythm': 'casual', 'timeZoneId': ''},
        }, defaults: PersonalProfilePresentation.groups).edits,
        isEmpty,
      );
    });

    test('same displayed content is skipped', () {
      expect(_plan(_saved(about: 'Previous page')).edits, isEmpty);
    });

    test('favorite instance IDs resolve to flat ship codes', () {
      final plan = _plan(
        {
          ..._saved(),
          'favoriteShipIds': [shipA],
        },
        defaults: {'favorites'},
        hangar: const LocalHangarSnapshot(
          revision: 1,
          ships: [
            LocalHangarShip(
              id: shipA,
              title: 'Carrack',
              catalogId: 'ANVL_Carrack',
            ),
          ],
        ),
      );
      expect(plan.edits, {
        'favorites': {
          'favoriteShipCodes': ['ANVL_Carrack'],
        },
      });
    });

    test(
      'an unresolved favorite stays pending instead of writing a partial list',
      () {
        final plan = _plan(
          {
            ..._saved(),
            'favoriteShipIds': [shipA],
          },
          defaults: {'favorites'},
        );
        expect(plan.edits, isEmpty);
        expect(plan.unresolved, {'favorites'});
      },
    );

    test('main role is written only with playStyle and its selected roles', () {
      final plan = _plan(
        {
          ..._saved(),
          'playStyle': {
            'roles': ['pilot', 'gunner'],
          },
          'mainRole': 'gunner',
        },
        defaults: {'playStyle'},
      );
      expect(plan.edits, {
        'playStyle': {
          'skilledRoles': ['pilot', 'gunner'],
          'mainRole': 'gunner',
        },
      });
    });

    test('showcase list and fourth-ship edits belong to layout', () {
      const module = {
        'id': 'favorite-ships',
        'span': 3,
        'isVisible': true,
        'position': 0,
      };
      final plan = _plan(
        {
          ..._saved(),
          'modules': [
            {
              ...module,
              'favoriteShipIds': [shipA],
            },
          ],
          'showcases': [
            {'id': 'trade-card', 'isVisible': false},
          ],
        },
        defaults: {'layout'},
        remoteContent: {
          'modules': [
            {...module, 'order': 0, 'favoriteShipIds': <String>[]},
          ],
          'favoriteShowcaseExtras': {'favorite-ships': shipA},
        },
      );
      expect(plan.edits.keys, ['layout']);
      expect(plan.edits['layout']!['favoriteShowcaseExtras'], isEmpty);
      expect(
        plan.edits['layout']!['showcases'],
        contains(equals({'id': 'trade-card', 'isVisible': false})),
      );
    });

    test('two showcases retain their distinct fourth ships during import', () {
      const extraA = '33333333333333333333333333333333';
      const extraB = '44444444444444444444444444444444';
      const extras = {'favorite-ships': extraA, 'favorite-ships-1': extraB};
      final plan = _plan(
        {
          ..._saved(),
          'modules': [
            _favoriteModule('favorite-ships', 0, [shipA]),
            _favoriteModule('favorite-ships-1', 3, [shipB]),
          ],
        },
        defaults: {'layout'},
        remoteContent: {
          'modules': [
            {..._favoriteModule('favorite-ships', 0, []), 'order': 0},
            {..._favoriteModule('favorite-ships-1', 3, []), 'order': 1},
          ],
          'favoriteShowcaseExtras': extras,
        },
      );
      final modules = (plan.edits['layout']!['modules'] as List).cast<Map>();
      expect(modules.map((module) => module['id']), containsAll(extras.keys));
      expect(
        plan.edits['layout']?['favoriteShowcaseExtras'],
        anyOf(isNull, extras),
      );
      expect(plan.unresolved, isEmpty);
    });

    test('normalization mismatch isolates the playStyle group', () {
      final plan = _plan(
        {
          ..._saved(),
          'playStyle': {
            'roles': ['Legacy role', 'legacy role'],
          },
          'avatarStyle': 2,
        },
        defaults: {'playStyle', 'avatarStyle'},
      );
      expect(plan.edits, {
        'avatarStyle': {'avatarStyle': 2},
      });
      expect(plan.unresolved, {'playStyle'});
    });

    test('schedule with the same day set is skipped', () {
      final plan = _plan(
        {
          ..._saved(),
          'schedule': {
            'rhythm': 'casual',
            'timeZoneId': 'UTC',
            'windows': [
              {
                'days': [5, 1],
                'startTime': '19:00',
                'endTime': '22:00',
              },
            ],
          },
        },
        defaults: {'schedule'},
      );
      expect(plan.edits, isEmpty);
    });

    test('a write can restore nullable fields omitted from the Host read', () {
      final presentation = _source();
      final request = presentation.editRequest(_plan(_saved()).edits)!;
      final content = request['content']! as Map;
      expect(content.containsKey('availabilityTimeZoneId'), isTrue);
      expect(content['availabilityTimeZoneId'], isNull);
      expect(content['availabilityWindows'], isEmpty);
    });
  });

  group('owner read', () {
    test('one import, then a readback of the saved page', () async {
      final h = _harness();
      final originalContent = h.connection.content;
      _acceptNextWrite(h);
      final result = await h.port.read();
      expect(result.about, 'Local revision');
      expect(result.presentation?.origins['introduction'], 'custom');
      expect(result.local?.autoImportPending, isFalse);
      expect(h.remote.reads, 2);
      expect(h.remote.writes, 1);
      expect(h.connection.content, same(originalContent));
      expect(h.connection.revision, 1);
      expect(_localWrites(h), isEmpty);
    });

    test('a conflict readback drops a group already saved elsewhere', () async {
      final h = _harness();
      h.remote.onPageSave = (_, _) {
        _setPage(h, about: 'Other device', origin: 'custom', revision: 8);
        return _conflict;
      };
      final result = await h.port.read();
      expect(result.about, 'Other device');
      expect(result.local?.autoImportPending, isFalse);
      expect(h.remote.writes, 1);
      expect(h.remote.reads, 2);
    });

    test('a conflict retries the remaining default group once', () async {
      final h = _harness();
      h.remote.onPageSave = (expected, edits) {
        expect(edits.keys, ['introduction']);
        if (h.remote.writes == 1) {
          _setPage(h, about: 'New inherited page', revision: 8);
          return _conflict;
        }
        expect(expected.revision, 8);
        _setPage(h, about: 'Local revision', origin: 'custom', revision: 9);
        return _complete;
      };
      expect((await h.port.read()).presentation?.revision, 9);
      expect(h.remote.writes, 2);
      expect(h.remote.reads, 3);
    });

    test('a second conflict defers the rest until the next read', () async {
      final h = _harness();
      h.remote.onPageSave = (_, _) => _conflict;
      final result = await h.port.read();
      expect(h.remote.writes, 2);
      expect(h.remote.reads, 2);
      expect(result.about, 'Local revision');
      expect(result.local?.autoImportPending, isTrue);
    });

    for (final disconnected in [false, true]) {
      test(
        '${disconnected ? 'disconnect' : 'uncertain reply'} retains local content',
        () async {
          final h = _harness();
          h.remote.onPageSave = (_, _) {
            if (disconnected) throw const BridgeDisconnectedException();
            return const PersonalProfileActionResult(
              PersonalProfileActionOutcome.failed,
              failureKey: 'profile.error.writeUnconfirmed',
            );
          };
          final result = await h.port.read();
          expect(result.about, 'Local revision');
          expect(result.local?.autoImportPending, isTrue);
          expect(result.failureKey, isNull);
          expect(h.remote.writes, 1);
          expect(h.remote.reads, 1);
          _acceptNextWrite(h);
          expect((await h.port.read()).local?.autoImportPending, isTrue);
          expect(h.remote.writes, 1);
          _setPage(h, about: 'Previous page', origin: 'default', revision: 8);
          expect((await h.port.read()).local?.autoImportPending, isFalse);
          expect(h.remote.writes, 2);
        },
      );
    }

    test('concurrent same-owner reads share the in-flight import', () async {
      final h = _harness();
      final started = Completer<void>(), finish = Completer<void>();
      h.remote.onPageSave = (expected, _) async {
        started.complete();
        await finish.future;
        _setPage(
          h,
          about: 'Local revision',
          origin: 'custom',
          revision: expected.revision + 1,
        );
        return _complete;
      };
      final first = h.port.read();
      await started.future;
      final second = h.port.read();
      finish.complete();
      expect(await first, same(await second));
      expect(h.remote.writes, 1);
      expect(h.remote.reads, 2);
    });

    test('read during an unfinished user save does not import', () async {
      final h = _harness(saved: false);
      final initial = await h.port.read();
      final started = Completer<void>(), finish = Completer<void>();
      h.remote.onPageSave = (_, edits) async {
        expect(edits.keys, ['avatarStyle']);
        started.complete();
        await finish.future;
        return _complete;
      };
      final saving = h.port.save(
        PersonalProfileEdit(
          callSign: initial.callSign,
          about: initial.about,
          avatarStyle: (initial.avatarStyle + 1) % 4,
          wallpaperId: initial.wallpaperId,
          visibility: initial.visibility,
          moduleLayout: initial.moduleLayout,
        ),
      );
      await started.future;
      final changed = h.port.changes.first;
      expect(await h.port.read(), same(initial));
      expect(h.remote.reads, 2);
      expect(h.remote.writes, 1);
      finish.complete();
      expect((await saving).outcome, PersonalProfileActionOutcome.completed);
      await changed;
    });

    test('legacySignedIn keeps the legacy local page', () async {
      final h = _harness(legacy: true);
      expect((await h.port.read()).about, 'Local revision');
      expect(h.remote.writes, 0);
    });

    test('no remote presentation means no auto import', () async {
      final h = _harness();
      h.remote.presentation = null;
      expect((await h.port.read()).about, 'Local revision');
      expect(h.remote.writes, 0);
    });

    test('an unsuccessful remote read cannot authorize an import', () async {
      final h = _harness()..remote.available = false;
      expect(
        (await h.port.read()).availability,
        PersonalProfileAvailability.unavailable,
      );
      expect(h.remote.writes, 0);
    });

    test(
      'signedIn imports the legacy-owned file returned through the Host alias',
      () async {
        final h = Harness(connection: _MigratedProfileConnection());
        addTearDown(h.close);
        _setPage(h, origin: 'linkedLegacy');
        _acceptNextWrite(h);
        final result = await h.port.read();
        expect(h.remote.pageGroups!['introduction'], {
          'introduction': 'Saved on the legacy account',
        });
        expect(result.about, 'Saved on the legacy account');
        expect(
          h.connection.requests
              .singleWhere(
                (request) => request.name == 'personalProfile.localRead',
              )
              .accountContext
              ?.subject,
          'synthetic-scm-owner',
        );
        expect(_localWrites(h), isEmpty);
      },
    );

    test(
      'the second device yields a custom group to the first device',
      () async {
        final first = _harness(), second = _harness();
        _acceptNextWrite(first);
        final winner = await first.port.read();
        second.connection.content = _saved(about: 'Second device local edit');
        second.remote
          ..about = winner.about
          ..presentation = winner.presentation;
        final read = await second.port.read();
        expect(read.about, winner.about);
        expect(read.local?.autoImportPending, isFalse);
        expect(second.remote.writes, 0);
        expect(_localWrites(second), isEmpty);
      },
    );
  });
}

const _complete = PersonalProfileActionResult(
  PersonalProfileActionOutcome.completed,
);
const _conflict = PersonalProfileActionResult(
  PersonalProfileActionOutcome.failed,
  failureKey: 'profile.error.writeConflict',
);

Map<String, Object?> _favoriteModule(
  String id,
  int position,
  List<String> picks,
) => {
  'id': id,
  'span': 3,
  'isVisible': true,
  'position': position,
  'favoriteShipIds': picks,
};

Map<String, Object?> _saved({
  String about = 'Local revision',
  bool preserveEmpty = true,
}) => {
  'introduction': about,
  'preserveEmptyFields': preserveEmpty,
  'modules': <Map<String, Object?>>[],
};

Map<String, Object?> _metadata({
  String origin = 'default',
  Set<String> defaults = const {'introduction'},
}) => {
  'schemaVersion': 1,
  'sourceVersion': null,
  'origins': {
    for (final group in PersonalProfilePresentation.groups)
      group: defaults.contains(group) ? origin : 'custom',
  },
};

PersonalProfilePresentation _source({
  String origin = 'default',
  int revision = 7,
}) => PersonalProfilePresentation.fromProfile({
  'revision': revision,
  'avatarStyle': 0,
  'wallpaperId': 'none',
  'presentation': _metadata(origin: origin),
  'content': <String, Object?>{},
})!;

PersonalProfileAutoImportPlan _plan(
  Map<String, Object?> content, {
  String origin = 'default',
  Set<String> defaults = const {'introduction'},
  LocalHangarSnapshot? hangar,
  Map<String, Object?> remoteContent = const {},
}) {
  final remote = parsePersonalProfileSnapshot({
    'schemaVersion': 1,
    'editable': true,
    'profile': {
      'revision': 7,
      'avatarStyle': 1,
      'wallpaperId': 'remote-wallpaper',
      'visibility': 'private',
      'identity': {'callSign': 'Fixture', 'gameHandle': 'Fixture'},
      'presentation': _metadata(origin: origin, defaults: defaults),
      'content': {
        'introduction': 'Previous page',
        'mainRole': 'pilot',
        'skilledRoles': ['pilot'],
        'favoriteShipCodes': <String>[],
        'showOnlineTime': true,
        'availabilityTimeZoneId': 'UTC',
        'availabilityWindows': [
          {
            'days': [1, 5],
            'startTime': '19:00',
            'endTime': '22:00',
          },
        ],
        ...remoteContent,
      },
    },
  });
  return planPersonalProfileAutoImport(
    projectLocalProfile(remote, content, hangar, null),
    projectLocalProfile(
      remote,
      content,
      hangar,
      null,
      preferLocalGroups: defaults,
    ),
    content,
  );
}

Harness _harness({bool legacy = false, bool saved = true}) {
  final h = Harness(legacy: legacy);
  addTearDown(h.close);
  _setPage(h);
  if (saved) {
    h.connection.content = _saved();
    h.connection.revision = 1;
  }
  return h;
}

void _setPage(
  Harness h, {
  String about = 'Previous page',
  String origin = 'default',
  int revision = 7,
}) {
  h.remote
    ..about = about
    ..presentation = _source(origin: origin, revision: revision);
}

void _acceptNextWrite(Harness h) {
  h.remote.onPageSave = (expected, edits) {
    expect(edits.keys, ['introduction']);
    _setPage(
      h,
      about: edits['introduction']!['introduction']! as String,
      origin: 'custom',
      revision: expected.revision + 1,
    );
    return _complete;
  };
}

Iterable<BridgeEnvelope> _localWrites(Harness h) => h.connection.requests.where(
  (request) => request.name == 'personalProfile.localSave',
);

class _MigratedProfileConnection extends LocalProfileConnection {
  _MigratedProfileConnection() {
    subject = 'synthetic-scm-owner';
  }

  final _aliases = {'synthetic-scm-owner': 'synthetic-legacy-owner'};
  final _files = {
    'synthetic-legacy-owner': _saved(about: 'Saved on the legacy account'),
  };

  @override
  Future<void> send(BridgeEnvelope request) {
    if (request.name == 'personalProfile.localRead') {
      content = _files[_aliases[request.accountContext?.subject]];
      revision = content == null ? 0 : 1;
    }
    return super.send(request);
  }
}
