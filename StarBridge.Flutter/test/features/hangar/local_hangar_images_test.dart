import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar_images.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_image_editor.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_images.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

const image =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const owner = BridgeAccountContext(
  environment: 'fixture',
  authority: 'scm',
  subject: 'owner',
);
void main() {
  testWidgets(
    'same instance metadata refresh retains image until new lease resolves',
    (tester) async {
      Widget app(_Port port, {bool preserve = true}) => MaterialApp(
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: LocalHangarImageEditor(
            port: port,
            onSaved: () {},
            preserveImageOnPortChange: preserve,
            fallback: const Text('catalog'),
          ),
        ),
      );
      final first = _Port()..currentImage = image;
      await tester.pumpWidget(app(first));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final next = _Port()..pendingRead = Completer<String?>();
      await tester.pumpWidget(app(next));
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('catalog'), findsNothing);
      next.pendingRead!.complete(image);
      await tester.pumpAndSettle();
      final different = _Port()..pendingRead = Completer<String?>();
      await tester.pumpWidget(app(different, preserve: false));
      await tester.pump();
      expect(find.text('catalog'), findsOneWidget);
      different.pendingRead!.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test('adapter sends only scoped references, saves explicitly and rejects stale generation', () async {
    final connection = _Connection();
    final session = BridgeClientSession(
      connection: connection,
      sessionGeneration: 1,
    )..acceptHostCapabilities(['hangar.localImages']);
    addTearDown(session.close);
    final port = BridgeLocalHangarImages(session, owner, 1, 'ship', 2);
    expect(await port.readImage(), isNull);
    final source = (await port.pickLogo())!;
    expect(await port.cropLogo(source.sourceRef, 0, 0, 1), image);
    expect(
      connection.requests.any((r) => r.name == 'hangarImage.save'),
      isFalse,
    );
    await port.saveImage();
    expect(port.revision, 3);
    final save = connection.requests.last;
    expect(save.payload.keys.toSet(), {'schemaVersion', 'draftRef'});
    expect(save.accountContext?.subject, 'owner');
    session.advanceGeneration(2);
    final count = connection.requests.length;
    await expectLater(port.pickLogo(), throwsA(isA<LocalHangarFailure>()));
    expect(connection.requests.length, count);
  });
  testWidgets('cancelled picker never saves and readonly history hides edit', (
    tester,
  ) async {
    final port = _Port()..cancel = true;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: LocalHangarImageEditor(
            port: port,
            onSaved: () {},
            fallback: const Text('catalog'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hangar-image-choose')));
    await tester.pumpAndSettle();
    expect(port.saves, 0);
    expect(port.clears, 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: LocalHangarImageEditor(
            key: const Key('history'),
            port: port,
            editable: false,
            onSaved: () {},
            fallback: const Text('catalog'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-image-choose')), findsNothing);
  });
  testWidgets('crop is not save; explicit local confirmation saves once', (
    tester,
  ) async {
    final port = _Port()..pendingRead = Completer<String?>();
    var saved = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: LocalHangarImageEditor(
            port: port,
            onSaved: () => saved++,
            fallback: const Text('catalog'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hangar-image-choose')));
    await tester.pumpAndSettle();
    expect(port.saves, 0);
    await tester.tap(find.widgetWithText(FilledButton, 'Use image'));
    await tester.pumpAndSettle();
    expect(find.textContaining('does not upload'), findsOneWidget);
    expect(port.saves, 0);
    await tester.tap(find.byKey(const Key('hangar-image-confirm')));
    await tester.pumpAndSettle();
    expect(port.saves, 1);
    expect(saved, 1);
    expect(find.text('Saved locally.'), findsOneWidget);
    port.pendingRead!.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('catalog'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('removing the editor closes its crop and never saves', (
    tester,
  ) async {
    final port = _Port();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStringsDelegate()],
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, show, child) => show
                ? LocalHangarImageEditor(
                    port: port,
                    onSaved: () {},
                    fallback: const Text('catalog'),
                  )
                : const Text('Signed out'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hangar-image-choose')));
    await tester.pumpAndSettle();
    expect(find.text('Crop ship image'), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Crop ship image'), findsNothing);
    expect(find.text('Signed out'), findsOneWidget);
    expect(port.saves, 0);
    expect(port.clears, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'restore default requires confirmation and refreshes only after success',
    (tester) async {
      final port = _Port()..currentImage = image;
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStringsDelegate()],
          home: Scaffold(
            body: LocalHangarImageEditor(
              port: port,
              onSaved: () => changes++,
              fallback: const Text('catalog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-image-restore')));
      await tester.pumpAndSettle();
      expect(port.restores, 0);
      await tester.tap(find.text('Keep image'));
      await tester.pumpAndSettle();
      expect(port.restores, 0);
      expect(find.text('catalog'), findsNothing);
      await tester.tap(find.byKey(const Key('hangar-image-restore')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-image-restore-confirm')));
      await tester.pumpAndSettle();
      expect(port.restores, 1);
      expect(changes, 1);
      expect(find.text('catalog'), findsOneWidget);
      expect(find.text('Default image restored.'), findsOneWidget);
      expect(port.saves, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Connection implements BridgeConnection {
  final stream = StreamController<BridgeEnvelope>.broadcast();
  final requests = <BridgeEnvelope>[];
  @override
  Stream<BridgeEnvelope> get incoming => stream.stream;
  @override
  Future<void> close() => stream.close();
  @override
  Future<void> send(BridgeEnvelope request) async {
    requests.add(request);
    final body = <String, Object?>{
      'schemaVersion': 1,
      ...switch (request.name) {
        'hangarImage.read' => {'status': 'none'},
        'hangarImage.pick' => {
          'status': 'selected',
          'draftRef': 'a' * 32,
          'previewImageData': image,
          'width': 1,
          'height': 1,
        },
        'hangarImage.crop' => {
          'status': 'prepared',
          'draftRef': 'a' * 32,
          'previewImageData': image,
        },
        'hangarImage.save' => {'status': 'saved', 'revision': 3},
        _ => {'status': 'cleared'},
      },
    };
    stream.add(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: 1,
        accountContext: owner,
        status: 'ok',
        payload: body,
      ),
    );
  }
}

class _Port implements LocalHangarImagePort {
  Completer<String?>? pendingRead;
  bool cancel = false;
  int saves = 0, clears = 0, restores = 0;
  String? currentImage;
  @override
  bool get canPickLogo => true;
  @override
  Future<String?> readImage() =>
      pendingRead?.future ?? Future.value(currentImage);
  @override
  Future<void> restoreImage() async {
    restores++;
    currentImage = null;
  }

  @override
  Future<CommunityLogoSource?> pickLogo() async =>
      cancel ? null : CommunityLogoSource('a' * 32, image, 1, 1);
  @override
  Future<String> cropLogo(
    String sourceRef,
    double x,
    double y,
    double size,
  ) async => image;
  @override
  Future<void> saveImage() async {
    saves++;
  }

  @override
  Future<void> clearLogo() async {
    clears++;
  }
}
