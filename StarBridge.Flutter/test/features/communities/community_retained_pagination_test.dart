import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'community_retained_renewal_test.dart' show RetainedRenewalHost;

class PagedRetainedHost extends RetainedRenewalHost {
  PagedRetainedHost() {
    answerDirectory = page;
  }
  String version = 'a' * 32, prefix = 'Old';
  int count = 61;
  int? pauseOffset;
  final pageStarted = Completer<void>(), releasePage = Completer<void>();
  final Map<String, dynamic>? nativePages = _nativePages();
  static Map<String, dynamic>? _nativePages() {
    const path = String.fromEnvironment('STARBRIDGE_RETAINED_PAGINATION_WIRE');
    return path.isEmpty
        ? null
        : jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  }

  Future<void> page(BridgeEnvelope request) async {
    final offset = request.payload['offset']! as int;
    if (roots > 1 && offset == pauseOffset && !pageStarted.isCompleted) {
      pageStarted.complete();
      await releasePage.future;
    }
    final expected = request.payload['directoryVersion'];
    final code = expected != null && expected != version
        ? (nativePages?['directoryChanged'] as String? ??
              'offlineAccount.directory_changed')
        : offset > count || offset > 0 && expected == null
        ? (nativePages?['missingPage'] as String? ??
              'offlineAccount.invalid_request')
        : null;
    if (code != null) {
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'error',
          payload: const {},
          error: BridgeErrorBody(
            code: code,
            message: 'Snapshot cursor is not current.',
            retryable: false,
          ),
        ),
      );
      return;
    }
    final end = (offset + 20).clamp(0, count);
    if (nativePages != null) {
      final label = '${prefix == 'Old' ? 'old' : 'new'}$count';
      final rows = (nativePages!['snapshots'] as Map)[label] as List;
      await respond(
        request,
        (rows[offset ~/ 20] as Map).cast<String, Object?>(),
      );
      return;
    }
    await respond(request, {
      'schemaVersion': 1,
      'source': 'cached',
      'cachedAtUtc': stamp,
      'complete': !(prefix == 'New' && count == 256),
      'directoryVersion': version,
      'items': [
        for (var i = offset; i < end; i++)
          {
            'id': (i + 1).toRadixString(16).padLeft(64, '0'),
            'name': '$prefix $i',
            'logoAvailable': false,
          },
      ],
      if (end < count) 'nextOffset': end,
    });
  }

  @override
  Future<void> close() async {
    if (!releasePage.isCompleted) releasePage.complete();
    await super.close();
  }
}

void main() {
  test(
    'cached preparation publishes busy before notifying paging listeners',
    () async {
      final h = PagedRetainedHost();
      await h.initialize();
      try {
        await h.model.refresh(newView: 'mine');
        await h.model.next();
        var tried = false;
        h.model.addListener(() {
          if (h.roots == 2 && h.model.joinedBusy && !tried) {
            tried = true;
            unawaited(h.model.next());
          }
        });
        h.holdReplacement = true;
        h.version = 'c' * 32;
        h.prefix = 'New';
        await h.account.refresh();
        await h.replacementStarted.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(Duration.zero);
        expect(tried, isTrue);
        expect(h.model.busy, isTrue);
        expect(
          h.seen.where(
            (r) =>
                r.payload['readId'] == h.current &&
                r.payload['directoryVersion'] == 'a' * 32,
          ),
          isEmpty,
        );
      } finally {
        await h.close();
      }
    },
  );
  for (final withdrawn in [true, false]) {
    test(
      'new cached page rejects late continuation withdrawn=$withdrawn',
      () async {
        final h = PagedRetainedHost()..pauseOffset = 20;
        await h.initialize();
        try {
          await h.model.refresh(newView: 'mine');
          await h.model.next();
          h.version = 'c' * 32;
          h.prefix = 'New';
          await h.account.refresh();
          await h.pageStarted.future.timeout(const Duration(seconds: 2));
          if (withdrawn) {
            h.nextState = 'signedOut';
            await h.account.refresh();
          } else {
            h.version = 'd' * 32;
          }
          final completed = Completer<void>();
          void settled() {
          if (!h.model.busy && !h.model.joinedBusy && !completed.isCompleted) {
              completed.complete();
          }
          }

          h.model.addListener(settled);
          h.releasePage.complete();
          settled();
          await completed.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(Duration.zero);
          expect(h.model.directory, isNull);
          expect(h.model.canPrevious, isFalse);
          expect(h.model.joined, isEmpty);
          expect(h.roots, withdrawn ? 3 : 2);
          if (!withdrawn) expect(h.model.error, 'offlineCacheUnavailable');
        } finally {
          await h.close();
        }
      },
    );
  }
  test(
    'cached directory receives logo bytes completed after its names',
    () async {
      final h = RetainedRenewalHost();
      await h.initialize();
      final completed = Completer<void>();
      h.model.addListener(() {
        if (!completed.isCompleted &&
            h.model.joined.firstOrNull?.logo == h.image) {
          completed.complete();
        }
      });
      try {
        await h.model.refresh(newView: 'mine');
        await h.oldStarted.future.timeout(const Duration(seconds: 2));
        expect(h.model.directory!.items.single.logo, isNull);
        h.releaseOld.complete();
        await completed.future.timeout(const Duration(seconds: 2));
        expect(h.model.directory!.items.single.logo == h.image, isTrue);
        expect(h.model.directory!.items.single.displayOnly, isTrue);
      } finally {
        await h.close();
      }
    },
  );
  for (final scenario in [
    (page: 1, changed: false, remaining: 61, expected: 20),
    (page: 1, changed: true, remaining: 61, expected: 20),
    (page: 1, changed: true, remaining: 5, expected: 0),
    (page: 2, changed: true, remaining: 25, expected: 20),
    (page: 1, changed: true, remaining: 0, expected: 0),
    (page: 12, changed: true, remaining: 256, expected: 240),
  ]) {
    test('retained page survives root renewal $scenario', () async {
      final h = PagedRetainedHost();
      if (scenario.page == 12) h.count = 256;
      await h.initialize();
      try {
        await h.model.refresh(newView: 'mine');
        for (var i = 0; i < scenario.page; i++) {
          await h.model.next();
        }
        expect(
          h.model.directory!.items.first.name,
          'Old ${scenario.page * 20}',
        );
        expect(h.model.canPrevious, isTrue);
        h.holdReplacement = true;
        if (scenario.changed) {
          h.version = 'c' * 32;
          h.prefix = 'New';
        }
        h.count = scenario.remaining;
        final completed = Completer<void>();
        h.model.addListener(() {
          if (h.roots > 1 &&
              !h.model.busy &&
              !h.model.joinedBusy &&
              !completed.isCompleted) {
            completed.complete();
          }
        });
        await h.account.refresh();
        await h.replacementStarted.future.timeout(const Duration(seconds: 2));
        expect(
          h.model.directory!.items.first.name,
          'Old ${scenario.page * 20}',
        );
        h.releaseReplacement.complete();
        await completed.future.timeout(const Duration(seconds: 2));
        expect(h.model.error, isNull);
        if (scenario.remaining == 0) {
          expect(h.model.directory?.items, isEmpty);
        } else {
          expect(
            h.model.directory?.items.first.name,
            '${h.prefix} ${scenario.expected}',
          );
        }
        expect(h.model.directory?.displayVersion, h.version);
        expect(
          h.model.directory?.cacheComplete,
          !(scenario.changed && scenario.remaining == 256),
        );
        expect(h.model.canPrevious, scenario.expected > 0);
        expect(
          h.model.directory!.items.every(
            (row) => row.displayOnly && row.actions.isEmpty,
          ),
          isTrue,
        );
        if (scenario.expected > 0) {
          await h.model.previous();
          expect(
            h.model.directory?.items.first.name,
            '${h.prefix} ${scenario.expected - 20}',
          );
          expect(h.model.error, isNull);
        }
        expect(h.roots, 2);
        expect(h.seen.every((r) => r.accountContext == null), isTrue);
        expect(h.seen.any((r) => r.name == 'communities.read'), isFalse);
      } finally {
        await h.close();
      }
    });
  }
}
