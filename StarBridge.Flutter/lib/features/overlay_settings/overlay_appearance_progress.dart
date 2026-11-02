import 'dart:convert';

import 'overlay_appearance_configuration.dart';

/// Account-confirmed collection only. No placement, account identity,
/// commands, local clock, or appearance-use grant crosses this interface.
abstract interface class OverlayAppearanceProgressPort {
  bool get supportsAppearanceProgress;
  Stream<void> get appearanceOwnerChanges;
  Future<OverlayAppearanceProgress> readAppearanceProgress(String appearanceId);
}

final class OverlayAppearanceProgress {
  OverlayAppearanceProgress._(
    this.appearanceId,
    this.state,
    this.confirmedUsageMs,
    this.items,
  );
  final String appearanceId, state;
  final int? confirmedUsageMs;
  final List<AppearanceCollectionItem> items;
  factory OverlayAppearanceProgress.fromMap(
    Map<String, Object?> value, {
    required String appearanceId,
  }) {
    if (utf8.encode(jsonEncode(value)).length > 12 * 1024) {
      throw const FormatException('Appearance collection too large.');
    }
    _exact(value, {
      'schemaVersion',
      'appearanceId',
      'state',
      'confirmedUsageMs',
      'items',
    });
    const states = {
      'ready',
      'signedOut',
      'accountSyncPending',
      'waitingAcknowledgement',
      'anotherSession',
      'unavailable',
      'authenticationRequired',
      'resyncRequired',
    };
    if (value['schemaVersion'] is! int ||
        value['schemaVersion'] != 1 ||
        value['appearanceId'] != appearanceId ||
        !states.contains(value['state'])) {
      throw const FormatException('Invalid appearance collection.');
    }
    final total = value['confirmedUsageMs'] == null
        ? null
        : _number(value['confirmedUsageMs']);
    if ((value['state'] == 'signedOut' ||
            value['state'] == 'authenticationRequired') &&
        total != null) {
      throw const FormatException('Signed-out collection retained progress.');
    }
    final input = value['items'];
    if (input is! List || input.isEmpty || input.length > 16) {
      throw const FormatException('Invalid collection items.');
    }
    final ids = <String>{};
    final items = <AppearanceCollectionItem>[];
    for (final row in input) {
      final item = _map(row);
      _exact(item, {'id', 'label', 'requiredUsageMs', 'remainingMs', 'owned'});
      final id = item['id'];
      if (id is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id) ||
          !ids.add(id)) {
        throw const FormatException('Invalid collection item identity.');
      }
      final label = AppearanceText.from(item['label']);
      if ([label.zhCN, label.zhTW, label.en].any((text) => text.length > 128)) {
        throw const FormatException('Collection label too long.');
      }
      final required = _number(item['requiredUsageMs']);
      final remaining = required == 0
          ? 0
          : total == null
          ? null
          : (required - total).clamp(0, required);
      final owned = required == 0 || total != null && total >= required;
      if (item['owned'] is! bool ||
          item['owned'] != owned ||
          item['remainingMs'] != remaining ||
          item['remainingMs'] != null && item['remainingMs'] is! int) {
        throw const FormatException('Inconsistent collection receipt.');
      }
      items.add(
        AppearanceCollectionItem._(id, label, required, remaining, owned),
      );
    }
    return OverlayAppearanceProgress._(
      appearanceId,
      value['state'] as String,
      total,
      List.unmodifiable(items),
    );
  }
}

final class AppearanceCollectionItem {
  const AppearanceCollectionItem._(
    this.id,
    this.label,
    this.requiredUsageMs,
    this.remainingMs,
    this.owned,
  );
  final String id;
  final AppearanceText label;
  final int requiredUsageMs;
  final int? remainingMs;
  final bool owned;
}

int _number(Object? value) {
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('Invalid collection time.');
  }
  return value;
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected collection object.');
  }
  return Map<String, Object?>.from(value);
}

void _exact(Map<String, Object?> value, Set<String> keys) {
  if (value.length != keys.length ||
      value.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Invalid collection fields.');
  }
}
