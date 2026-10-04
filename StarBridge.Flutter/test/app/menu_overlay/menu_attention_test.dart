import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_attention.dart';
import 'package:starbridge_flutter/platform/window/menu_toolbar_preferences.dart';

class _Counter<T> extends ValueNotifier<T> {
  _Counter(super.value);
  bool get observed => hasListeners;
}

void main() {
  test('count-only envelope rejects malformed or unbounded data', () {
    const value = MenuAttention(
      friends: 1,
      comms: 102,
      rooms: 3,
      organizations: 4,
    );
    expect(
      MenuAttention.parse(jsonEncode(value.toMap()))!.toMap(),
      value.toMap(),
    );
    for (final raw in [
      null,
      {},
      [],
      'invalid',
      'x' * 257,
      jsonEncode({...value.toMap(), 'account': 'forbidden'}),
      jsonEncode({...value.toMap()}..remove('friends')),
      for (final bad in [-1, 1.5, null, true, '1', 1000000001])
        jsonEncode({...value.toMap(), 'friends': bad}),
    ]) {
      expect(MenuAttention.parse(raw), isNull, reason: '$raw');
    }
    expect(
      const MenuAttention(friends: -1, comms: 1000000001).toMap(),
      const MenuAttention(comms: MenuAttention.maximum).toMap(),
    );
  });

  test(
    'existing counters update immediately, unchanged values are deduplicated',
    () {
      final counter = _Counter<int>(3), account = _Counter<bool>(true);
      final source = MenuAttentionSource(
        changes: [counter, account],
        isCurrent: () => account.value,
        read: () => MenuAttention(comms: counter.value),
      );
      var events = 0;
      source.addListener(() => events++);
      expect(source.value.comms, 3);
      counter.value = 4;
      expect(source.value.comms, 4);
      expect(events, 1);
      counter.value = 4;
      expect(events, 1);
      account.value = false;
      expect(source.value.comms, 0);
      counter.value = 9;
      expect(source.value.comms, 0);
      source.dispose();
      expect(counter.observed, false);
      expect(account.observed, false);
      counter.value = 10; // Original owner remains usable.
      expect(events, 2);
      counter.dispose();
      account.dispose();
    },
  );

  test('invalidation clears and latches old session; new opening gets fresh source', () async {
    final counter = _Counter<int>(8);
    final invalidations = StreamController<void>.broadcast(sync: true);
    MenuAttentionSource create() => MenuAttentionSource(
      changes: [counter],
      isCurrent: () => true,
      read: () => MenuAttention(rooms: counter.value),
      invalidations: invalidations.stream,
    );
    final old = create();
    invalidations.add(null);
    expect(old.value.rooms, 0);
    counter.value = 12;
    expect(old.value.rooms, 0);
    old.dispose();
    final next = create();
    expect(next.value.rooms, 12);
    next.dispose();
    expect(counter.observed, false);
    counter.dispose();
    await invalidations.close();
  });

  test(
    'old four-field toolbar defaults to badges, new flag is strictly boolean',
    () {
      final old = const MenuToolbarPreferences().toMap()
        ..remove('showUnreadBadges');
      expect(MenuToolbarPreferences.parse(old)!.showUnreadBadges, true);
      expect(
        MenuToolbarPreferences.parse({...old, 'showUnreadBadges': false})!
            .showUnreadBadges,
        false,
      );
      for (final bad in [null, 0, 'false', []]) {
        expect(
          MenuToolbarPreferences.parse({...old, 'showUnreadBadges': bad}),
          isNull,
        );
      }
      expect(
        const MenuToolbarPreferences(showUnreadBadges: false)
            .copyWith(density: 'compact')
            .showUnreadBadges,
        false,
      );
    },
  );
}
