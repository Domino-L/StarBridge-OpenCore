import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'direct_messages_test.dart' as fixture;
import '../friends/social_layout_test.dart' show loadFonts;

const previewOutput = String.fromEnvironment(
  'STARBRIDGE_HISTORY_FEEDBACK_OUTPUT',
);
const traditionalPreviewFont = String.fromEnvironment(
  'STARBRIDGE_HISTORY_TRADITIONAL_FONT',
);

class HistoryPort implements DirectMessagesPort, DirectMessageSender {
  HistoryPort({this.empty = false, this.paginate = false});
  final bool empty;
  final bool paginate;
  final events = StreamController<void>.broadcast(sync: true);
  final reads = <(String, int, int)>[];
  int sends = 0;
  Object? failure;
  Completer<DirectPage>? pending;
  Conversation get peer => Conversation(
    'peer',
    'Peer',
    '',
    DateTime.utc(2026),
    2,
    'friend',
    conversationKey: 'synthetic-history',
  );
  Conversation get other => Conversation(
    'other',
    'Other',
    '',
    DateTime.utc(2026),
    0,
    'friend',
    conversationKey: 'synthetic-other',
  );
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() async => [peer, other];
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    reads.add((ref, before, after));
    if (pending != null) return pending!.future;
    if (failure != null) throw failure!;
    final messages = [
      if (!empty)
        for (var n = 1; n <= 40; n++)
          if ((before == 0 || n < before) &&
              n > after &&
              (!paginate || before > 0 || n >= 21))
            DirectMessage(
              n,
              '$ref-$n',
              true,
              'Synthetic retained body $n',
              DateTime.utc(2026),
              null,
            ),
    ];
    return DirectPage(
      ref,
      messages,
      messages.isEmpty ? 0 : messages.first.sequence,
      messages.isEmpty ? 0 : messages.last.sequence,
      paginate && before == 0 && after == 0,
      'friend',
      canSend: true,
    );
  }

  @override
  bool get supportsSending => true;
  @override
  Future<DirectSendResult> send(String ref, String text, String id) async {
    sends++;
    return const DirectSendResult('unknown');
  }

  @override
  void cancel() {}
  @override
  Future<void> close() => events.close();
}

Future<DirectMessagesModule> ready(HistoryPort port) async {
  final module = DirectMessagesModule(port);
  await module.refresh();
  await module.open(module.rows.first);
  module.editDraft('Synthetic unsaved draft');
  return module;
}

Future<void> mount(
  WidgetTester t,
  DirectMessagesModule module,
  HistoryPort port, {
  Locale locale = const Locale('en', 'US'),
  LoadingMetrics? metrics,
}) async {
  final base = fixture.app(locale, () => port) as MaterialApp;
  await runZoned(
    () => t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('history-feedback-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          theme: base.theme,
          home: Scaffold(
            body: DirectMessagesPage(
              createPort: () => port,
              sharedModule: module,
              onBack: () {},
            ),
          ),
        ),
      ),
    ),
    zoneValues: {loadingMetricsZoneKey: ?metrics},
  );
  await pump(t, metrics);
}

Future<void> pump(WidgetTester t, [LoadingMetrics? metrics]) =>
    runZoned(() async {
      await t.pumpAndSettle();
    }, zoneValues: {loadingMetricsZoneKey: ?metrics});

Future<void> capture(WidgetTester t, Locale locale, bool empty) async {
  if (previewOutput.isEmpty) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('history-feedback-preview')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '$previewOutput/${locale.toLanguageTag()}-${empty ? 'empty' : 'history'}.png',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    if (previewOutput.isNotEmpty) {
      await loadFonts();
      // The headless engine does not discover Windows system fonts. Load the
      // product's configured traditional fallback only for local preview QA;
      // never bundle, copy or substitute it into the product assets.
      if (traditionalPreviewFont.isEmpty) {
        throw StateError(
          'Traditional preview requires the configured system font',
        );
      }
      await (FontLoader('Microsoft JhengHei UI')..addFont(
            File(traditionalPreviewFont)
                .readAsBytes()
                .then(ByteData.sublistView),
          ))
          .load();
    }
  });
  test(
    'loading older messages does not clear a failed latest-message sync',
    () async {
      final port = HistoryPort(paginate: true);
      final model = await ready(port);
      addTearDown(model.dispose);
      expect(model.hasOlder, true);
      port.failure = const DirectReadFailure('unavailable');
      await model.load(newer: true, quiet: true);
      expect(model.historySyncError, 'unavailable');
      port.failure = null;
      await model.load(older: true);
      expect(model.messages.length, 40);
      expect(
        model.historySyncError,
        'unavailable',
        reason:
            'An older-page read cannot prove the latest cursor is synchronized',
      );
      await model.load(newer: true, quiet: true);
      expect(model.historySyncError, isNull);
    },
  );
  for (final failure in [
    const DirectReadFailure('unavailable'),
    TimeoutException('Synthetic timeout'),
    const DirectReadFailure('data_invalid'),
    const DirectReadFailure('limit'),
  ]) {
    test(
      'quiet history failure publishes feedback without revoking a confirmed view: ${failure.runtimeType} ${failure is DirectReadFailure ? failure.code : 'timeout'}',
      () async {
        final port = HistoryPort();
        final module = await ready(port);
        addTearDown(module.dispose);
        final messages = module.messages, revision = module.draftRevision;
        var notices = 0;
        module.addListener(() => notices++);
        port.failure = failure;
        await module.load(newer: true, quiet: true);
        expect(notices, greaterThan(0));
        expect(
          module.historySyncError,
          failure is DirectReadFailure ? failure.code : 'unavailable',
        );
        expect(module.messages, same(messages));
        expect(module.draftRevision, revision);
        expect(module.draft, 'Synthetic unsaved draft');
        expect(module.canSend, true);
        expect(module.error, isNull);
        port.failure = null;
        await module.refresh();
        expect(
          module.historySyncError,
          isNotNull,
          reason: 'Directory success cannot vouch for history freshness',
        );
        await module.load(newer: true, quiet: true);
        expect(module.historySyncError, isNull);
      },
    );
  }

  test(
    'history failures keep an uncertain send visible and never post it twice',
    () async {
      final port = HistoryPort();
      final module = await ready(port);
      addTearDown(module.dispose);
      await module.send();
      await pumpEventQueue();
      expect(module.outgoing.single.text, 'Synthetic unsaved draft');
      expect(module.draft, isEmpty);
      expect(port.sends, 1);
      port.failure = const DirectReadFailure('unavailable');
      await module.receive();
      expect(module.historySyncError, 'unavailable');
      expect(module.outgoing.single.text, 'Synthetic unsaved draft');
      port.failure = null;
      await module.load(newer: true);
      expect(module.historySyncError, isNull);
      expect(module.outgoing.single.text, 'Synthetic unsaved draft');
      expect(port.sends, 1, reason: 'reads never post the message again');
    },
  );

  for (final code in ['forbidden', 'identity_unavailable', 'target_changed']) {
    test(
      '$code history denial supersedes recoverable feedback and withdraws inaccessible messages',
      () async {
        final port = HistoryPort();
        final module = await ready(port);
        addTearDown(module.dispose);
        port.failure = const DirectReadFailure('unavailable');
        await module.load(quiet: true, newer: true);
        expect(module.historySyncError, isNotNull);
        port.failure = DirectReadFailure(code);
        await module.load(quiet: true, newer: true);
        expect(module.historySyncError, isNull);
        expect(module.error, code);
        expect(module.messages, isEmpty);
        expect(module.canSend, false);
      },
    );
  }

  test('back, another conversation and account invalidation retire the former history failure', () async {
    final port = HistoryPort();
    final module = await ready(port);
    addTearDown(module.dispose);
    for (final action in ['back', 'open', 'account']) {
      port.failure = const DirectReadFailure('unavailable');
      await module.load(quiet: true, newer: true);
      expect(module.historySyncError, isNotNull);
      port.failure = null;
      if (action == 'back') {
        module.back();
        expect(module.historySyncError, isNull);
        await module.open(module.rows.first);
      } else if (action == 'open') {
        await module.open(module.rows.last);
        expect(module.historySyncError, isNull);
      } else {
        port.events.add(null);
        expect(module.historySyncError, isNull);
        await Future<void>.delayed(Duration.zero);
      }
    }
  });

  test('a late old history failure cannot contaminate the replacement conversation', () async {
    final port = HistoryPort();
    final module = await ready(port);
    addTearDown(module.dispose);
    final held = port.pending = Completer<DirectPage>();
    final receiving = module.receive();
    await Future<void>.delayed(Duration.zero);
    port.pending = null;
    module.back();
    await module.open(module.rows.last);
    held.completeError(const DirectReadFailure('unavailable'));
    await receiving;
    expect(module.selected!.ref, port.other.ref);
    expect(module.historySyncError, isNull);
    expect(module.error, isNull);
  });

  for (final locale in AppStrings.supportedLocales) {
    for (final empty in [false, true]) {
      testWidgets(
        '$locale quiet history failure is visible while preserving '
        '${empty ? 'empty' : 'populated'} history, draft and viewport; refresh recovers',
        (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = const Size(1000, 760);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.view.resetPhysicalSize);
          final port = HistoryPort(empty: empty);
          final model = await ready(port);
          addTearDown(model.dispose);
          await mount(t, model, port, locale: locale);
          try {
            final before = model.messages,
                revision = model.draftRevision,
                selected = model.selected;
            final list = find.byKey(ValueKey(selected!.ref));
            final controller = empty
                ? null
                : t.widget<ListView>(list).controller!;
            if (controller != null) {
              controller.jumpTo(200);
              await t.pump();
            }
            final offset = controller?.offset;
            port.failure = const DirectReadFailure('unavailable');
            expect(await model.receive(), DirectMessageReceiveResult.failed);
            await pump(t);
            expect(model.messages, same(before));
            expect(model.selected?.ref, selected.ref);
            expect(model.draft, 'Synthetic unsaved draft');
            expect(model.draftRevision, revision);
            expect(model.canSend, true);
            expect(model.busy, false);
            expect(controller?.offset, offset);
            expect(
              find.byKey(const ValueKey('chat-history-sync-failed')),
              findsOneWidget,
            );
            expect(
              find.textContaining('direct.historySyncFailed'),
              findsNothing,
            );
            if (empty) {
              expect(
                find.text(
                  AppStrings.resolve(locale).text('direct.emptyHistory'),
                ),
                findsNothing,
              );
            }
            await capture(t, locale, empty);
            port.failure = null;
            await t.tap(find.byKey(const ValueKey('chat-refresh-history')));
            await pump(t);
            expect(
              find.byKey(const ValueKey('chat-history-sync-failed')),
              findsNothing,
            );
            expect(model.draft, 'Synthetic unsaved draft');
            expect(model.draftRevision, revision);
            expect(controller?.offset, offset);
            expect(port.sends, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }

  for (final empty in [false, true]) {
    testWidgets('quiet history failure records ${empty ? 'failed' : 'partial'} '
        'rather than healthy ${empty ? 'empty' : 'data'} content', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1000, 760);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final port = HistoryPort(empty: empty);
      final module = await ready(port);
      addTearDown(module.dispose);
      final metrics = LoadingMetrics(nowUs: () => 10, write: (_) {});
      await mount(t, module, port, metrics: metrics);
      try {
        expect(find.byType(LoadingContentProbe), findsOneWidget);
        port.failure = const DirectReadFailure('unavailable');
        await module.receive();
        await pump(t, metrics);
        final probe = t.widget<LoadingContentProbe>(
          find.byType(LoadingContentProbe),
        );
        expect(
          probe.status,
          empty ? LoadingContentStatus.failed : LoadingContentStatus.partial,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets(
    'an old conversation timestamp fits the English compact directory at 800 pixels',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(800, 760);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final port = HistoryPort();
      final model = await ready(port);
      addTearDown(model.dispose);
      try {
        await mount(t, model, port);
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
      }
    },
  );
}
