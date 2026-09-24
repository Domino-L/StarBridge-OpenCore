import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';

void main() {
  test(
    'edits coalesce; successful groups are not resubmitted after failure',
    () async {
      final drafts = PrivacyPageDrafts();
      var calls = 0;
      Future<bool> commit(int n) async {
        calls++;
        return true;
      }

      drafts.edit('one', 0, 1, commit);
      drafts.edit('one', 0, 2, commit);
      drafts.edit('two', false, true, (_) async => false);
      expect(calls, 0);
      expect(await drafts.save(), isFalse);
      expect(calls, 1);
      expect(drafts.dirty, isTrue);
      await drafts.save();
      expect(calls, 1);
      drafts.discard();
      expect(drafts.dirty, isFalse);
    },
  );
  test('account invalidation stops remaining queued writes', () async {
    final drafts = PrivacyPageDrafts();
    final pending = Completer<bool>();
    var secondCalls = 0;
    drafts.edit('one', false, true, (_) => pending.future);
    drafts.edit('two', false, true, (_) async {
      secondCalls++;
      return true;
    });
    final save = drafts.save();
    drafts.discard();
    pending.complete(true);
    expect(await save, isFalse);
    expect(secondCalls, 0);
    expect(drafts.dirty, isFalse);
  });
  test('returning to saved value removes the write', () {
    final drafts = PrivacyPageDrafts();
    drafts.edit('one', 0, 1, (_) async => true);
    drafts.edit('one', 0, 0, (_) async => true);
    expect(drafts.dirty, isFalse);
  });
}
