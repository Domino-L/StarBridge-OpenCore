import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/guide/guide_copy.dart';
import 'package:starbridge_flutter/shared/guide/guide_page_tip.dart';
import 'package:starbridge_flutter/shared/guide/guide_state.dart';
import 'package:starbridge_flutter/shared/guide/guide_tours.dart';

final _han = RegExp(r'[㐀-鿿豈-﫿　-〿＀-￯]');

Map<String, Object?> _ready({
  List<Object?> seen = const [],
  List<Object?> done = const [],
}) => {
  'schemaVersion': 1,
  'state': 'ready',
  'eligible': true,
  'seen': seen,
  'checklist': {
    'collapsed': false,
    'dismissed': false,
    'celebrated': false,
    'done': done,
  },
};

void main() {
  group('Host projection', () {
    test('ready and unavailable decode', () {
      final state = parseGuideState(
        _ready(seen: ['tip.fleet'], done: ['hangar']),
      );
      expect(state.available, isTrue);
      expect(state.eligible, isTrue);
      expect(state.seen, {'tip.fleet'});
      expect(state.done, {'hangar'});
      expect(
        parseGuideState({'schemaVersion': 1, 'state': 'unavailable'}),
        GuideState.unavailable,
      );
    });

    test('fails closed on malformed input', () {
      for (final bad in <Map<String, Object?>>[
        {'schemaVersion': 2, 'state': 'ready'},
        {'schemaVersion': 1, 'state': 'other'},
        {..._ready(), 'eligible': 'yes'},
        _ready(seen: ['UPPER']),
        _ready(seen: [1]),
        _ready(seen: List.filled(65, 'tip.fleet')),
        {
          ..._ready(),
          'checklist': {'collapsed': false},
        },
      ]) {
        expect(
          () => parseGuideState(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('ops apply locally like Host and serialize exactly', () {
      var state = const GuideState(available: true);
      for (final op in [
        GuideOp.markSeen('tip.fleet'),
        GuideOp.markSeen('tip.fleet'),
        const GuideOp.markEligible(),
        GuideOp.markDone('hangar'),
        const GuideOp.setChecklist(collapsed: true, dismissed: true),
      ]) {
        state = state.apply(op);
      }
      expect(state.seen, {'tip.fleet'});
      expect(state.eligible && state.collapsed && state.dismissed, isTrue);
      state = state
          .apply(const GuideOp.resetChecklist())
          .apply(const GuideOp.resetSeen());
      expect(state.seen, isEmpty);
      expect(state.dismissed || state.collapsed, isFalse);
      expect(state.done, {'hangar'}, reason: 'reset keeps progress');
      expect(state.eligible, isTrue, reason: 'eligibility is permanent');
      expect(const GuideOp.setChecklist(collapsed: true).toWire(), {
        'op': 'setChecklist',
        'collapsed': true,
      });
      expect(GuideOp.markDone('friend').toWire(), {
        'op': 'markDone',
        'id': 'friend',
      });
    });
  });

  group('copy', () {
    test('every entry has three non-empty items and Chinese-free English', () {
      for (final table in GuideCopy.tables) {
        for (final MapEntry(:key, :value) in table.entries) {
          expect(
            value.$1.trim().isNotEmpty &&
                value.$2.trim().isNotEmpty &&
                value.$3.trim().isNotEmpty,
            isTrue,
            reason: key,
          );
          expect(_han.hasMatch(value.$3), isFalse, reason: key);
        }
      }
    });

    test('every tour step and tip has its copy', () {
      const copy = GuideCopy(Locale('zh', 'CN'));
      for (final spec in guideTours.values) {
        expect(copy.maybe('tour.${spec.id}.name'), isNotNull, reason: spec.id);
        for (var i = 1; i <= spec.steps.length; i++) {
          expect(copy.maybe('tour.${spec.id}.$i.title'), isNotNull);
          expect(copy.maybe('tour.${spec.id}.$i.body'), isNotNull);
        }
        expect(
          copy.maybe('tour.${spec.id}.${spec.steps.length + 1}.title'),
          isNull,
          reason: '${spec.id} has no orphan step copy',
        );
      }
      for (final tip in guideTipRoutes.values) {
        expect(copy.maybe('tip.$tip.title'), isNotNull, reason: tip);
      }
      for (final id in [
        'hangar', 'fleet', 'rooms', 'trades', 'communities', 'friends', //
        'messages', 'notifications', 'online',
      ]) {
        expect(copy.maybe('empty.$id.title'), isNotNull, reason: id);
        expect(copy.maybe('empty.$id.body'), isNotNull, reason: id);
      }
    });

    test('the market tip keeps the user-approved SCM terms wording', () {
      expect(
        const GuideCopy(Locale('zh', 'CN')).text('tip.market.title'),
        '买卖游戏物品，进行交易默认你已经了解并同意SCM网站上的交易条款',
      );
    });
  });
}
