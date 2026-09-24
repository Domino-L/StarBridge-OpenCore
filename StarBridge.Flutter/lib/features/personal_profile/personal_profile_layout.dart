import 'personal_profile_models.dart';

enum PersonalProfileLayoutFailure {
  none,
  moduleNotFound,
  noSpace,
  selectionExceedsSize,
}

final class PersonalProfileLayoutMutation {
  const PersonalProfileLayoutMutation({
    required this.layout,
    this.failure = PersonalProfileLayoutFailure.none,
  });

  final List<PersonalProfileModuleLayoutItem> layout;
  final PersonalProfileLayoutFailure failure;
}

abstract final class PersonalProfileLayout {
  static const columnCount = 3;
  static const rowCount = 3;
  static const cellCount = columnCount * rowCount;
  static const maxModules = 64;
  static const maximumCells = maxModules * columnCount;

  static const displayModuleIds = <String>[
    PersonalProfileModuleIds.favoriteShips,
    PersonalProfileModuleIds.hangarSummary,
    PersonalProfileModuleIds.skilledRoles,
  ];

  static List<PersonalProfileModuleSize> allowedSizes(String moduleId) {
    if (moduleId == PersonalProfileModuleIds.skilledRoles) {
      return const [PersonalProfileModuleSize.two];
    }
    return PersonalProfileModuleSize.values;
  }

  static List<PersonalProfileModuleLayoutItem> normalize(
    Iterable<PersonalProfileModuleLayoutItem> source,
  ) {
    final canonical = <String, PersonalProfileModuleLayoutItem>{};
    for (final item in source) {
      final moduleId = _canonicalModuleId(item.moduleId);
      if (moduleId == null || canonical.containsKey(moduleId)) {
        continue;
      }
      canonical[moduleId] = PersonalProfileModuleLayoutItem(
        moduleId: moduleId,
        favoriteShipIds: item.favoriteShipIds,
        size: _normalizeSize(moduleId, item.size),
        isVisible: item.isVisible,
        position: item.isVisible ? item.position : -1,
      );
    }

    for (final moduleId in displayModuleIds) {
      canonical.putIfAbsent(
        moduleId,
        () => PersonalProfileModuleLayoutItem(
          moduleId: moduleId,
          size: _defaultSize(moduleId),
          isVisible: false,
          position: -1,
        ),
      );
    }

    final occupied = List<bool>.filled(maximumCells, false);
    final normalized = <PersonalProfileModuleLayoutItem>[];
    for (final moduleId in canonical.keys) {
      final item = canonical[moduleId]!;
      if (!item.isVisible) {
        normalized.add(item.copyWith(position: -1));
        continue;
      }
      final span = item.size.span;
      final position = _canPlace(occupied, item.position, span)
          ? item.position
          : _firstPosition(occupied, span);
      if (position < 0) {
        normalized.add(item.copyWith(isVisible: false, position: -1));
        continue;
      }
      _mark(occupied, position, span, true);
      normalized.add(item.copyWith(position: position));
    }
    // Empty rows are not user content. Collapse them while retaining column
    // choices and relative order so removed modules do not leave a tall void.
    final rows =
        normalized
            .where((e) => e.isVisible)
            .map((e) => e.position ~/ columnCount)
            .toSet()
            .toList()
          ..sort();
    return _sort([
      for (final item in normalized)
        item.isVisible
            ? item.copyWith(
                position:
                    rows.indexOf(item.position ~/ columnCount) * columnCount +
                    item.position % columnCount,
              )
            : item,
    ]);
  }

  static PersonalProfileLayoutMutation move(
    Iterable<PersonalProfileModuleLayoutItem> source,
    String moduleId,
    int requestedPosition,
  ) {
    final modules = normalize(source);
    final moving = modules.cast<PersonalProfileModuleLayoutItem?>().firstWhere(
      (item) => item?.moduleId == moduleId && item!.isVisible,
      orElse: () => null,
    );
    if (moving == null) {
      return PersonalProfileLayoutMutation(
        layout: modules,
        failure: PersonalProfileLayoutFailure.moduleNotFound,
      );
    }

    final target = _normalizePosition(requestedPosition, moving.size.span);
    if (target == moving.position) {
      return PersonalProfileLayoutMutation(layout: modules);
    }

    final occupied = List<bool>.filled(maximumCells, false);
    _mark(occupied, target, moving.size.span, true);
    final positions = <String, int>{moving.moduleId: target};
    final remaining =
        modules
            .where((item) => item.isVisible && item.moduleId != moving.moduleId)
            .toList()
          ..sort((first, second) {
            final firstOverlaps = _overlaps(
              first.position,
              first.size.span,
              target,
              moving.size.span,
            );
            final secondOverlaps = _overlaps(
              second.position,
              second.size.span,
              target,
              moving.size.span,
            );
            if (firstOverlaps != secondOverlaps) {
              return firstOverlaps ? -1 : 1;
            }
            return modules.indexOf(first).compareTo(modules.indexOf(second));
          });

    if (!_placeRemaining(
      remaining,
      0,
      moving.position,
      target,
      moving.size.span,
      occupied,
      positions,
    )) {
      return PersonalProfileLayoutMutation(
        layout: modules,
        failure: PersonalProfileLayoutFailure.noSpace,
      );
    }

    return PersonalProfileLayoutMutation(
      layout: _sort([
        for (final item in modules)
          item.isVisible
              ? item.copyWith(position: positions[item.moduleId])
              : item.copyWith(position: -1),
      ]),
    );
  }

  static PersonalProfileLayoutMutation resize(
    Iterable<PersonalProfileModuleLayoutItem> source,
    String moduleId,
    PersonalProfileModuleSize requestedSize,
  ) {
    final modules = normalize(source);
    final index = modules.indexWhere(
      (item) => item.moduleId == moduleId && item.isVisible,
    );
    if (index < 0) {
      return PersonalProfileLayoutMutation(
        layout: modules,
        failure: PersonalProfileLayoutFailure.moduleNotFound,
      );
    }

    final nextSize = _normalizeSize(moduleId, requestedSize);
    if ((modules[index].favoriteShipIds?.length ?? 0) > nextSize.span) {
      return PersonalProfileLayoutMutation(
        layout: modules,
        failure: PersonalProfileLayoutFailure.selectionExceedsSize,
      );
    }
    final occupied = occupiedCells(
      modules,
      excludedModuleId: moduleId,
      full: true,
    );
    final current = modules[index];
    final position = _canPlace(occupied, current.position, nextSize.span)
        ? current.position
        : _firstPosition(occupied, nextSize.span);
    if (position < 0) {
      return PersonalProfileLayoutMutation(
        layout: modules,
        failure: PersonalProfileLayoutFailure.noSpace,
      );
    }
    modules[index] = current.copyWith(size: nextSize, position: position);
    return PersonalProfileLayoutMutation(layout: _sort(modules));
  }

  static PersonalProfileLayoutMutation show(
    Iterable<PersonalProfileModuleLayoutItem> source,
    String moduleId, {
    int? requestedPosition,
  }) {
    final modules = normalize(source);
    final index = modules.indexWhere((item) => item.moduleId == moduleId);
    if (index < 0) {
      return PersonalProfileLayoutMutation(
        layout: modules,
        failure: PersonalProfileLayoutFailure.moduleNotFound,
      );
    }
    if (modules[index].isVisible) {
      return PersonalProfileLayoutMutation(layout: modules);
    }

    final occupied = occupiedCells(modules, full: true);
    final sizes = [modules[index].size];
    for (final size in sizes) {
      final requested = requestedPosition == null
          ? -1
          : _normalizePosition(requestedPosition, size.span);
      final position = _canPlace(occupied, requested, size.span)
          ? requested
          : _firstPosition(occupied, size.span);
      if (position < 0) {
        continue;
      }
      modules[index] = modules[index].copyWith(
        size: size,
        isVisible: true,
        position: position,
      );
      return requestedPosition == null
          ? PersonalProfileLayoutMutation(layout: _sort(modules))
          : move(modules, moduleId, requestedPosition);
    }
    return PersonalProfileLayoutMutation(
      layout: modules,
      failure: PersonalProfileLayoutFailure.noSpace,
    );
  }

  static PersonalProfileLayoutMutation hide(
    Iterable<PersonalProfileModuleLayoutItem> source,
    String moduleId,
  ) {
    final modules = normalize(source);
    final index = modules.indexWhere((item) => item.moduleId == moduleId);
    if (index < 0) {
      return PersonalProfileLayoutMutation(
        layout: modules,
        failure: PersonalProfileLayoutFailure.moduleNotFound,
      );
    }
    modules[index] = modules[index].copyWith(isVisible: false, position: -1);
    return PersonalProfileLayoutMutation(layout: _sort(modules));
  }

  static List<bool> occupiedCells(
    Iterable<PersonalProfileModuleLayoutItem> source, {
    String? excludedModuleId,
    bool full = false,
  }) {
    final items = source.toList();
    final extent = items
        .where((e) => e.isVisible)
        .fold<int>(
          cellCount,
          (n, e) => n > e.position + e.size.span ? n : e.position + e.size.span,
        );
    final occupied = List<bool>.filled(
      full ? maximumCells : ((extent + 2) ~/ 3 * 3),
      false,
    );
    for (final item in source) {
      if (!item.isVisible || item.moduleId == excludedModuleId) {
        continue;
      }
      if (_canPlace(occupied, item.position, item.size.span)) {
        _mark(occupied, item.position, item.size.span, true);
      }
    }
    return occupied;
  }

  static bool hasSameLayout(
    Iterable<PersonalProfileModuleLayoutItem> first,
    Iterable<PersonalProfileModuleLayoutItem> second,
  ) {
    final left = normalize(first);
    final right = normalize(second);
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].moduleId != right[index].moduleId ||
          left[index].size != right[index].size ||
          left[index].isVisible != right[index].isVisible ||
          left[index].position != right[index].position ||
          left[index].favoriteShipIds?.join(',') !=
              right[index].favoriteShipIds?.join(',')) {
        return false;
      }
    }
    return true;
  }

  static bool _placeRemaining(
    List<PersonalProfileModuleLayoutItem> modules,
    int index,
    int vacatedPosition,
    int targetPosition,
    int targetSpan,
    List<bool> occupied,
    Map<String, int> positions,
  ) {
    if (index >= modules.length) {
      return true;
    }
    final module = modules[index];
    final displaced = _overlaps(
      module.position,
      module.size.span,
      targetPosition,
      targetSpan,
    );
    final candidates = <int>{
      if (displaced) _normalizePosition(vacatedPosition, module.size.span),
      _normalizePosition(module.position, module.size.span),
      ...List.generate(maximumCells, (position) => position)..sort(
        (first, second) => (first - module.position).abs().compareTo(
          (second - module.position).abs(),
        ),
      ),
    };
    for (final rawPosition in candidates) {
      final position = _normalizePosition(rawPosition, module.size.span);
      if (!_canPlace(occupied, position, module.size.span)) {
        continue;
      }
      _mark(occupied, position, module.size.span, true);
      positions[module.moduleId] = position;
      if (_placeRemaining(
        modules,
        index + 1,
        vacatedPosition,
        targetPosition,
        targetSpan,
        occupied,
        positions,
      )) {
        return true;
      }
      positions.remove(module.moduleId);
      _mark(occupied, position, module.size.span, false);
    }
    return false;
  }

  static PersonalProfileModuleSize _defaultSize(String moduleId) =>
      moduleId == PersonalProfileModuleIds.skilledRoles
      ? PersonalProfileModuleSize.two
      : PersonalProfileModuleSize.three;

  static PersonalProfileModuleSize _normalizeSize(
    String moduleId,
    PersonalProfileModuleSize requested,
  ) {
    final allowed = allowedSizes(moduleId);
    return allowed.contains(requested) ? requested : allowed.first;
  }

  static String? _canonicalModuleId(String moduleId) {
    if (PersonalProfileModuleIds.isFavorite(moduleId)) return moduleId;
    return switch (moduleId) {
      PersonalProfileModuleIds.favoriteShips =>
        PersonalProfileModuleIds.favoriteShips,
      PersonalProfileModuleIds.hangarSummary =>
        PersonalProfileModuleIds.hangarSummary,
      PersonalProfileModuleIds.skilledRoles ||
      PersonalProfileModuleIds.supportCapabilities ||
      PersonalProfileModuleIds.participationInterests =>
        PersonalProfileModuleIds.skilledRoles,
      _ => null,
    };
  }

  static List<PersonalProfileModuleLayoutItem> _sort(
    Iterable<PersonalProfileModuleLayoutItem> source,
  ) {
    final result = source.toList();
    result.sort((first, second) {
      if (first.isVisible != second.isVisible) {
        return first.isVisible ? -1 : 1;
      }
      if (first.isVisible && first.position != second.position) {
        return first.position.compareTo(second.position);
      }
      final typeOrder = displayModuleIds
          .indexOf(PersonalProfileModuleIds.typeOf(first.moduleId))
          .compareTo(
            displayModuleIds.indexOf(
              PersonalProfileModuleIds.typeOf(second.moduleId),
            ),
          );
      if (typeOrder != 0) return typeOrder;
      return first.moduleId.compareTo(second.moduleId);
    });
    return result;
  }

  static int _firstPosition(List<bool> occupied, int span) {
    for (var position = 0; position < occupied.length; position++) {
      if (_canPlace(occupied, position, span)) {
        return position;
      }
    }
    return -1;
  }

  static int _normalizePosition(int position, int span) {
    final safePosition = position.clamp(0, maximumCells - 1);
    final row = safePosition ~/ columnCount;
    final column = (safePosition % columnCount).clamp(0, columnCount - span);
    return row * columnCount + column;
  }

  static bool _overlaps(
    int firstPosition,
    int firstSpan,
    int secondPosition,
    int secondSpan,
  ) {
    if (firstPosition ~/ columnCount != secondPosition ~/ columnCount) {
      return false;
    }
    return firstPosition < secondPosition + secondSpan &&
        secondPosition < firstPosition + firstSpan;
  }

  static bool _canPlace(List<bool> occupied, int position, int span) {
    if (position < 0 ||
        position + span > occupied.length ||
        span < 1 ||
        span > columnCount ||
        position % columnCount + span > columnCount) {
      return false;
    }
    for (var offset = 0; offset < span; offset++) {
      if (occupied[position + offset]) {
        return false;
      }
    }
    return true;
  }

  static void _mark(List<bool> occupied, int position, int span, bool value) {
    for (var offset = 0; offset < span; offset++) {
      occupied[position + offset] = value;
    }
  }
}
