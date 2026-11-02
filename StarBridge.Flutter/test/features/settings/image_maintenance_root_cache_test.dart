import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/features/communities/community_directory_card.dart';
import 'package:starbridge_flutter/features/communities/community_directory_details.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/shared/embedded_avatar.dart';

import '../../design_system/interaction/interaction_batch3do_test.dart'
    show size, loadFonts;
import 'image_maintenance_directory_native_test.dart' show NativeDirectoryHost;

class RootImageHost extends NativeDirectoryHost {
  RootImageHost(super.wire);
  bool failClear = false;
  @override
  Future<void> reply(BridgeEnvelope request) {
    if (failClear && request.name == 'diagnostics.clearImageCache') {
      return connection.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: request.accountContext,
          status: 'error',
          payload: const {},
          error: const BridgeErrorBody(
            code: 'diagnostics.testFailure',
            message: 'Synthetic maintenance refusal',
            retryable: false,
          ),
        ),
      );
    }
    if (request.name == 'communities.read' &&
        request.payload['view'] != 'discover') {
      return connection.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: request.accountContext,
          status: 'ok',
          payload: {
            'schemaVersion': 1,
            'view': request.payload['view'],
            'query': request.payload['query'],
            'items': <Object?>[],
            'next': null,
          },
        ),
      );
    }
    return super.reply(request);
  }
}

void main() {
  final path =
      Platform.environment['STARBRIDGE_DIRECTORY_IMAGE_MAINTENANCE_FIXTURE'];
  final missing = path == null || !File(path).existsSync();
  setUpAll(loadFonts);
  for (final fails in [false, true]) {
    for (final retained in [false, true]) {
      testWidgets(
        'real root retires downloaded providers and keeps originals/portraits (Native failure=$fails; retainedDetails=$retained)',
        (t) async {
          size(t, const Size(1600, 1100));
          final host = RootImageHost(
            jsonDecode(File(path!).readAsStringSync()) as Map<String, dynamic>,
          );
          host.failClear = fails;
          final preferences = InMemoryAppPreferences();
          final app = AppComposition.forConnectedProduct(
            nativeHost: host,
            preferences: preferences,
            windowChrome: InMemoryWindowChrome(),
          );
          final navigator = GlobalKey<NavigatorState>();
          var mountedRoot = false;
          Future<String?> render(Color color) => t.runAsync(() async {
            final recorder = ui.PictureRecorder();
            Canvas(
              recorder,
            ).drawRect(const Rect.fromLTWH(0, 0, 3, 3), Paint()..color = color);
            final picture = recorder.endRecording();
            final image = await picture.toImage(3, 3);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            picture.dispose();
            return 'data:image/png;base64,${base64Encode(data!.buffer.asUint8List())}';
          });
          final avatar = await render(Colors.green);
          final original = await render(Colors.red);
          final downloaded = (await render(Colors.blue))!;
          final mediaBytes = base64Decode(
            downloaded.substring(downloaded.indexOf(',') + 1),
          );
          // Preserve Native protocol/identity transitions, but replace its header-only
          // transport bytes with renderable media for this decoder-lifetime check.
          for (final name in ['beforeMedia', 'afterMedia']) {
            host.wire[name] = {
              ...host.wire[name] as Map,
              'data': base64Encode(mediaBytes),
              'version': sha256.convert(mediaBytes).toString(),
              'totalBytes': mediaBytes.length,
              'offset': 0,
              'next': null,
            };
          }
          try {
            final reading = app.communities.refresh(newView: 'discover');
            await t.pump();
            await reading;
            final source = app.communities.directory!.items.single.logo;
            var shownSnapshot = app.communities.directory!.items.single;
            expect(source, isNotNull);
            mountedRoot = true;
            await t.pumpWidget(
              StarBridgeApp(
                composition: app,
                navigatorKey: navigator,
                canPresentIdentityPrompt: () => false,
              ),
            );
            await t.pump();
            Widget page(BuildContext context) => Scaffold(
              body: ListenableBuilder(
                listenable: app.communities,
                builder: (context, _) => Row(
                  children: [
                    SizedBox(
                      width: 420,
                      height: retained ? 1000 : 600,
                      child: retained
                          ? CommunityDirectoryDetails(
                              key: const Key('root-directory-card'),
                              row: shownSnapshot,
                              text: AppStrings.of(context).text,
                              onClose: () {},
                            )
                          : CommunityDirectoryCard(
                              key: const Key('root-directory-card'),
                              row: app.communities.directory!.items.single,
                              text: AppStrings.of(context).text,
                              onDetails: null,
                              onAction: null,
                            ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: EmbeddedAvatar(
                        key: const Key('protected-root-portrait'),
                        source: avatar,
                        fallback: const SizedBox(),
                      ),
                    ),
                    CommunityLogo(
                      key: const Key('protected-root-original'),
                      data: original,
                    ),
                  ],
                ),
              ),
            );
            Future<void> open() async {
              unawaited(
                navigator.currentState!.push(
                  MaterialPageRoute<void>(builder: page),
                ),
              );
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              await t.pump();
            }

            await open();
            expect(
              find.byKey(const Key('root-directory-card')),
              findsOneWidget,
            );
            expect(
              t
                  .widget<CommunityLogo>(
                    find.descendant(
                      of: find.byKey(const Key('root-directory-card')),
                      matching: find.byType(CommunityLogo),
                    ),
                  )
                  .data,
              source,
              reason: 'The real directory image must still be present before maintenance.',
            );
            final logo = find.descendant(
              of: find.byKey(const Key('root-directory-card')),
              matching: find.byType(Image),
            );
            final portrait = find.descendant(
              of: find.byKey(const Key('protected-root-portrait')),
              matching: find.byType(Image),
            );
            final originalFinder = find.descendant(
              of: find.byKey(const Key('protected-root-original')),
              matching: find.byType(Image),
            );
            expect(logo, findsOneWidget);
            expect(portrait, findsOneWidget);
            final logoProvider = t.widget<Image>(logo).image;
            final portraitProvider = t.widget<Image>(portrait).image;
            final originalProvider = t.widget<Image>(originalFinder).image;
            final config = createLocalImageConfiguration(t.element(logo));
            final logoKey = await logoProvider.obtainKey(config);
            final portraitKey = await portraitProvider.obtainKey(config);
            final originalKey = await originalProvider.obtainKey(config);
            for (
              var i = 0;
              i < 60 &&
                  (!t.binding.imageCache.statusForKey(logoKey).keepAlive ||
                      !t.binding.imageCache
                          .statusForKey(portraitKey)
                          .keepAlive);
              i++
            ) {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await t.pump();
            }
            expect(
              t.binding.imageCache.statusForKey(logoKey).keepAlive,
              isTrue,
            );
            expect(t.binding.imageCache.statusForKey(portraitKey).live, isTrue);
            final reads = host.requests
                .where(
                  (request) =>
                      request.name == 'communities.read' &&
                      request.payload['view'] == 'discover',
                )
                .length;
            navigator.currentState!.pop();
            await t.pump();
            await t.pump(const Duration(milliseconds: 300));
            await open();
            expect(t.widget<Image>(logo).image, logoProvider);
            expect(t.widget<Image>(portrait).image, portraitProvider);
            expect(
              host.requests.where(
                (request) =>
                    request.name == 'communities.read' &&
                    request.payload['view'] == 'discover',
              ),
              hasLength(reads),
            );
            var complete = false;
            final clearing = app.imageMaintenance
                .clear()
                .then<Object>(
                  (value) => value,
                  onError: (Object error, StackTrace _) => error,
                )
                .whenComplete(() => complete = true);
            for (var i = 0; i < 20 && !complete; i++) {
              await t.pump(const Duration(milliseconds: 10));
            }
            expect(complete, isTrue);
            final outcome = await clearing;
            await t.pump();
            if (fails) {
              expect(
                outcome,
                isA<BridgeRemoteException>().having(
                  (e) => e.code,
                  'code',
                  'diagnostics.testFailure',
                ),
              );
              expect(app.imageMaintenance.result, 'failed');
            } else {
              expect(outcome, isA<int>());
              expect(app.imageMaintenance.result, 'cleared');
            }
            expect(host.purged, !fails);
            expect(app.communities.directory!.items.single.logo, isNull);
            expect(logo, findsNothing);
            expect(
              t.binding.imageCache.statusForKey(logoKey).keepAlive,
              isFalse,
              reason: 'The application root must retire the downloaded provider as well as its domain field.',
            );
            expect(t.binding.imageCache.statusForKey(portraitKey).live, isTrue);
            expect(t.widget<Image>(portrait).image, portraitProvider);
            expect(t.widget<Image>(originalFinder).image, originalProvider);
            expect(t.binding.imageCache.statusForKey(originalKey).live, isTrue);
            expect(
              host.requests.where(
                (request) =>
                    request.name == 'communities.read' &&
                    request.payload['view'] == 'discover',
              ),
              hasLength(reads),
            );
            expect(
              host.requests.where(
                (request) => request.name == 'diagnostics.clearImageCache',
              ),
              hasLength(1),
            );
            final fresh = app.communities.refresh(reuseFresh: true);
            await t.pump();
            await fresh;
            await t.pump();
            expect(app.communities.directory!.items.single.logo, source);
            if (retained) {
              expect(
                logo,
                findsNothing,
                reason: 'A fresh read elsewhere cannot renew the old details snapshot.',
              );
              navigator.currentState!.pop();
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
              shownSnapshot = app.communities.directory!.items.single;
              await open();
            }
            final nextKey = await t.widget<Image>(logo).image.obtainKey(config);
            expect(nextKey, isNot(logoKey));
            expect(t.widget<Image>(portrait).image, portraitProvider);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            if (!mountedRoot) {
              app.dispose();
            }
            await t.pump();
            await host.close();
            preferences.dispose();
            await t.pump();
          }
        },
        skip: missing,
      );
    }
  }
}
