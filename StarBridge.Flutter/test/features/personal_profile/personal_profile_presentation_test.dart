import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';

void main() {
  test('explicit groups preserve unedited wire values and clear intent', () {
    final lease = PersonalProfilePresentation.fromProfile({
      'revision': 9,
      'avatarStyle': 2,
      'wallpaperId': 'aurora',
      'presentation': {
        'schemaVersion': 1,
        'sourceVersion': 'b' * 64,
        'origins': {
          for (final group in PersonalProfilePresentation.groups)
            group: 'linkedLegacy',
        },
      },
      'content': {
        'introduction': 'Inherited',
        'modules': [
          {'id': 'rich-module'},
        ],
        'favoriteShipCodes': ['unresolved'],
        'presenceIntent': 'busy',
      },
    })!;
    expect(lease.editRequest({}), isNull);
    final request = lease.editRequest({
      'introduction': {'introduction': ''},
    })!;
    expect(request['editedGroups'], ['introduction']);
    expect(request['sourceVersion'], 'b' * 64);
    expect(request['expectedRevision'], 9);
    final content = request['content']! as Map;
    expect(content['introduction'], '');
    expect(content['modules'], [
      {'id': 'rich-module'},
    ]);
    expect(content['favoriteShipCodes'], ['unresolved']);
    expect(content.containsKey('presenceIntent'), isFalse);
    expect(lease.content['introduction'], 'Inherited');
    expect(
      () => lease.editRequest({
        'introduction': {'visibility': 'public'},
      }),
      throwsFormatException,
    );
    expect(
      () => lease.editRequest({
        'identity': {'callSign': 'Other'},
      }),
      throwsFormatException,
    );
    expect(() => request['expectedRevision'] = 10, throwsUnsupportedError);
  });
  Map<String, Object?> fixture() => {
    'revision': 7,
    'avatarStyle': 0,
    'wallpaperId': 'none',
    'presentation': {
      'schemaVersion': 1,
      'sourceVersion': 'a' * 64,
      'origins': {
        for (final group in PersonalProfilePresentation.groups)
          group: 'unknown',
      },
    },
    'content': {
      'introduction': '  exact  ',
      'modules': [
        {
          'id': 'rich-local-layout',
          'favoriteShipIds': ['unresolved-instance'],
        },
      ],
    },
  };
  test('retains exact content and deep freezes source lease', () {
    final wire = fixture();
    final lease = PersonalProfilePresentation.fromProfile(wire)!;
    expect(lease.revision, 7);
    expect(lease.sourceVersion, 'a' * 64);
    expect(lease.origins['introduction'], 'unknown');
    expect(lease.content['introduction'], '  exact  ');
    final modules = lease.content['modules']! as List;
    expect((modules.single as Map)['id'], 'rich-local-layout');
    expect(() => modules.clear(), throwsUnsupportedError);
    expect(
      () => (modules.single as Map)['id'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => lease.origins['introduction'] = 'custom',
      throwsUnsupportedError,
    );
    (wire['content']! as Map)['introduction'] = 'mutated';
    expect(lease.content['introduction'], '  exact  ');
  });
  test('old backend has no inferred default or migration provenance', () {
    expect(PersonalProfilePresentation.fromProfile({'revision': 42}), isNull);
  });
  test('malformed provenance fails closed', () {
    for (final metadata in [
      {'schemaVersion': 2, 'sourceVersion': null, 'origins': {}},
      {'schemaVersion': 1, 'sourceVersion': 'wrong', 'origins': {}},
      {
        'schemaVersion': 1,
        'sourceVersion': null,
        'origins': {'introduction': 'custom'},
      },
      {
        'schemaVersion': 1,
        'sourceVersion': null,
        'origins': {
          for (final group in PersonalProfilePresentation.groups)
            group: 'guessed',
        },
      },
    ]) {
      expect(
        () => PersonalProfilePresentation.fromProfile({
          ...fixture(),
          'presentation': metadata,
        }),
        throwsFormatException,
      );
    }
  });
}
