import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/legacy_profile_migration.dart';

void main() {
  test(
    'full replacement is explicit and cannot be mixed with selected content',
    () {
      final selection = LegacyProfileImportSelection(
        modules: [],
        replaceAllDisplayContent: true,
      );
      expect(selection.toJson()['replaceAllDisplayContent'], true);
      expect(
        () => LegacyProfileImportSelection(
          modules: ['hangar-summary'],
          replaceAllDisplayContent: true,
        ),
        throwsArgumentError,
      );
      final view = LegacyProfileMigrationView.fromJson({
        'state': 'completed',
        'previewId': 'full-ticket',
        'conflict': false,
        'choices': {
          'version': 2,
          'modules': ['hangar-summary'],
          'replaceModules': ['hangar-summary'],
          'useLegacyCallSign': true,
          'useLegacyAvatar': false,
          'needsReselection': <String>[],
        },
        'presentation': {
          'callSign': 'Old',
          'avatarStyle': 1,
          'wallpaperId': 'none',
          'content': <String, Object?>{'introduction': 'Old introduction'},
        },
      });
      expect(view.choices!.version, 2);
      expect(view.presentation!['callSign'], 'Old');
      expect(view.selectedContent, isNull);
      expect(
        () => LegacyProfileMigrationView.fromJson({
          'state': 'completed',
          'conflict': true,
          'choices': {
            'version': 2,
            'modules': <String>[],
            'replaceModules': <String>[],
            'useLegacyCallSign': true,
            'needsReselection': <String>[],
          },
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'follow-up selection explicitly carries the previous completed ticket',
    () {
      final selection = LegacyProfileImportSelection(
        modules: [],
        useLegacyAvatar: true,
        previousCompletedPreviewId: 'completed-ticket',
      );
      expect(
        selection.toJson()['previousCompletedPreviewId'],
        'completed-ticket',
      );
      expect(
        LegacyProfileImportSelection(
          modules: [],
          useLegacyCallSign: true,
        ).toJson(),
        isNot(contains('previousCompletedPreviewId')),
      );
      for (final invalid in ['', ' ', 'bad\nreceipt', 'x' * 65]) {
        expect(
          () => LegacyProfileImportSelection(
            modules: [],
            useLegacyAvatar: true,
            previousCompletedPreviewId: invalid,
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'selected content excludes unselected fields and validates exact modules',
    () {
      final selection = LegacyProfileImportSelection(
        modules: ['hangar-summary'],
      );
      final data = <String, Object?>{
        'callSign': null,
        'modules': [
          <String, Object?>{'id': 'hangar-summary', 'span': 2},
        ],
      };
      final parsed = LegacyProfileSelectedContent.fromJson(data, selection);
      expect(parsed.modules, {'hangar-summary': 2});
      expect(() => parsed.modules['inventory'] = 3, throwsUnsupportedError);
      for (final changed in <Map<String, Object?>>[
        {...data, 'callSign': 'unselected name'},
        {...data, 'skilledRoles': <String>[]},
        {
          ...data,
          'favoriteShipCodes': ['old ship'],
        },
        {...data, 'modules': <Object>[]},
        {
          ...data,
          'modules': [
            <String, Object?>{'id': 'hangar-summary', 'span': 4},
          ],
        },
        {
          ...data,
          'modules': [
            <String, Object?>{'id': 'favorite-ships', 'span': 2},
          ],
        },
      ]) {
        expect(
          () => LegacyProfileSelectedContent.fromJson(changed, selection),
          throwsFormatException,
        );
      }
    },
  );
  test('collaboration content is required only when selected', () {
    final selection = LegacyProfileImportSelection(
      modules: ['skilled-roles'],
      useLegacyCallSign: true,
    );
    final data = <String, Object?>{
      'callSign': 'Imported',
      'modules': [
        <String, Object?>{'id': 'skilled-roles', 'span': 2},
      ],
      'skilledRoles': ['pilot'],
      'supportCapabilities': <String>[],
      'participationInterests': ['exploration'],
    };
    final parsed = LegacyProfileSelectedContent.fromJson(data, selection);
    expect(parsed.callSign, 'Imported');
    expect(parsed.skilledRoles, ['pilot']);
    expect(
      () => LegacyProfileSelectedContent.fromJson({
        ...data,
        'skilledRoles': null,
      }, selection),
      throwsFormatException,
    );
    expect(
      () => LegacyProfileSelectedContent.fromJson({
        ...data,
        'skilledRoles': ['pilot', 'pilot'],
      }, selection),
      throwsFormatException,
    );
  });
  test('selected avatar without preview cannot produce a confirmable view', () {
    final summary = <String, Object?>{
      'callSign': 'Current',
      'introduction': '',
      'modules': 0,
      'favorites': 0,
      'playTimeSeconds': null,
    };
    expect(
      () => LegacyProfileMigrationView.fromJson({
        'state': 'previewed',
        'previewId': 'ticket',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 15))
            .toIso8601String(),
        'source': summary,
        'target': summary,
        'choices': {
          'version': 1,
          'modules': <String>[],
          'replaceModules': <String>[],
          'useLegacyCallSign': false,
          'useLegacyAvatar': true,
          'needsReselection': <String>[],
        },
      }),
      throwsFormatException,
    );
  });
  test(
    'avatar preview accepts bounded PNG and rejects remote or oversized images',
    () {
      final bytes = Uint8List(24);
      bytes.setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
      final header = ByteData.sublistView(bytes);
      header.setUint32(16, 128);
      header.setUint32(20, 64);
      Map<String, Object?> response(String image) => {
        'state': 'completed',
        'avatarPreview': image,
      };
      String image() => 'data:image/png;base64,${base64Encode(bytes)}';
      expect(
        LegacyProfileMigrationView.fromJson(response(image())).avatarPreview,
        bytes,
      );
      expect(
        () => LegacyProfileMigrationView.fromJson(
          response('https://invalid.example/a.png'),
        ),
        throwsFormatException,
      );
      header.setUint32(16, 129);
      expect(
        () => LegacyProfileMigrationView.fromJson(response(image())),
        throwsFormatException,
      );
      header.setUint32(16, 0);
      expect(
        () => LegacyProfileMigrationView.fromJson(response(image())),
        throwsFormatException,
      );
      expect(
        () => LegacyProfileMigrationView.fromJson(
          response('data:image/png;base64,%%%'),
        ),
        throwsFormatException,
      );
    },
  );
  test('selection is explicit and immutable', () {
    final modules = ['hangar-summary'];
    final selection = LegacyProfileImportSelection(modules: modules);
    modules.add('favorite-ships');
    expect(selection.modules, ['hangar-summary']);
    expect(selection.toJson(), {
      'modules': ['hangar-summary'],
      'replaceModules': <String>[],
      'useLegacyCallSign': false,
      'useLegacyAvatar': false,
    });
    expect(
      () => selection.modules.add('skilled-roles'),
      throwsUnsupportedError,
    );
  });
  test('no implicit all import or inventory selection', () {
    for (final modules in [
      <String>[],
      ['inventory'],
      ['hangar-summary', 'hangar-summary'],
    ]) {
      expect(
        () => LegacyProfileImportSelection(modules: modules),
        throwsArgumentError,
      );
    }
    expect(
      () => LegacyProfileImportSelection(
        modules: ['hangar-summary'],
        replaceModules: ['favorite-ships'],
      ),
      throwsArgumentError,
    );
    expect(
      LegacyProfileImportSelection(
        modules: [],
        useLegacyCallSign: true,
      ).modules,
      isEmpty,
    );
  });
  test('receipt retains selection and rejects unselected references', () {
    final receipt = <String, Object?>{
      'version': 1,
      'modules': ['favorite-ships'],
      'replaceModules': <String>[],
      'useLegacyCallSign': false,
      'needsReselection': ['favorite-ships'],
    };
    expect(LegacyProfileImportChoices.fromJson(receipt).needsReselection, [
      'favorite-ships',
    ]);
    expect(
      () => LegacyProfileImportChoices.fromJson({
        ...receipt,
        'needsReselection': ['hangar-summary'],
      }),
      throwsFormatException,
    );
    expect(
      () => LegacyProfileImportChoices.fromJson({...receipt, 'version': 2}),
      throwsFormatException,
    );
  });
  test('avatar can be selected without callsign or modules', () {
    final selection = LegacyProfileImportSelection(
      modules: [],
      useLegacyAvatar: true,
    );
    expect(selection.useLegacyCallSign, isFalse);
    expect(selection.toJson()['useLegacyAvatar'], isTrue);
    final receipt = LegacyProfileImportChoices.fromJson({
      'version': 1,
      ...selection.toJson(),
      'needsReselection': <String>[],
    });
    expect(receipt.selection.useLegacyAvatar, isTrue);
    expect(receipt.selection.modules, isEmpty);
  });
}
