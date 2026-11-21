import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../design_system/theme/classic_font_scope.dart';
import '../../features/communities/bridge_communities.dart';
import '../../features/communities/communities_module.dart';
import '../../features/communities/communities_page.dart';
import '../../features/communities/community_shortcuts.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../shared/remote_image_loader.dart';
import 'menu_page_relay.dart';
import 'menu_relay_page_owner.dart';

/// The client's organizations (communities and the main fleet as one of them),
/// on the relayed session. Renames and overlay focus stay with the client's own
/// module; admission privacy and logo picking are done in the client.
final class MenuCommunitiesContent implements MenuRelayPageContent {
  MenuCommunitiesContent(
    BridgeClientSession session,
    MenuCommunitiesOwner owner,
  ) : module = CommunitiesModule(
        BridgeCommunities(
          session,
          connectionMode: owner.relay.hostMode,
          ownAvatar: () => owner.relay.ownProfile?.avatarImageData,
          scmOnly: () => owner.relay.scmOnly,
        ),
      ) {
    _scmOnly = owner.relay.scmOnly;
    _relay = owner.relay..addListener(_relayChanged);
    unawaited(module.prefetch());
  }

  final CommunitiesModule module;
  late final MenuPageRelay _relay;
  late bool _scmOnly;

  /// Disband and invitation delivery follow SCM-only, which can be confirmed
  /// after the page is shown.
  void _relayChanged() {
    if (_relay.scmOnly == _scmOnly) return;
    _scmOnly = _relay.scmOnly;
    module.entriesChanged();
  }

  @override
  void refresh() => unawaited(module.refresh(silent: true));

  /// The module follows `account.changed` itself; the owner's navigator change
  /// closes the old account's dialogs.
  @override
  void contextChanged() {}

  @override
  void dispose() {
    _relay.removeListener(_relayChanged);
    module.dispose();
  }
}

final class MenuCommunitiesOwner
    extends MenuRelayPageOwner<MenuCommunitiesContent> {
  MenuCommunitiesOwner(super.relay);

  @override
  String get clientPage => 'openCommunitiesPage';

  @override
  bool asksClientOnly(String name) =>
      name.startsWith('communities.') ||
      name.startsWith('overlay.') ||
      name == 'account.refreshRsiData' ||
      name.startsWith('officialFleet.governance.');

  @override
  MenuCommunitiesContent create(
    BridgeClientSession session,
    RemoteImageLoader images,
  ) => MenuCommunitiesContent(session, this);
}

/// The client's left organization list beside its page. Names show from 1400
/// wide (10-30 layout), icons only below that.
class MenuCommunitiesPage extends StatelessWidget {
  const MenuCommunitiesPage({super.key, required this.owner});
  final MenuCommunitiesOwner owner;

  @override
  Widget build(BuildContext context) => MenuRelayPage<MenuCommunitiesContent>(
    owner: owner,
    unavailableKey: 'menu.overlay.window.communitiesUnavailable',
    build: (context, content) => ClassicFontScope(
      child: LayoutBuilder(
        builder: (context, box) {
          final iconOnly = box.maxWidth < 1400;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: iconOnly ? 72 : 260,
                child: CommunityShortcuts(
                  module: content.module,
                  iconOnly: iconOnly,
                  selected: true,
                  activate: () async => true,
                ),
              ),
              Expanded(
                child: CommunitiesPage(
                  createPort: () => content.module.port,
                  module: content.module,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
