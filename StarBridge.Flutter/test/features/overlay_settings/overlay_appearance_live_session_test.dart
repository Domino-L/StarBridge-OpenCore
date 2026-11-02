import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';

import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_live_session.dart';

OverlayWorkspaceSettings settings() => OverlayWorkspaceSettings.fromMap({
  'hideMissionWhenIdle': false,
  'showMission': false,
  for (final f in overlayWorkspaceFieldSpecs)
    f.field: switch (f.kind) {
      OverlayWorkspaceFieldKind.toggle => false,
      OverlayWorkspaceFieldKind.choice ||
      OverlayWorkspaceFieldKind.readOnlyChoice => f.options.first,
      OverlayWorkspaceFieldKind.numberChoice => f.numberOptions.first,
      OverlayWorkspaceFieldKind.number =>
        f.field == 'chatMaxVisibleCount' ? f.minimum.round() : f.minimum,
      OverlayWorkspaceFieldKind.color => '#FFFFFF',
      OverlayWorkspaceFieldKind.hotkey => '',
      OverlayWorkspaceFieldKind.eventTypes => 0,
      OverlayWorkspaceFieldKind.eventDurations => {
        for (final e in overlayDurationFields) e.$1: 0,
        'squadChange': 0,
        'commanderChange': 0,
      },
    },
});
const layoutItem = OverlayWorkspaceLayoutItem(
  key: 'Squads',
  x: .23,
  y: .41,
  width: .2,
  height: .2,
  horizontalAnchor: 'Left',
  verticalAnchor: 'Middle',
  isLocked: true,
  textOpacity: .7,
  backgroundOpacity: .6,
);
List<OverlayWorkspaceLayoutItem> fullLayout() => [
  for (final key in ['Squads', 'Members', 'Notice', 'Chat'])
    OverlayWorkspaceLayoutItem.fromMap({...layoutItem.toMap(), 'key': key}),
];
OverlayAppearanceLiveFrame frame([
  String id = 'HajiCitizen',
  bool reduced = false,
]) => OverlayAppearanceLiveFrame(
  appearanceId: id,
  settings: settings(),
  layout: fullLayout(),
  options: const OverlayAppearanceOptions.empty(),
  language: 'zh-CN',
  reduceMotion: reduced,
);

class Port implements OverlayAppearanceLivePort {
  final opens = <OverlayAppearanceLiveFrame>[];
  final updates = <(String, int, OverlayAppearanceLiveFrame)>[];
  final closes = <String>[];
  Completer<String>? opening;
  Completer<int>? updating;
  Completer<void>? closing;
  bool failUpdate = false, failClose = false;
  int? badRevision;
  final renewals = <int>[];
  Completer<int>? renewing;
  bool failRenew = false;
  @override
  Future<int> renewLivePreview(String id, int revision) async {
    renewals.add(revision);
    if (failRenew) throw StateError('renew failed');
    return renewing?.future ?? revision;
  }

  @override
  Future<String> openLivePreview(OverlayAppearanceLiveFrame f) async {
    opens.add(f);
    return opening?.future ?? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  }

  @override
  Future<int> updateLivePreview(
    String id,
    int revision,
    OverlayAppearanceLiveFrame f,
  ) async {
    updates.add((id, revision, f));
    if (failUpdate) throw StateError('update failed');
    return updating?.future ?? badRevision ?? revision;
  }

  @override
  Future<void> closeLivePreview(String id) async {
    closes.add(id);
    if (failClose) throw StateError('close failed');
    await closing?.future;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.value();
  }
}

final class PlaybackPort extends Port
    implements OverlayAppearanceLivePlaybackPort {
  final plays = <(int, OverlayAppearancePreviewPlayback)>[];
  Completer<bool>? playing;
  @override
  Future<bool> playLivePreview(
    String id,
    int revision,
    OverlayAppearancePreviewPlayback action,
  ) async {
    plays.add((revision, action));
    return await playing?.future ?? true;
  }
}

void main() {
  testWidgets(
    'one delayed renewal blocks duplicates; close waits and stops renewal without reopen',
    (tester) async {
      final port = Port()..renewing = Completer<int>();
      final session = OverlayAppearanceLiveSession(port);
      await session.open(frame());
      await tester.pump(const Duration(seconds: 30));
      expect(port.renewals, [1]);
      await tester.pump(const Duration(seconds: 60));
      expect(port.renewals, [1]);
      final closing = session.close();
      await tester.pump();
      expect(port.closes, isEmpty);
      port.renewing!.complete(1);
      await tester.pump();
      await closing;
      await tester.pump(const Duration(minutes: 3));
      expect(port.renewals, [1]);
      expect(port.opens, hasLength(1));
      expect(port.closes, hasLength(1));
      expect(port.updates, isEmpty);
      session.dispose();
    },
  );

  testWidgets('renewal failure closes once without auto-reopen or replay', (
    tester,
  ) async {
    final port = Port()..failRenew = true;
    final session = OverlayAppearanceLiveSession(port);
    await session.open(frame());
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(session.phase, OverlayAppearanceLivePhase.closed);
    await tester.pump(const Duration(minutes: 3));
    expect(port.renewals, [1]);
    expect(port.opens, hasLength(1));
    expect(port.closes, hasLength(1));
    expect(port.updates, isEmpty);
    session.dispose();
  });

  testWidgets('disposal before late open never starts a liveness timer', (
    tester,
  ) async {
    final port = Port()..opening = Completer<String>();
    final session = OverlayAppearanceLiveSession(port);
    final opening = session.open(frame());
    await tester.pump(const Duration(minutes: 3));
    expect(port.renewals, isEmpty);
    session.dispose();
    port.opening!.complete('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    await opening;
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(port.renewals, isEmpty);
    expect(port.closes, ['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb']);
  });

  test(
    'playback waits for latest draft; rapid repeated intent is not queued',
    () async {
      final port = PlaybackPort()..updating = Completer<int>();
      final session = OverlayAppearanceLiveSession(port);
      await session.open(frame());
      session.update(frame('Verdict'));
      final play = session.play(OverlayAppearancePreviewPlayback.eventAdd);
      expect(port.plays, isEmpty);
      expect(
        () => session.play(OverlayAppearancePreviewPlayback.eventAdd),
        throwsStateError,
      );
      port.updating!.complete(1);
      expect(await play, isTrue);
      expect(port.plays, [(1, OverlayAppearancePreviewPlayback.eventAdd)]);
      expect(session.playbackBusy, isFalse);
      await session.close();
      session.dispose();
    },
  );
  test('close waits for in-flight playback and never makes a late receipt successful', () async {
    final port = PlaybackPort()..playing = Completer<bool>();
    final session = OverlayAppearanceLiveSession(port);
    await session.open(frame());
    final play = session.play(OverlayAppearancePreviewPlayback.noticeShow);
    await flush();
    final close = session.close();
    await flush();
    expect(port.closes, isEmpty);
    port.playing!.complete(true);
    expect(await play, isFalse);
    await close;
    expect(port.closes.length, 1);
    expect(session.phase, OverlayAppearanceLivePhase.closed);
    session.dispose();
  });
  test('finite frame carries real layout but no source, hotkey, account or pet instruction', () {
    final items = fullLayout();
    final f = OverlayAppearanceLiveFrame(
      appearanceId: 'Default',
      settings: settings(),
      layout: items,
      options: const OverlayAppearanceOptions.empty(),
      language: 'en',
      reduceMotion: false,
    );
    items.clear();
    expect(f.layout.first.x, .23);
    expect(f.layout.first.isLocked, isTrue);
    expect(() => f.layout.clear(), throwsUnsupportedError);
    expect(f.toMap().keys.toSet(), {
      'appearanceId',
      'settings',
      'layout',
      'appearanceOptions',
      'language',
      'reduceMotion',
    });
    expect(() => frame('../asset'), throwsFormatException);
  });
  test('preview frame requires the complete normal four-module workspace', () {
    OverlayAppearanceLiveFrame withLayout(
      List<OverlayWorkspaceLayoutItem> items,
    ) => OverlayAppearanceLiveFrame(
      appearanceId: 'Default',
      settings: settings(),
      layout: items,
      options: const OverlayAppearanceOptions.empty(),
      language: 'en',
      reduceMotion: false,
    );
    expect(() => withLayout([layoutItem]), throwsFormatException);
    expect(
      () => withLayout([...fullLayout(), layoutItem]),
      throwsFormatException,
    );
    expect(
      () => withLayout([for (var i = 0; i < 4; i++) layoutItem]),
      throwsFormatException,
    );
    expect(
      () => withLayout([
        ...fullLayout().take(3),
        OverlayWorkspaceLayoutItem.fromMap({
          ...layoutItem.toMap(),
          'key': 'Crosshair',
        }),
      ]),
      throwsFormatException,
    );
  });
  for (final skin in ['Default', 'NightShadow', 'Verdict', 'HajiCitizen']) {
    test(
      '$skin uses the same one-session interface without pet-only branches',
      () async {
        final port = Port();
        final session = OverlayAppearanceLiveSession(port);
        await session.open(frame(skin));
        session.update(frame(skin, true));
        await flush();
        expect(port.opens.length, 1);
        expect(port.updates.single.$3.reduceMotion, isTrue);
        expect(session.appliedRevision, 1);
        await session.close();
        session.dispose();
        expect(port.closes.length, 1);
        expect(session.phase, OverlayAppearanceLivePhase.closed);
      },
    );
  }
  test('changes during pending open retain only latest draft and clean late session on exit', () async {
    final port = Port()..opening = Completer<String>();
    final session = OverlayAppearanceLiveSession(port);
    final opening = session.open(frame());
    session.update(frame('Verdict'));
    session.update(frame('Default', true));
    final closing = session.close();
    port.opening!.complete('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    await opening;
    await closing;
    expect(port.updates, isEmpty);
    expect(port.closes, ['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb']);
    expect(session.phase, OverlayAppearanceLivePhase.closed);
    session.dispose();
  });
  test('pending-open updates reach returned session without reopen', () async {
    final port = Port()..opening = Completer<String>();
    final session = OverlayAppearanceLiveSession(port);
    final opening = session.open(frame());
    session.update(frame('Verdict'));
    session.update(frame('Default', true));
    port.opening!.complete('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
    await opening;
    await flush();
    expect(port.updates.length, 1);
    expect(port.updates.single.$2, 2);
    expect(port.updates.single.$3.appearanceId, 'Default');
    await session.close();
    session.dispose();
  });
  test(
    'serial updates coalesce pending settings rather than queue all drafts',
    () async {
      final port = Port()..updating = Completer<int>();
      final session = OverlayAppearanceLiveSession(port);
      await session.open(frame());
      session.update(frame('Default'));
      session.update(frame('Verdict'));
      session.update(frame('NightShadow', true));
      expect(port.updates.length, 1);
      final pending = port.updating!;
      port.updating = null;
      pending.complete(1);
      await flush();
      expect(port.updates.map((u) => u.$2), [1, 3]);
      expect(port.updates.last.$3.appearanceId, 'NightShadow');
      expect(session.appliedRevision, 3);
      expect(port.opens.length, 1);
      await session.close();
      session.dispose();
    },
  );
  test(
    'exit waits for update; late receipt cannot resurrect live mode',
    () async {
      final port = Port()..updating = Completer<int>();
      final session = OverlayAppearanceLiveSession(port);
      await session.open(frame());
      session.update(frame());
      final closing = session.close();
      expect(() => session.update(frame()), throwsStateError);
      expect(port.closes, isEmpty);
      port.updating!.complete(1);
      await closing;
      expect(session.phase, OverlayAppearanceLivePhase.closed);
      expect(session.appliedRevision, 0);
      expect(port.closes.length, 1);
      session.dispose();
    },
  );
  test('failed update preserves latest draft for explicit retry, no automatic replay', () async {
    final port = Port()..failUpdate = true;
    final session = OverlayAppearanceLiveSession(port);
    await session.open(frame());
    session.update(frame('Verdict'));
    await flush();
    expect(session.phase, OverlayAppearanceLivePhase.failed);
    expect(session.appliedRevision, 0);
    expect(port.updates.length, 1);
    port.failUpdate = false;
    session.retryUpdate();
    await flush();
    expect(session.appliedRevision, 1);
    expect(port.updates.last.$3.appearanceId, 'Verdict');
    expect(port.opens.length, 1);
    await session.close();
    session.dispose();
  });
  test('incorrect revision receipt is not success', () async {
    final port = Port()..badRevision = 999;
    final session = OverlayAppearanceLiveSession(port);
    await session.open(frame());
    session.update(frame());
    await flush();
    expect(session.phase, OverlayAppearanceLivePhase.failed);
    expect(session.appliedRevision, 0);
    await session.close();
    session.dispose();
  });
  test(
    'listener edit on live receipt is drained, not lost behind old pump',
    () async {
      final port = Port();
      final session = OverlayAppearanceLiveSession(port);
      await session.open(frame());
      var edited = false;
      session.addListener(() {
        if (!edited &&
            session.phase == OverlayAppearanceLivePhase.live &&
            session.appliedRevision == 1) {
          edited = true;
          session.update(frame('Verdict', true));
        }
      });
      session.update(frame('Default'));
      await flush();
      expect(port.updates.map((u) => u.$2), [1, 2]);
      expect(session.appliedRevision, 2);
      expect(port.updates.last.$3.appearanceId, 'Verdict');
      await session.close();
      session.dispose();
    },
  );
  test(
    'disposal during pending open still cleans late native session once',
    () async {
      final port = Port()..opening = Completer<String>();
      final session = OverlayAppearanceLiveSession(port);
      final opening = session.open(frame());
      session.dispose();
      port.opening!.complete('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');
      await opening;
      await flush();
      expect(port.closes, ['bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb']);
      expect(port.updates, isEmpty);
      expect(session.phase, OverlayAppearanceLivePhase.closed);
    },
  );
  test(
    'close failure retains ownership and can retry without reopening',
    () async {
      final port = Port()..failClose = true;
      final session = OverlayAppearanceLiveSession(port);
      await session.open(frame());
      await expectLater(session.close(), throwsStateError);
      expect(session.hasSession, isTrue);
      expect(session.phase, OverlayAppearanceLivePhase.failed);
      port.failClose = false;
      await session.close();
      expect(session.hasSession, isFalse);
      expect(port.opens.length, 1);
      expect(port.closes.length, 2);
      session.dispose();
    },
  );
  test('concurrent closes share one native request', () async {
    final port = Port()..closing = Completer<void>();
    final session = OverlayAppearanceLiveSession(port);
    await session.open(frame());
    final a = session.close();
    final b = session.close();
    expect(identical(a, b), isTrue);
    await flush();
    expect(port.closes.length, 1);
    port.closing!.complete();
    await a;
    session.dispose();
  });
}
