import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/settings/application_update_announcement.dart';
import 'package:starbridge_flutter/features/settings/application_update_dialog.dart';
import 'package:starbridge_flutter/features/settings/application_update_hero.dart';
import 'package:starbridge_flutter/features/settings/application_update_panel.dart';
import 'package:starbridge_flutter/features/settings/application_update_poster.dart';
import 'package:starbridge_flutter/features/settings/application_update_status.dart';

const _posterNotes =
    '# 主舰队上线（测试版）\n'
    '交易大厅接入 SCM 市场，社区组织换上新的两屏页面。\n'
    '- 【主舰队】成员、聊天、舰船、管理和召集都接进了客户端\n'
    '- 【交易大厅】接入 SCM 市场，挂单、关注和交易私信都在这里\n'
    '- 【社区组织】已加入的组织换成和主舰队同样的两屏页面\n'
    '- 【城市成就】到达四座城市，游戏日志确认地点后解锁\n'
    '\n'
    '## 完整更新内容\n'
    '- 第一条很长的完整记录';

void main() {
  group('UpdateAnnouncement.parse', () {
    test('reads headline, test version, subline, cards and the rest', () {
      final value = UpdateAnnouncement.parse(_posterNotes)!;
      expect(value.headline, '主舰队上线');
      expect(value.isTestVersion, isTrue);
      expect(value.subline, startsWith('交易大厅接入'));
      expect(value.highlights.map((e) => e.label), [
        '主舰队',
        '交易大厅',
        '社区组织',
        '城市成就',
      ]);
      expect(value.fullNotes, startsWith('## 完整更新内容'));
      expect(value.fullNotes, contains('第一条很长的完整记录'));
    });

    test('accepts Windows line endings from the release script', () {
      final value = UpdateAnnouncement.parse(
        _posterNotes.replaceAll('\n', '\r\n'),
      )!;
      expect(value.highlights, hasLength(4));
      expect(value.fullNotes, isNot(contains('\r')));
    });

    test('keeps at most four cards and works without the rest', () {
      final value = UpdateAnnouncement.parse(
        '# 标题\n- 【一】a\n- 【二】b\n- 【三】c\n- 【四】d\n- 【五】e',
      )!;
      expect(value.highlights, hasLength(4));
      expect(value.isTestVersion, isFalse);
      expect(value.subline, isNull);
      expect(value.fullNotes, isNull);
    });

    for (final notes in <String?>[
      null,
      '',
      '普通说明\n- 【主舰队】a\n- 【交易】b\n- 【组织】c',
      '# 只有标题',
      '# 太少\n- 【一】a\n- 【二】b',
      '# 混了普通条目\n- 【一】a\n- 【二】b\n- 【三】c\n- 普通',
      '## 优化\n- 【一】a\n- 【二】b\n- 【三】c',
    ]) {
      test('falls back to ordinary notes: $notes', () {
        expect(UpdateAnnouncement.parse(notes), isNull);
      });
    }

    test('moves a plain title out of ordinary notes', () {
      final split = splitUpdateNotesTitle('# 小更新\n- 一条\n- 两条');
      expect(split.title, '小更新');
      expect(split.notes, isNot(contains('# 小更新')));
      expect(split.notes, contains('- 两条'));
      expect(splitUpdateNotesTitle('- 一条').title, isNull);
    });
  });

  for (final mode in AppearanceMode.values) {
    testWidgets(
      'poster shows the headline and cards, not the raw notes $mode',
      (tester) async {
        await pumpPoster(tester, mode: mode);
        expect(find.byType(ApplicationUpdatePoster), findsOneWidget);
        expect(find.text('主舰队上线'), findsOneWidget);
        expect(find.text('测试版'), findsOneWidget);
        expect(find.text('0.7.2'), findsOneWidget);
        expect(find.text('交易大厅'), findsOneWidget);
        expect(find.text('发现新版本'), findsNothing);
        expect(find.byType(UpdateReleaseNotes), findsNothing);
        expect(find.text('更新并重启'), findsOneWidget);
        expect(find.text('稍后'), findsOneWidget);
        expect(find.textContaining('再问你一次'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('full notes open and close without losing the buttons', (
    tester,
  ) async {
    await pumpPoster(tester);
    await tester.tap(find.byKey(const Key('update-full-notes')));
    await tester.pumpAndSettle();
    expect(find.textContaining('第一条很长的完整记录'), findsOneWidget);
    expect(find.text('城市成就'), findsNothing);
    expect(find.text('更新并重启'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update-full-notes')));
    await tester.pumpAndSettle();
    expect(find.text('城市成就'), findsOneWidget);
    expect(find.byType(UpdateReleaseNotes), findsNothing);
  });

  testWidgets('download turns the bottom into progress, cards stay', (
    tester,
  ) async {
    final progress = StreamController<Map<String, dynamic>>.broadcast();
    final reply = Completer<Map<String, dynamic>>();
    addTearDown(progress.close);
    await pumpPoster(
      tester,
      progress: progress.stream,
      prepare: (_) => reply.future,
    );
    await tester.tap(find.byKey(const Key('update-download')));
    await tester.pump();
    expect(find.byKey(const Key('update-steps')), findsOneWidget);
    expect(find.text('城市成就'), findsOneWidget);
    expect(find.byKey(const Key('update-close')), findsOneWidget);
    expect(find.byKey(const Key('update-cancel')), findsOneWidget);
    progress.add({
      'schemaVersion': 1,
      'requestId': 'fixture',
      'version': '0.7.2',
      'phase': 'downloading',
      'receivedBytes': 1048576,
      'totalBytes': 2097152,
    });
    await tester.pump();
    expect(find.text('50% · 1.0 / 2.0 MB'), findsOneWidget);
    reply.complete({
      'schemaVersion': 1,
      'version': '0.7.2',
      'ticket': 'a' * 32,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('update-install')), findsOneWidget);
    expect(find.text('重启并安装'), findsOneWidget);
  });

  testWidgets('failure says what to do next and offers another try', (
    tester,
  ) async {
    await pumpPoster(tester, prepare: (_) async => throw StateError('no'));
    await tester.tap(find.byKey(const Key('update-download')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('scstarbridge.com'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('城市成就'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(900, 620), Size(1280, 800), Size(390, 540)]) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('primary action stays on screen at $size text $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpPoster(tester, scale: scale);
        final button = find.byKey(const Key('update-download'));
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('public builds without the art still show every word', (
    tester,
  ) async {
    await pumpPoster(tester, bundle: _MissingArtBundle());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.text('主舰队上线'), findsOneWidget);
    expect(find.text('城市成就'), findsOneWidget);
    expect(find.text('更新并重启'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('readApplicationUpdateHero', () {
    final image = Uint8List.fromList(List.generate(600000, (i) => i % 251));
    final digest = sha256.convert(image).toString();
    Map<String, dynamic> reply(int offset, {int size = 262144}) {
      final end = (offset + size).clamp(0, image.length);
      return {
        'schemaVersion': 1,
        'version': '0.7.4',
        'mediaType': 'image/jpeg',
        'sha256': digest,
        'length': image.length,
        'offset': offset,
        'nextOffset': end,
        'chunk': base64Encode(image.sublist(offset, end)),
        'done': end == image.length,
      };
    }

    test('joins chunks and checks the hash', () async {
      final offsets = <int>[];
      final bytes = await readApplicationUpdateHero((version, offset) async {
        offsets.add(offset);
        return reply(offset);
      }, '0.7.4');
      expect(bytes, image);
      expect(offsets, [0, 262144, 524288]);
    });

    final bad = <String, Map<String, dynamic> Function(int)>{
      'wrong hash': (o) => {...reply(o), 'sha256': 'a' * 64},
      'hash changes between chunks': (o) => {
        ...reply(o),
        'sha256': o == 0 ? digest : 'b' * 64,
      },
      'wrong version': (o) => {...reply(o), 'version': '0.7.5'},
      'wrong offset': (o) => {...reply(o), 'offset': o + 1},
      'extra field': (o) => {...reply(o), 'url': 'https://example.invalid'},
      'unknown type': (o) => {...reply(o), 'mediaType': 'image/svg+xml'},
      'too large': (o) => {...reply(o), 'length': 3145729},
      'oversized chunk': (o) => reply(o, size: 262145),
      'done too early': (o) => {...reply(o), 'done': true},
      'not base64': (o) => {...reply(o), 'chunk': '!!!'},
    };
    bad.forEach((name, build) {
      test('rejects $name', () async {
        expect(
          await readApplicationUpdateHero(
            (version, offset) async => build(offset),
            '0.7.4',
          ),
          isNull,
        );
      });
    });

    test('a failed request or stale dialog gives nothing', () async {
      expect(
        await readApplicationUpdateHero(
          (version, offset) async => throw StateError('offline'),
          '0.7.4',
        ),
        isNull,
      );
      expect(
        await readApplicationUpdateHero(
          (version, offset) async => reply(offset),
          '0.7.4',
          isCurrent: () => false,
        ),
        isNull,
      );
    });
  });

  group('hero line in the notes', () {
    final line = '主图校验 sha256=${'a' * 64} bytes=1024';

    test('is recognised once and never shown', () {
      expect(updateNotesHaveHero('$_posterNotes\n$line'), isTrue);
      expect(updateNotesHaveHero('$_posterNotes\r\n$line'), isTrue);
      expect(updateNotesHaveHero(_posterNotes), isFalse);
      expect(updateNotesHaveHero('$_posterNotes\n$line\n$line'), isFalse);
      expect(
        updateNotesHaveHero('$_posterNotes\n主图校验 sha256=abc bytes=1'),
        isFalse,
      );
      expect(updateNotesHaveHero('$line\n$_posterNotes'), isFalse);
      expect(updateNotesHaveHero('$_posterNotes\n $line'), isFalse);
      expect(updateNotesHaveHero('$_posterNotes\n$line\n'), isTrue);
      expect(
        stripUpdateHeroLine('# 标题\n $line \n- 一条'),
        isNot(contains('主图校验')),
      );
      final parsed = UpdateAnnouncement.parse('$_posterNotes\n$line')!;
      expect(parsed.fullNotes, isNot(contains('主图校验')));
    });

    testWidgets('poster asks for the art only when the notes name it', (
      tester,
    ) async {
      final asked = <String>[];
      await pumpPoster(
        tester,
        readHero: (version, offset) async {
          asked.add(version);
          throw StateError('offline');
        },
      );
      expect(asked, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await pumpPoster(
        tester,
        notes: '$_posterNotes\n$line',
        readHero: (version, offset) async {
          asked.add(version);
          throw StateError('offline');
        },
      );
      expect(asked, ['0.7.2']);
      expect(find.byKey(const Key('update-hero-image')), findsNothing);
      expect(find.text('主舰队上线'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a small update never asks and never shows the line', (
      tester,
    ) async {
      var asked = false;
      await pumpPoster(
        tester,
        version: '0.7.2.1',
        notes: '# 小更新\n- 修好了\n$line',
        readHero: (version, offset) async {
          asked = true;
          throw StateError('no');
        },
      );
      expect(asked, isFalse);
      expect(find.textContaining('主图校验'), findsNothing);
    });

    testWidgets('verified art appears; undecodable art leaves the fallback', (
      tester,
    ) async {
      // 1×1 的 PNG。
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
      Future<Map<String, dynamic>> answer(List<int> bytes) async => {
        'schemaVersion': 1,
        'version': '0.7.2',
        'mediaType': 'image/png',
        'sha256': sha256.convert(bytes).toString(),
        'length': bytes.length,
        'offset': 0,
        'nextOffset': bytes.length,
        'chunk': base64Encode(bytes),
        'done': true,
      };
      await pumpPoster(
        tester,
        notes: '$_posterNotes\n$line',
        readHero: (version, offset) => answer(png),
      );
      await tester.pump();
      expect(find.byKey(const Key('update-hero-image')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpPoster(
        tester,
        notes: '$_posterNotes\n$line',
        readHero: (version, offset) => answer(const [1, 2, 3, 4]),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(find.text('主舰队上线'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a small update never uses the poster', (tester) async {
    expect(isMajorUpdateVersion('0.7.3'), isTrue);
    expect(isMajorUpdateVersion('0.7.3.1'), isFalse);
    await pumpPoster(tester, version: '0.7.2.1');
    expect(find.byType(ApplicationUpdatePoster), findsNothing);
    expect(find.byType(ApplicationUpdatePanel), findsOneWidget);
    expect(find.text('主舰队上线（测试版）'), findsOneWidget);
    expect(find.text('0.7.2.1'), findsOneWidget);
  });

  testWidgets('ordinary notes keep the plain panel with the banner', (
    tester,
  ) async {
    await pumpPoster(tester, notes: '# 小更新\n- 修好了一处显示');
    expect(find.byType(ApplicationUpdatePoster), findsNothing);
    expect(find.byType(ApplicationUpdatePanel), findsOneWidget);
    expect(find.text('小更新'), findsOneWidget);
    expect(find.text('修好了一处显示'), findsOneWidget);
    expect(find.text('0.7.2'), findsOneWidget);
    expect(find.text('更新并重启'), findsOneWidget);
  });
}

class _MissingArtBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key.contains('home-scenes') || key.contains('achievements')) {
      throw FlutterError('missing $key');
    }
    return rootBundle.load(key);
  }
}

Future<void> pumpPoster(
  WidgetTester tester, {
  AssetBundle? bundle,
  ApplicationUpdateHeroRead? readHero,
  String version = '0.7.2',
  AppearanceMode mode = AppearanceMode.dark,
  double scale = 1,
  String notes = _posterNotes,
  Stream<Map<String, dynamic>>? progress,
  ApplicationUpdatePrepare? prepare,
}) async {
  const locale = Locale('zh', 'CN');
  await tester.pumpWidget(
    DefaultAssetBundle(
      bundle: bundle ?? rootBundle,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildStarBridgeTheme(FutureRestraintStyle.resolve(mode), locale),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ApplicationUpdateDialog(
            startupAnnouncement: true,
            progress: progress,
            readHero: readHero,
            initialStatus: ApplicationUpdateStatus.parse({
              'schemaVersion': 1,
              'state': 'available',
              'currentVersion': '0.7.1',
              'availableVersion': version,
              'notes': notes,
            }),
            prepare: prepare ?? (_) async => throw StateError('Never installs'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
