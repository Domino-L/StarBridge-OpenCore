import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

import '../communities/community_visitor_profile_test.dart'
    show VisitorPort, visitorPayload;
import '../friends/social_layout_test.dart' show app;

void main() {
  testWidgets('a pending background cannot return after account invalidation', (
    tester,
  ) async {
    final p = _WallpaperVisitorPort();
    final bundle = _HeldWallpaperBundle();
    addTearDown(p.changes.close);
    await tester.pumpWidget(
      app(
        DefaultAssetBundle(
          bundle: bundle,
          child: UserProfilePage(
            port: p,
            target: const UserTarget.community(
              'synthetic-community-ref',
              'synthetic-member-ref',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(bundle.reads, 1);
    p.changes.add(null);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      bundle.pending.complete(_wallpaperFixture());
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-wallpaper-image')), findsNothing);
    expect(find.text('Visitor Pilot'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'manual profile refresh retries a failed wallpaper even when metadata completes in the same frame',
    (tester) async {
      final p = _WallpaperVisitorPort();
      final bundle = _RetryWallpaperBundle();
      addTearDown(p.changes.close);
      await tester.pumpWidget(
        app(
          DefaultAssetBundle(
            bundle: bundle,
            child: UserProfilePage(
              port: p,
              target: const UserTarget.community(
                'synthetic-community-ref',
                'synthetic-member-ref',
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(seconds: 1));
        if (bundle.reads == 3 &&
            find
                .byKey(const Key('profile-wallpaper-failed'))
                .evaluate()
                .isNotEmpty) {
          break;
        }
      }
      expect(bundle.reads, 3);
      expect(find.byKey(const Key('profile-wallpaper-failed')), findsOneWidget);
      bundle.fail = false;
      await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (find.byType(RawImage).evaluate().isNotEmpty &&
            tester.widget<RawImage>(find.byType(RawImage)).image != null) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(p.reads, 2);
      expect(bundle.reads, greaterThan(3));
      expect(find.byKey(const Key('profile-wallpaper-failed')), findsNothing);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      final imageReads = bundle.reads;
      await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
      await tester.pumpAndSettle();
      expect(
        bundle.reads,
        imageReads,
        reason: 'Successful cached images need not be reread.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'profile opened before its data and wallpaper finish loading fills both without refresh',
    (tester) async {
      final p = VisitorPort()..pending = Completer<PersonalProfileSnapshot>();
      final bundle = _HeldWallpaperBundle();
      addTearDown(p.changes.close);
      await tester.pumpWidget(
        app(
          DefaultAssetBundle(
            bundle: bundle,
            child: UserProfilePage(
              port: p,
              target: const UserTarget.community(
                'synthetic-community-ref',
                'synthetic-member-ref',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Visitor Pilot'), findsNothing);
      expect(find.byKey(const Key('profile-wallpaper-image')), findsNothing);
      p.pending!.complete(
        parsePersonalProfileSnapshot({
          ...visitorPayload,
          'profile': {
            ...visitorPayload['profile']! as Map<String, Object?>,
            'wallpaperId': 'formation-flight',
          },
        }),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Visitor Pilot'), findsWidgets);
      expect(find.text('Authorized shared introduction'), findsOneWidget);
      expect(find.byKey(const Key('profile-wallpaper-image')), findsOneWidget);
      expect(bundle.reads, 1);
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNull);
      await tester.runAsync(() async {
        bundle.pending.complete(_wallpaperFixture());
      });
      for (var i = 0; i < 40; i++) {
        if (tester.widget<RawImage>(find.byType(RawImage)).image != null) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(
        p.reads,
        1,
        reason: 'Recovery must not require a profile refresh.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

const _wallpaperPath = 'assets/profile-wallpapers/formation-flight.jpg';

// Synthetic one-pixel PNG: loading tests must not require optional artwork.
ByteData _wallpaperFixture() => ByteData.sublistView(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  ),
);

class _HeldWallpaperBundle extends CachingAssetBundle {
  final pending = Completer<ByteData>();
  int reads = 0;
  @override
  Future<ByteData> load(String key) {
    if (key == _wallpaperPath) {
      reads++;
      return pending.future;
    }
    return rootBundle.load(key);
  }
}

class _WallpaperVisitorPort extends VisitorPort {
  @override
  Future<PersonalProfileSnapshot> readMemberPersonalProfile(
    String targetRef,
    String memberRef,
  ) async {
    reads++;
    return parsePersonalProfileSnapshot({
      ...visitorPayload,
      'profile': {
        ...visitorPayload['profile']! as Map<String, Object?>,
        'wallpaperId': 'formation-flight',
      },
    });
  }
}

class _RetryWallpaperBundle extends CachingAssetBundle {
  bool fail = true;
  int reads = 0;
  @override
  Future<ByteData> load(String key) {
    if (key == _wallpaperPath) {
      reads++;
      if (fail) throw StateError('Synthetic asset read failure');
      return Future.value(_wallpaperFixture());
    }
    return rootBundle.load(key);
  }
}
