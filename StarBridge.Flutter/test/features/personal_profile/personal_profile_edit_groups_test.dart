import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_presentation.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_edit_groups.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

void main() {
  test(
    'schedule wire days use Monday-first order regardless of click order',
    () {
      const baseline = PersonalProfileSnapshot.signedOut();
      const window = PersonalProfileAvailabilityWindow(
        days: [0, 5, 1],
        startTime: '19:00',
        endTime: '22:00',
      );
      final groups = personalProfileEditGroups(
        baseline,
        const PersonalProfileEdit(
          callSign: '',
          about: '',
          avatarStyle: 0,
          wallpaperId: 'none',
          visibility: PersonalProfileVisibility.onlyMe,
          moduleLayout: [],
          schedule: PersonalProfileSchedule(
            timeZoneId: 'UTC',
            rhythm: PersonalProfileActivityRhythm.casual,
            windows: [window],
          ),
        ),
      );
      final windows = groups['schedule']!['availabilityWindows']! as List;
      expect(windows.single['days'], [1, 5, 0]);
      expect(window.days, [0, 5, 1]);
    },
  );
  final modules = List.generate(
    64,
    (index) => PersonalProfileModuleLayoutItem(
      moduleId: index == 0 ? 'favorite-ships' : 'favorite-ships-$index',
      size: PersonalProfileModuleSize.one,
      isVisible: false,
      position: -1,
      favoriteShipIds: [index.toRadixString(16).padLeft(32, '0')],
    ),
  );
  final displayed = PersonalProfileSnapshot.available(
    callSign: 'Existing',
    gameHandle: 'Synthetic',
    about: 'Visible introduction',
    avatarStyle: 2,
    wallpaperId: 'none',
    visibility: PersonalProfileVisibility.onlyMe,
    presenceIntent: PersonalProfilePresenceIntent.busy,
    affiliations: const [],
    availabilityWindows: const [],
    timeZoneLabel: '',
    gameplayMinutes: 0,
    activityRhythm: PersonalProfileActivityRhythm.casual,
    roles: const [],
    participationInterests: const [],
    supportCapabilities: const [],
    shipWishlist: const [],
    favoriteShips: const [],
    hangarSummary: const PersonalProfileHangarSummary.empty(),
    moduleLayout: modules,
  );
  PersonalProfileEdit edit({
    String? about,
    List<PersonalProfileModuleLayoutItem>? layout,
    PersonalProfilePlayStyle? style,
    PersonalProfileSchedule? schedule,
  }) => PersonalProfileEdit(
    callSign: 'Changed through another authority',
    about: about ?? displayed.about,
    avatarStyle: displayed.avatarStyle,
    wallpaperId: displayed.wallpaperId,
    visibility: PersonalProfileVisibility.everyone,
    moduleLayout: layout ?? modules,
    playStyle: style,
    schedule: schedule,
  );

  test(
    'unchanged displayed page does not freeze layout or write identity/privacy',
    () {
      expect(personalProfileEditGroups(displayed, edit()), isEmpty);
      expect(personalProfileEditGroups(displayed, edit(about: '')), {
        'introduction': {'introduction': ''},
      });
    },
  );

  test('layout edits retain all hidden instance selections', () {
    final changed = [...modules];
    changed[63] = changed[63].copyWith(isVisible: true, position: 0);
    final groups = personalProfileEditGroups(displayed, edit(layout: changed));
    expect(groups.keys, ['layout']);
    final wire = groups['layout']!['modules']! as List;
    expect(wire, hasLength(64));
    for (var index = 0; index < wire.length; index++) {
      expect(wire[index]['favoriteShipIds'], modules[index].favoriteShipIds);
      expect(wire[index]['order'], index);
    }
    expect(wire.first['isVisible'], isFalse);
    expect(wire.last['isVisible'], isTrue);
    expect(modules.last.isVisible, isFalse);
  });

  test(
    'actual editor groups produce the cross-language synthetic fixture',
    () async {
      final source = PersonalProfilePresentation.fromProfile({
        'revision': 7,
        'avatarStyle': 2,
        'wallpaperId': 'none',
        'presentation': {
          'schemaVersion': 1,
          'sourceVersion': 'a' * 64,
          'origins': {
            for (final group in PersonalProfilePresentation.groups)
              group: 'default',
          },
        },
        'content': {
          'showOnlineTime': false,
          'onlineTimeStart': '19:00',
          'onlineTimeEnd': '22:00',
          'activityRhythm': '休闲',
          'introduction': '',
          'skilledRoles': [],
          'supportCapabilities': [],
          'participationInterests': [],
          'shipWishlist': [],
          'favoriteShipCodes': [],
          'modules': [],
          'availabilityTimeZoneId': null,
          'availabilityWindows': [],
        },
      })!;
      final changed = [...modules];
      changed[63] = changed[63].copyWith(isVisible: true, position: 0);
      final groups = personalProfileEditGroups(
        displayed,
        edit(
          about: '中文 — synthetic 👩‍🚀',
          layout: changed,
          schedule: const PersonalProfileSchedule(
            timeZoneId: 'UTC',
            rhythm: PersonalProfileActivityRhythm.casual,
            windows: [
              PersonalProfileAvailabilityWindow(
                days: [0, 5, 1],
                startTime: '19:00',
                endTime: '22:00',
              ),
            ],
          ),
        ),
      );
      final request = source.editRequest(groups)!;
      expect(request['editedGroups'], ['introduction', 'layout', 'schedule']);
      expect((request['content']! as Map)['modules'], hasLength(64));
      // Optional test artifact only; never reads account data or changes product files.
      final destination = Platform.environment['STARBRIDGE_PAGE_EDIT_OUTPUT'];
      if (destination != null) {
        await File(destination)
            .writeAsString(jsonEncode(request), encoding: utf8);
      }
    },
  );

  test('explicit style and schedule clears stay within their own groups', () {
    final groups = personalProfileEditGroups(
      displayed,
      edit(
        style: const PersonalProfilePlayStyle(roles: []),
        schedule: const PersonalProfileSchedule(
          timeZoneId: '',
          rhythm: PersonalProfileActivityRhythm.casual,
          windows: [],
        ),
      ),
    );
    expect(groups.keys, ['playStyle', 'schedule']);
    expect(groups['playStyle'], {'skilledRoles': []});
    expect(groups['schedule'], {
      'showOnlineTime': false,
      'onlineTimeStart': '19:00',
      'onlineTimeEnd': '22:00',
      'availabilityTimeZoneId': null,
      'availabilityWindows': [],
      'activityRhythm': '休闲',
    });
  });
}
