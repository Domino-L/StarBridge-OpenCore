import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import 'menu_comms_view.dart';
import 'menu_comms_directory.dart';
import 'menu_comms_history.dart';
import 'menu_feature_view.dart';
import 'menu_channel_panel.dart';
import 'menu_loading.dart';
export 'menu_inline_avatar.dart';

/// Familiar client master/detail layout within a free-floating menu window.
class MenuCommsPanel extends StatefulWidget {
  const MenuCommsPanel({
    super.key,
    required this.view,
    required this.onClose,
    required this.onAction,
    this.onProfile,
    this.onOrganizationProfile,
    this.embedded = false,
    this.onCompose,
    this.disconnected = false,
    this.active = false,
    this.organization,
    this.organizationSelected = false,
    this.onOrganizationAction,
    this.onConversationKind,
  });
  final MenuCommsView view;
  final VoidCallback onClose;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  final ValueChanged<String>? onOrganizationProfile;
  final bool embedded, disconnected, active;
  final MenuFeatureView? organization;
  final bool organizationSelected;
  final void Function(String, String)? onOrganizationAction;
  final ValueChanged<String>? onConversationKind;
  final void Function(String, String, String, int)? onCompose;
  @override
  State<MenuCommsPanel> createState() => _MenuCommsPanelState();
}

class _MenuCommsPanelState extends State<MenuCommsPanel> {
  String _query = '', _group = 'all';
  int _searchRevision = 0;
  MenuFeatureView? _organizationDirectory;
  @override
  void didUpdateWidget(MenuCommsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.view.state == 'idle' ||
        widget.view.state == 'restricted' ||
        (widget.view.profileKey != null &&
            widget.view.profileKey != oldWidget.view.profileKey)) {
      _query = '';
      _group = 'all';
      _searchRevision++;
    }
    // A loading view can retain only its own presentation context. Private
    // chat access is independent and is not organization authorization.
    if (oldWidget.organization?.scope != widget.organization?.scope ||
        widget.organization == null) {
      _organizationDirectory = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final view = widget.view;
      final organization = widget.organization;
      if (organization?.state == 'ready') _organizationDirectory = organization;
      if (organization?.state == 'unavailable' ||
          organization?.state == 'idle') {
        _organizationDirectory = null;
      }
      final directoryOrganization = organization?.state == 'loading'
          ? MenuFeatureView(
              'loading',
              scope: organization!.scope,
              busy: true,
              channels: _organizationDirectory?.channels ?? const [],
            )
          : organization;
      final wide =
          constraints.maxWidth >= 660 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      final compact =
          !constraints.hasBoundedHeight ||
          constraints.maxHeight < 470 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.5;
      Widget directory() => MenuCommsDirectory(
        view: view,
        query: _query,
        group: _group,
        searchRevision: _searchRevision,
        onQuery: (value) => setState(() => _query = value),
        onGroup: (value) => setState(() => _group = value),
        onAction: (action, key) {
          if (action == 'select') widget.onConversationKind?.call('private');
          widget.onAction(action, key);
        },
        onProfile: widget.onProfile,
        organization: directoryOrganization,
        organizationSelected: widget.organizationSelected,
        onOrganizationAction: (key, value) {
          if (key != 'refresh') {
            widget.onConversationKind?.call('organizationChat');
          }
          widget.onOrganizationAction?.call(key, value);
        },
      );
      Widget history() => MenuCommsHistory(
        view: view,
        active: widget.active && !widget.organizationSelected,
        onAction: widget.onAction,
        onProfile: widget.onProfile,
        onCompose: widget.onCompose,
        disconnected: widget.disconnected,
      );
      Widget content;
      if (view.state != 'ready') {
        content = SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (view.state == 'idle' || view.state == 'loading')
                  MenuLoading(feedback: view.readFeedback),
                Text(switch (view.state) {
                  'idle' ||
                  'loading' => menuText(context, 'menu.overlay.comms.loading'),
                  'restricted' => menuText(
                    context,
                    'menu.overlay.comms.restricted',
                  ),
                  _ => menuText(context, 'menu.overlay.comms.unavailable'),
                }),
                if (view.state != 'idle' && view.state != 'loading') ...[
                  const SizedBox(height: 12),
                  StarBridgeActionButton(
                    controlKey: const ValueKey('menu-comms-retry'),
                    semanticLabel: menuText(context, 'menu.display.reload'),
                    onActivate: (_) => widget.onAction('retry', ''),
                    child: Text(menuText(context, 'menu.display.reload')),
                  ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    controlKey: const ValueKey('menu-comms-back'),
                    semanticLabel: menuText(context, 'menu.overlay.comms.back'),
                    onActivate: (_) => widget.onAction('back', ''),
                    child: Text(menuText(context, 'menu.overlay.comms.back')),
                  ),
                ],
              ],
            ),
          ),
        );
      } else if (view.invitation case final invitation?) {
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: StarBridgeActionButton(
                semanticLabel: menuText(
                  context,
                  'menu.overlay.comms.backComms',
                ),
                onActivate: invitation.busy
                    ? null
                    : (_) => widget.onAction('inviteClose', ''),
                child: Text(menuText(context, 'menu.overlay.comms.backComms')),
              ),
            ),
            Expanded(
              child: MenuFeaturePanel(
                view: invitation,
                actionsAfterRows: true,
                onAction: (key, _) => widget.onAction('inviteAction', key),
              ),
            ),
          ],
        );
      } else {
        content = history();
      }
      final detail = IndexedStack(
        index: widget.organizationSelected ? 1 : 0,
        children: [
          TickerMode(enabled: !widget.organizationSelected, child: content),
          TickerMode(
            enabled: widget.organizationSelected,
            child: MenuChannelPanel(
              view: widget.organization ?? const MenuFeatureView('loading'),
              active: widget.active && widget.organizationSelected,
              directoryAsPlaceholder: true,
              onProfile: widget.onOrganizationProfile,
              onAction: (key, value) =>
                  widget.onOrganizationAction?.call(key, value),
            ),
          ),
        ],
      );
      if (wide) {
        content = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth >= 850 ? 270 : 230,
              child: directory(),
            ),
            VerticalDivider(
              width: 20,
              color: context.tokens.surfaces.panel.border,
            ),
            Expanded(child: detail),
          ],
        );
      } else {
        content =
            view.state == 'ready' &&
                view.name == null &&
                !widget.organizationSelected &&
                view.invitation == null
            ? directory()
            : Column(
                children: [
                  if (widget.organizationSelected)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: StarBridgeActionButton(
                        kind: StarBridgeActionKind.quiet,
                        semanticLabel: menuText(
                          context,
                          'menu.overlay.comms.back',
                        ),
                        onActivate: (_) {
                          widget.onConversationKind?.call('private');
                          widget.onAction('back', '');
                        },
                        child: Text(
                          menuText(context, 'menu.overlay.comms.back'),
                        ),
                      ),
                    ),
                  Expanded(child: detail),
                ],
              );
      }
      // A tiny window scrolls as a whole; ordinary windows keep the composer fixed.
      if (compact) {
        content = SingleChildScrollView(
          key: const ValueKey('menu-scroll-comms'),
          child: SizedBox(
            height: MediaQuery.textScalerOf(context).scale(720),
            child: content,
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (!widget.embedded)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      menuText(context, 'menu.tools.comms'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  StarBridgeActionButton(
                    kind: StarBridgeActionKind.quiet,
                    semanticLabel: menuText(context, 'window.close'),
                    onActivate: (_) => widget.onClose(),
                    child: Text(menuText(context, 'window.close')),
                  ),
                ],
              ),
            if (view.inviteAvailable &&
                view.invitation == null &&
                !widget.organizationSelected)
              Align(
                alignment: Alignment.centerRight,
                child: StarBridgeActionButton(
                  kind: StarBridgeActionKind.quiet,
                  semanticLabel: menuText(
                    context,
                    'menu.overlay.comms.inviteHistory',
                  ),
                  onActivate: view.busy
                      ? null
                      : (_) => widget.onAction('inviteRecords', ''),
                  child: Text(
                    menuText(context, 'menu.overlay.comms.inviteHistory'),
                  ),
                ),
              ),
            Expanded(child: content),
          ],
        ),
      );
    },
  );
}
