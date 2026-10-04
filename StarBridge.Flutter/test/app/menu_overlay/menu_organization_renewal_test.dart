import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organizations_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_organization_previews.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_directory_logos.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/example_community_workspace.dart';

import 'menu_channel_media_session_test.dart' show PhotoPort;
import 'menu_chat_media_test.dart' show photo;
import '../../features/communities/community_chat_test.dart' show chatPage;
import 'menu_organization_body_stability_test.dart' show ready;

class RenewingPort extends PhotoPort {
  int renewal = 0;
  String? organization = 'f' * 32;
  String relationship = 'member';
  bool removeLogo = false, removeAvatar = false;
  String? chatError;
  Completer<void>? overviewGate;
  @override
  CommunityCard get card => CommunityCard(
    targetRef: (renewal == 0 ? 'a' : 'e') * 32,
    organizationRef: organization,
    relationship: relationship,
    name: 'Same authorized organization',
    logo: removeLogo ? null : photo,
    memberCount: 3,
  );
  @override
  Future<CommunityWorkspace> readWorkspace(
    String targetRef,
    String query,
    int offset,
  ) async {
    await overviewGate?.future;
    return exampleCommunityWorkspace(card, query, offset);
  }

  @override
  Future<CommunityChatPage> readChat(
    String targetRef, {
    int after = 0,
    int before = 0,
  }) async {
    if (chatError != null) throw CommunityFailure(chatError!);
    final raw = chatPage();
    return CommunityChatPage.parse({
      ...raw,
      'targetRef': targetRef,
      if (removeAvatar)
        'messages': [
          for (final m in raw['messages'] as List)
            <String, Object?>{
              ...Map<String, Object?>.from(m as Map),
              'hasAvatar': false,
            },
        ],
      if (after > 0) ...{
        'messages': [],
        'oldestSequence': 0,
        'hasOlder': false,
      },
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fresh target references for the same organization do not erase chrome or peer portraits', () async {
    final port = RenewingPort();
    final views = <MenuFeatureView>[];
    final session = MenuOrganizationsSession(
      port,
      (raw) => views.add(MenuFeatureView.parse(raw)),
    );
    addTearDown(session.dispose);
    addTearDown(() {
      if (port.overviewGate?.isCompleted == false) {
        port.overviewGate!.complete();
      }
      if (port.gate?.isCompleted == false) port.gate!.complete();
    });
    session.show(true);
    await ready(session, 'chat');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final before = MenuFeatureView.parse(session.currentView);
    expect(before.organization!.logo, isNotNull);
    expect(before.organization!.overview!.online, isNotNull);
    expect(before.rows.every((r) => r.avatar != null), isTrue);
    port.renewal++;
    port.overviewGate = Completer<void>();
    port.gate = Completer<void>();
    views.clear();
    await session.refresh(silent: true);
    expect(views, isNotEmpty);
    expect(
      views.every((v) => v.organization?.logo == before.organization!.logo),
      true,
      reason: 'Reference renewal is not logo removal',
    );
    expect(
      views.every(
        (v) =>
            v.organization?.overview?.online ==
            before.organization!.overview!.online,
      ),
      true,
      reason: 'Reference renewal is not unknown presence',
    );
    expect(
      views.every(
        (v) =>
            v.rows.length == before.rows.length &&
            v.rows.first.avatar == before.rows.first.avatar,
      ),
      true,
      reason: 'Same sender portrait must not blink while media revalidates',
    );
    port.overviewGate!.complete();
    port.gate!.complete();
  });

  test(
    'renewal never reuses another or unverified organization portrait',
    () async {
      final port = RenewingPort();
      final loaded = Completer<void>();
      final logos = MenuDirectoryLogos(port, (_, image) {
        if (image != null && !loaded.isCompleted) loaded.complete();
      });
      addTearDown(logos.dispose);
      addTearDown(port.close);
      await logos.read(port.card);
      await loaded.future;
      final image = await logos.read(port.card);
      port.renewal++;
      expect(await logos.read(port.card), image);
      port.organization = 'b' * 32;
      expect(await logos.read(port.card), isNull);
      port.organization = null;
      expect(await logos.read(port.card), isNull);
      port.organization = 'f' * 32;
      port.relationship = 'none';
      expect(await logos.read(port.card), isNull);
      port.relationship = 'member';
      port.removeLogo = true;
      expect(
        await logos.read(port.card),
        isNull,
        reason: 'Explicit removal must not retain old media',
      );
      logos.clear();
      port.removeLogo = false;
      expect(
        await logos.read(port.card),
        isNull,
        reason: 'Account reset clears display cache',
      );
    },
  );

  test(
    'summary survives renewal and transient failure but not denied access',
    () async {
      final port = RenewingPort();
      var changed = Completer<void>();
      final previews = MenuOrganizationPreviews(port, (_, _) {
        if (!changed.isCompleted) changed.complete();
      });
      addTearDown(previews.dispose);
      addTearDown(port.close);
      final old = port.card.targetRef;
      previews.refresh([old]);
      await changed.future;
      final summary = previews.value(old);
      port.renewal++;
      final target = port.card.targetRef;
      previews.rebind(old, target);
      expect(previews.value(target), summary);
      port.chatError = 'unavailable';
      changed = Completer<void>();
      previews.refresh([target]);
      await changed.future;
      expect(previews.value(target), summary);
      port.chatError = 'forbidden';
      changed = Completer<void>();
      previews.refresh([target]);
      await changed.future;
      expect(previews.value(target)['summary'], '暂时无法读取聊天摘要');
      expect(previews.value(target)['unread'], isNull);
    },
  );

  test(
    'authoritative avatar removal wins over retained and late photos',
    () async {
      final port = RenewingPort();
      final session = MenuOrganizationsSession(port, (_) {});
      addTearDown(session.dispose);
      session.show(true);
      await ready(session, 'chat');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        MenuFeatureView.parse(session.currentView).rows.first.avatar,
        isNotNull,
      );
      port.renewal++;
      port.removeAvatar = true;
      expect(
        (await port.readChat(port.card.targetRef)).messages.first.hasAvatar,
        false,
      );
      await session.refresh(silent: true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        MenuFeatureView.parse(session.currentView).rows.first.avatar,
        isNull,
      );
    },
  );
}
