import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

void main() {
  test('normalizes the WPF-compatible three by three profile grid', () {
    final normalized = PersonalProfileLayout.normalize(_defaultLayout());

    expect(normalized.where((item) => item.isVisible), hasLength(3));
    expect(
      _item(normalized, PersonalProfileModuleIds.favoriteShips).position,
      0,
    );
    expect(
      _item(normalized, PersonalProfileModuleIds.hangarSummary).position,
      3,
    );
    final roles = _item(normalized, PersonalProfileModuleIds.skilledRoles);
    expect(roles.position, 6);
    expect(roles.size, PersonalProfileModuleSize.two);
    expect(PersonalProfileLayout.occupiedCells(normalized), [
      true,
      true,
      true,
      true,
      true,
      true,
      true,
      true,
      false,
    ]);
  });

  test('moving a module displaces overlaps into the vacated row', () {
    final moved = PersonalProfileLayout.move(
      _defaultLayout(),
      PersonalProfileModuleIds.skilledRoles,
      0,
    );

    expect(moved.failure, PersonalProfileLayoutFailure.none);
    expect(
      _item(moved.layout, PersonalProfileModuleIds.skilledRoles).position,
      0,
    );
    expect(
      _item(moved.layout, PersonalProfileModuleIds.hangarSummary).position,
      3,
    );
    expect(
      _item(moved.layout, PersonalProfileModuleIds.favoriteShips).position,
      6,
    );
    expect(PersonalProfileLayout.occupiedCells(moved.layout), [
      true,
      true,
      false,
      true,
      true,
      true,
      true,
      true,
      true,
    ]);
  });

  test('size selection is constrained per module and remains placeable', () {
    final resized = PersonalProfileLayout.resize(
      _defaultLayout(),
      PersonalProfileModuleIds.favoriteShips,
      PersonalProfileModuleSize.two,
    );
    final fixedRoles = PersonalProfileLayout.resize(
      resized.layout,
      PersonalProfileModuleIds.skilledRoles,
      PersonalProfileModuleSize.three,
    );

    expect(
      _item(resized.layout, PersonalProfileModuleIds.favoriteShips).size,
      PersonalProfileModuleSize.two,
    );
    expect(
      _item(fixedRoles.layout, PersonalProfileModuleIds.skilledRoles).size,
      PersonalProfileModuleSize.two,
    );
  });

  test('removed modules can be inserted into a selected empty cell', () {
    final hidden = PersonalProfileLayout.hide(
      _defaultLayout(),
      PersonalProfileModuleIds.hangarSummary,
    );
    final restored = PersonalProfileLayout.show(
      hidden.layout,
      PersonalProfileModuleIds.hangarSummary,
      requestedPosition: 3,
    );

    expect(
      _item(hidden.layout, PersonalProfileModuleIds.hangarSummary).isVisible,
      isFalse,
    );
    final hangar = _item(
      restored.layout,
      PersonalProfileModuleIds.hangarSummary,
    );
    expect(hangar.isVisible, isTrue);
    expect(hangar.position, 3);
  });
}

List<PersonalProfileModuleLayoutItem> _defaultLayout() => const [
  PersonalProfileModuleLayoutItem(
    moduleId: PersonalProfileModuleIds.favoriteShips,
    size: PersonalProfileModuleSize.three,
    isVisible: true,
    position: 0,
  ),
  PersonalProfileModuleLayoutItem(
    moduleId: PersonalProfileModuleIds.hangarSummary,
    size: PersonalProfileModuleSize.three,
    isVisible: true,
    position: 3,
  ),
  PersonalProfileModuleLayoutItem(
    moduleId: PersonalProfileModuleIds.skilledRoles,
    size: PersonalProfileModuleSize.two,
    isVisible: true,
    position: 6,
  ),
];

PersonalProfileModuleLayoutItem _item(
  List<PersonalProfileModuleLayoutItem> layout,
  String moduleId,
) => layout.singleWhere((item) => item.moduleId == moduleId);
