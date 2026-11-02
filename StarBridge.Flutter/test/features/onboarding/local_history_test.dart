import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_local_history_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/local_history_controller.dart';
import 'package:starbridge_flutter/features/onboarding/local_history_port.dart';
import 'package:starbridge_flutter/features/onboarding/local_statistics_controller.dart';
import 'package:starbridge_flutter/features/onboarding/local_statistics_port.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_summary.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';

const _scan = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _preview = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> historyWire(
  String state, {
  String? scanId,
  String? phase,
  int processed = 0,
  int total = 0,
  String? previewId,
  int? seconds,
  int sessions = 0,
  int? importedSeconds,
  String? importedAt,
}) => {
  'schemaVersion': 1,
  'state': state,
  'scanId': scanId,
  'phase': phase,
  'processedFiles': processed,
  'totalFiles': total,
  'readBytes': 0,
  'totalBytes': 0,
  'previewId': previewId,
  'seconds': seconds,
  'sessions': sessions,
  'incompleteSessions': 0,
  'skippedFiles': 0,
  'importedSeconds': importedSeconds,
  'importedAt': importedAt,
};

LocalHistorySnapshot snap(String state, {Map<String, Object?>? raw}) =>
    LocalHistoryWire.parse(raw ?? historyWire(state));

final _scanning = snap(
  'scanning',
  raw: historyWire('scanning', scanId: _scan, phase: 'scanning', total: 2),
);
final _previewed = snap(
  'preview',
  raw: historyWire('preview', previewId: _preview, seconds: 5400, sessions: 2),
);
final _imported = snap(
  'imported',
  raw: historyWire(
    'imported',
    importedSeconds: 5400,
    importedAt: '2026-10-19T12:00:00+00:00',
  ),
);

final class FakeHistoryPort implements LocalHistoryPort {
  final events = StreamController<void>.broadcast(sync: true);
  LocalHistorySnapshot durable = snap('available');
  List<LocalHistorySnapshot> scanSteps = [];
  LocalHistorySnapshot? confirmResult;
  bool failConfirm = false, importOnFailedConfirm = false;
  int starts = 0, confirms = 0, cancels = 0;

  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<LocalHistorySnapshot> read() async => durable;
  @override
  Future<LocalHistorySnapshot> startScan() async {
    starts++;
    return scanSteps.isEmpty ? durable : scanSteps.removeAt(0);
  }

  @override
  Future<LocalHistorySnapshot> readScan(String scanId) async =>
      scanSteps.removeAt(0);
  @override
  Future<LocalHistorySnapshot> cancelScan(String scanId) async {
    cancels++;
    return snap('cancelled');
  }

  bool supportsReset = true;
  LocalResetSnapshot resetPreview = const LocalResetSnapshot(
    'ready',
    resetId: 'cccccccccccccccccccccccccccccccc',
    seconds: 9000,
    historicalSeconds: 5400,
  );
  String resetResult = 'reset';
  int resetPreviews = 0, resetConfirms = 0;
  @override
  bool get resetSupported => supportsReset;
  @override
  Future<LocalResetSnapshot> previewReset() async {
    resetPreviews++;
    return resetPreview;
  }

  @override
  Future<LocalResetSnapshot> confirmReset(String resetId) async {
    resetConfirms++;
    if (resetResult == 'reset') durable = snap('available');
    return LocalResetSnapshot(resetResult, seconds: 0);
  }

  @override
  Future<LocalHistorySnapshot> confirm(String previewId) async {
    confirms++;
    if (failConfirm) {
      if (importOnFailedConfirm) durable = _imported;
      throw StateError('Synthetic lost reply.');
    }
    final result = confirmResult ?? _imported;
    if (result.state == LocalHistoryState.imported) durable = result;
    return result;
  }
}

LocalHistoryController controllerFor(FakeHistoryPort port) =>
    LocalHistoryController(port, pollInterval: Duration.zero);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in <String, String>{
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  test('wire accepts only state-consistent aggregate projections', () {
    expect(_previewed.seconds, 5400);
    expect(_imported.importedAt, isNotNull);
    for (final raw in [
      {...historyWire('available')}..remove('phase'),
      {...historyWire('available'), 'path': 'C:/private'},
      historyWire('ready'),
      historyWire('preview'),
      historyWire('imported'),
      historyWire('available', previewId: _preview, seconds: 1),
      historyWire('scanning', scanId: 'private/path', phase: 'scanning'),
      historyWire('available', processed: 3, total: 1),
      {...historyWire('available'), 'sessions': -1},
    ]) {
      expect(() => LocalHistoryWire.parse(raw), throwsFormatException);
    }
  });

  test('nothing is imported automatically; scan previews, confirm imports', () async {
    final port = FakeHistoryPort()
      ..scanSteps = [_scanning, _scanning, _previewed];
    final c = controllerFor(port);
    addTearDown(c.dispose);
    await c.refresh();
    expect(port.starts, 0);
    expect(c.value.outcome, LocalHistoryOutcome.incomplete);
    await c.scan();
    expect(c.value.snapshot.state, LocalHistoryState.preview);
    expect(port.confirms, 0, reason: 'a preview is not an import');
    await c.confirm();
    expect(c.value.imported, true);
    expect(c.value.outcome, LocalHistoryOutcome.saved);
    await c.scan();
    await c.confirm();
    expect(port.starts, 1, reason: 'imported state blocks a second scan');
    expect(port.confirms, 1, reason: 'imported state blocks a second import');
  });

  test('already imported shows real state and offers no import', () async {
    final port = FakeHistoryPort()..durable = _imported;
    final c = controllerFor(port);
    addTearDown(c.dispose);
    await c.refresh();
    expect(c.value.imported, true);
    expect(c.value.canScan, false);
    expect(c.value.canSkip, false);
  });

  test('failed confirm keeps preview retryable and reports failure', () async {
    final port = FakeHistoryPort()
      ..scanSteps = [_previewed]
      ..confirmResult = snap('unavailable');
    final c = controllerFor(port);
    addTearDown(c.dispose);
    await c.refresh();
    await c.scan();
    port.durable = _previewed; // Host keeps the ticket after a failed write.
    await c.confirm();
    expect(c.value.failure, LocalHistoryFailure.confirm);
    expect(c.value.outcome, LocalHistoryOutcome.failed);
    expect(c.value.canConfirm, true);
    port.confirmResult = null;
    await c.confirm();
    expect(c.value.outcome, LocalHistoryOutcome.saved);
    expect(c.value.failure, LocalHistoryFailure.none);
  });

  test('lost confirm reply is never resent; actual state is read', () async {
    final port = FakeHistoryPort()
      ..scanSteps = [_previewed]
      ..failConfirm = true
      ..importOnFailedConfirm = true;
    final c = controllerFor(port);
    addTearDown(c.dispose);
    await c.refresh();
    await c.scan();
    await c.confirm();
    expect(port.confirms, 1);
    expect(c.value.imported, true);
    expect(c.value.failure, LocalHistoryFailure.none);
  });

  test('empty and cancelled scans stay retryable; skip writes nothing', () async {
    final port = FakeHistoryPort()..scanSteps = [snap('empty')];
    final c = controllerFor(port);
    addTearDown(c.dispose);
    await c.refresh();
    await c.scan();
    expect(c.value.lastResult, LocalHistoryState.empty);
    expect(c.value.canScan, true);
    expect(c.value.outcome, LocalHistoryOutcome.incomplete);
    c.skip();
    expect(c.value.outcome, LocalHistoryOutcome.skipped);
    expect(port.confirms, 0);
    port.scanSteps = List.filled(50, _scanning, growable: true);
    final running = c.scan();
    await Future<void>.delayed(Duration.zero);
    await c.cancel();
    await running;
    expect(port.cancels, 1);
    expect(c.value.lastResult, LocalHistoryState.cancelled);
    expect(c.value.skipped, false, reason: 'a new attempt clears skip');
  });

  test('reset needs explicit confirmation and restores the import', () async {
    final port = FakeHistoryPort()..durable = _imported;
    final c = controllerFor(port);
    addTearDown(c.dispose);
    await c.refresh();
    LocalResetSnapshot? shown;
    await c.reset((preview) async {
      shown = preview;
      return false;
    });
    expect(shown?.seconds, 9000);
    expect(port.resetConfirms, 0, reason: 'declined dialog writes nothing');
    expect(c.value.imported, true);
    await c.reset((_) async => true);
    expect(port.resetConfirms, 1);
    expect(c.value.reset, LocalResetResult.done);
    expect(c.value.imported, false);
    expect(c.value.canScan, true, reason: 'one import is available again');
  });

  test('empty or failed reset keeps state and reports it', () async {
    final port = FakeHistoryPort()
      ..durable = _imported
      ..resetPreview = const LocalResetSnapshot('empty', seconds: 0);
    final c = controllerFor(port);
    addTearDown(c.dispose);
    await c.refresh();
    await c.reset((_) async => true);
    expect(c.value.reset, LocalResetResult.empty);
    expect(port.resetConfirms, 0);
    port
      ..resetPreview = const LocalResetSnapshot(
        'ready',
        resetId: 'cccccccccccccccccccccccccccccccc',
        seconds: 5,
      )
      ..resetResult = 'unavailable';
    await c.reset((_) async => true);
    expect(c.value.reset, LocalResetResult.failed);
    expect(c.value.imported, true, reason: 'original data kept');
  });

  test('summary distinguishes saved, skipped, incomplete and failed', () {
    final view = OnboardingView(
      step: OnboardingStep.summary,
      mode: OnboardingMode.local,
      facts: facts(confirmed: true, signedIn: false, matched: false),
    );
    LocalStatisticsView stats(String state, String consent) =>
        LocalStatisticsView(
          snapshot: LocalStatisticsSnapshot(
            state: LocalStatisticsState.values.byName(state),
            choiceKey: '11111111111111111111111111111111',
            consent: LocalStatisticsConsent.values.byName(consent),
            savedSeconds: 0,
          ),
        );
    SummaryStatus status(List<SummaryEntry> e, SummaryItem item) =>
        e.singleWhere((x) => x.item == item).status;

    var entries = buildOnboardingSummary(
      view: view,
      statistics: stats('saved', 'declined'),
      history: LocalHistoryView(snapshot: snap('recordingRequired')),
    );
    expect(status(entries, SummaryItem.identity), SummaryStatus.saved);
    expect(status(entries, SummaryItem.recording), SummaryStatus.saved);
    expect(status(entries, SummaryItem.history), SummaryStatus.incomplete);
    expect(entries.any((e) => e.item == SummaryItem.onlineChoices), false);

    entries = buildOnboardingSummary(
      view: view,
      statistics: stats('retryRequired', 'unknown'),
      history: LocalHistoryView(snapshot: snap('available'), skipped: true),
    );
    expect(status(entries, SummaryItem.recording), SummaryStatus.failed);
    expect(status(entries, SummaryItem.history), SummaryStatus.skipped);

    entries = buildOnboardingSummary(
      view: view,
      statistics: stats('choiceRequired', 'unknown'),
      history: LocalHistoryView(
        snapshot: snap('available'),
        failure: LocalHistoryFailure.scan,
      ),
    );
    expect(status(entries, SummaryItem.recording), SummaryStatus.incomplete);
    expect(status(entries, SummaryItem.history), SummaryStatus.failed);

    entries = buildOnboardingSummary(
      view: view,
      history: LocalHistoryView(snapshot: _imported),
    );
    expect(status(entries, SummaryItem.history), SummaryStatus.saved);

    final unconfirmed = buildOnboardingSummary(
      view: OnboardingView(
        step: OnboardingStep.summary,
        mode: OnboardingMode.local,
        facts: facts(
          confirmed: false,
          localReady: false,
          signedIn: false,
          matched: false,
        ),
      ),
    );
    expect(status(unconfirmed, SummaryItem.identity), SummaryStatus.incomplete);
    expect(status(unconfirmed, SummaryItem.device), SummaryStatus.incomplete);
  });

  testWidgets('finish page renders actual outcomes, not navigation', (
    tester,
  ) async {
    final port = FakeHistoryPort()..durable = _imported;
    final history = controllerFor(port);
    addTearDown(history.dispose);
    await history.refresh();
    await pumpSetup(
      tester,
      step: OnboardingStep.summary,
      mode: OnboardingMode.local,
      observation: facts(confirmed: true, signedIn: false, matched: false),
      localHistory: history,
    );
    expect(find.byKey(const Key('summary-history-saved')), findsOneWidget);
    expect(find.byKey(const Key('summary-identity-saved')), findsOneWidget);
    expect(find.text('已导入，不会重复计入'), findsOneWidget);
    expect(find.textContaining('不会开启共享'), findsOneWidget);
  });

  testWidgets('local step offers optional import with explicit confirm', (
    tester,
  ) async {
    final port = FakeHistoryPort()..scanSteps = [_previewed];
    final history = controllerFor(port);
    addTearDown(history.dispose);
    await pumpSetup(
      tester,
      step: OnboardingStep.local,
      mode: OnboardingMode.local,
      observation: facts(confirmed: true, signedIn: false, matched: false),
      localHistory: history,
    );
    await tester.ensureVisible(find.byKey(const Key('history-scan')));
    await tester.tap(find.byKey(const Key('history-scan')));
    await tester.pumpAndSettle();
    expect(find.textContaining('找到 2 次记录'), findsOneWidget);
    expect(port.confirms, 0);
    await tester.ensureVisible(find.byKey(const Key('history-confirm')));
    await tester.tap(find.byKey(const Key('history-confirm')));
    await tester.pumpAndSettle();
    expect(port.confirms, 1);
    expect(find.textContaining('不会重复计入'), findsOneWidget);
  });

  testWidgets('reset opens a danger confirmation before writing', (
    tester,
  ) async {
    final port = FakeHistoryPort()..durable = _imported;
    final history = controllerFor(port);
    addTearDown(history.dispose);
    await pumpSetup(
      tester,
      step: OnboardingStep.local,
      mode: OnboardingMode.local,
      observation: facts(confirmed: true, signedIn: false, matched: false),
      localHistory: history,
    );
    await tester.ensureVisible(find.byKey(const Key('history-reset')));
    await tester.tap(find.byKey(const Key('history-reset')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-reset-dialog')), findsOneWidget);
    expect(find.textContaining('2 小时 30 分钟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-reset-keep')));
    await tester.pumpAndSettle();
    expect(port.resetConfirms, 0);
    await tester.tap(find.byKey(const Key('history-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-reset-confirm')));
    await tester.pumpAndSettle();
    expect(port.resetConfirms, 1);
    expect(find.textContaining('已重置本机时长'), findsOneWidget);
  });
}
