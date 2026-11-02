import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';

import '../../features/communities/community_catalog_ship_image.dart';
import '../../features/communities/community_ship_banner.dart';
import '../../features/communities/community_fleet_statistics_dialog.dart';
import '../../features/communities/community_ship_row_surface.dart';
import '../../features/communities/community_announcement_card.dart';
import '../../features/communities/community_announcements_copy.dart';
import '../../features/direct_messages/communication_time_formatter.dart';
import '../localization/app_strings.dart';
import '../../shared/ships/catalog_vehicle_icon.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../../features/communities/community_ships_copy.dart';
import '../../shared/ships/ship_category_colors.dart';
import 'menu_bridge_style.dart';
import 'menu_feature_view.dart';
import 'menu_friends_view.dart' show menuPresenceColor;
import 'menu_organization_view.dart';
import 'menu_announcement_details_control.dart';
import 'menu_comms_panel.dart' show MenuInlineAvatar;
import 'menu_organization_directory.dart';
import 'menu_organization_header.dart';
import 'menu_organization_sidebar.dart';
import 'menu_organization_navigation.dart';
import 'menu_channel_panel.dart';
import 'menu_organization_members_board.dart';
import 'menu_loading.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

/// WPF-style collaboration hierarchy, with stacked fields at narrow widths.
/// This renderer has no service or authority references.
class MenuOrganizationsPanel extends StatefulWidget {
  const MenuOrganizationsPanel({
    super.key,
    required this.view,
    required this.onAction,
    this.onProfile,
    this.active = false,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  final ValueChanged<String>? onProfile;
  final bool active;
  @override
  State<MenuOrganizationsPanel> createState() => _MenuOrganizationsPanelState();
}

class _MenuOrganizationsPanelState extends State<MenuOrganizationsPanel> {
  final _query = TextEditingController();
  bool _showOrganizations = false;
  bool _statisticsDismissed = false;
  @override
  void initState() {
    super.initState();
    _query.text = widget.view.organization?.query ?? '';
  }

  @override
  void didUpdateWidget(MenuOrganizationsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.scope != widget.view.scope ||
        (oldWidget.view.organization != null &&
            widget.view.organization != null &&
            oldWidget.view.organization?.tab !=
                widget.view.organization?.tab)) {
      _statisticsDismissed = false;
      _query.text = widget.view.organization?.query ?? '';
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _action(MenuFeatureButton action, {bool selected = false}) =>
      StarBridgeActionButton(
        kind: selected
            ? StarBridgeActionKind.primary
            : StarBridgeActionKind.secondary,
        nativeStyle: selected
            ? const FilledButton.tonal(
                    onPressed: null,
                    child: SizedBox.shrink(),
                  )
                  .defaultStyleOf(context)
                  .merge(FilledButtonTheme.of(context).style)
            : null,
        onActivate: widget.view.busy
            ? null
            : (_) {
                if (action.role == 'fleetStatistics') {
                  setState(() => _statisticsDismissed = false);
                }
                widget.onAction(action.key, '');
              },
        child: Text(action.label),
      );

  Widget _organizationToggle() {
    final style = TextButton.icon(
      onPressed: null,
      icon: const SizedBox.shrink(),
      label: const SizedBox.shrink(),
    ).defaultStyleOf(context).merge(TextButtonTheme.of(context).style);
    final fontSize = style.textStyle?.resolve({})?.fontSize ?? 14;
    final scale =
        (MediaQuery.textScalerOf(context).scale(fontSize) / 14)
            .clamp(1.0, 2.0)
            .toDouble() -
        1;
    final icon = StandardIcon(
      _showOrganizations
          ? StandardIconSemantic.arrowForward
          : StandardIconSemantic.arrowBack,
    );
    final label = Flexible(
      child: Text(
        _showOrganizations
            ? menuText(context, 'menu.overlay.organizations.backCurrent')
            : menuText(context, 'menu.overlay.organizations.list'),
      ),
    );
    return StarBridgeActionButton(
      kind: StarBridgeActionKind.quiet,
      nativeStyle: style,
      onActivate: (_) =>
          setState(() => _showOrganizations = !_showOrganizations),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8 - 4 * scale,
        children: style.iconAlignment == IconAlignment.end
            ? [label, icon]
            : [icon, label],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view, org = view.organization;
    if (org == null) {
      return MenuFeaturePanel(view: view, onAction: widget.onAction);
    }
    if (org.tab == 'directory') {
      return MenuOrganizationDirectory(view: view, onAction: widget.onAction);
    }
    final search = view.buttons
        .where((a) => a.role == 'searchMembers' || a.role == 'searchShips')
        .firstOrNull;
    final footer = view.buttons.where(
      (a) => const {'firstPage', 'nextPage', 'olderMessages'}.contains(a.role),
    );
    final form = view.buttons.where((a) => a.input != null && a != search);
    final statistics = view.buttons
        .where((a) => a.role == 'fleetStatistics')
        .firstOrNull;
    final indices = List<int>.generate(view.rows.length, (i) => i);
    final layout = LayoutBuilder(
      builder: (context, constraints) {
        final normalText = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        final showSidebar =
            org.navigation.isNotEmpty &&
            constraints.maxWidth >= 860 &&
            normalText;
        final sidebarWidth = constraints.maxWidth >= 1100 ? 260.0 : 220.0;
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (view.notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  view.notice,
                  style: const TextStyle(color: BridgeInk.amber),
                ),
              ),
            if (view.busy) ...[
              if (!view.refreshing && !org.bodyLoading)
                MenuLoading(
                  label: menuText(context, 'menu.overlay.window.working'),
                ),
              BridgeCaption(menuText(context, 'menu.display.busy')),
            ],
            if (search != null) ...[
              Row(
                children: [
                  Expanded(
                    child: StarBridgeFieldFrame(
                      enabled: !view.busy,
                      builder: (context, focus) => TextField(
                        controller: _query,
                        focusNode: focus,
                        enabled: !view.busy,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(search.limit),
                        ],
                        decoration: InputDecoration(
                          hintText: search.input,
                          isDense: true,
                        ),
                        onSubmitted: view.busy
                            ? null
                            : (value) => runStarBridgeSynchronousActivation(
                                InteractionSource.keyboard,
                                () => widget.onAction(search.key, value),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StarBridgeActionButton(
                    onActivate: view.busy
                        ? null
                        : (_) => widget.onAction(search.key, _query.text),
                    child: Text(
                      menuText(context, 'menu.overlay.organizations.search'),
                    ),
                  ),
                  if (org.tab == 'ships' && statistics != null) ...[
                    const SizedBox(width: 8),
                    _action(statistics),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 10),
            ],
            if (org.tab == 'ships')
              const CommunityShipColumnHeader(showImportedAt: false),
            if (indices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  org.query.isNotEmpty
                      ? menuText(
                          context,
                          'menu.overlay.organizations.noSearchResults',
                        )
                      : switch (org.tab) {
                          'directory' => menuText(
                            context,
                            'menu.overlay.organizations.empty',
                          ),
                          'ships' => menuText(
                            context,
                            'menu.overlay.organizations.noShips',
                          ),
                          'announcements' => menuText(
                            context,
                            'menu.overlay.organizations.noAnnouncements',
                          ),
                          'chat' => menuText(
                            context,
                            'menu.overlay.organizations.noMessages',
                          ),
                          _ => menuText(
                            context,
                            'menu.overlay.organizations.noMembers',
                          ),
                        },
                ),
              ),
            for (final i in indices) _row(view.rows[i], org.rows[i], org.tab),
            if (org.tab == 'members' || org.tab == 'ships')
              BridgeCaption(
                org.matched == 0
                    ? menuText(
                        context,
                        'menu.overlay.organizations.zeroResults',
                      )
                    : '${org.offset + 1}–${org.offset + view.rows.length} / ${org.matched}',
              ),
            Wrap(children: [for (final action in footer) _action(action)]),
            for (final action in form)
              MenuFeatureAction(
                key: ValueKey('${view.scope}/${action.role ?? action.label}'),
                identity: view.scope,
                action: action,
                enabled: !view.busy,
                onAction: widget.onAction,
              ),
          ],
        );
        final Widget content = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: MenuOrganizationHeader(
                view: view,
                onAction: widget.onAction,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MenuOrganizationNavigation(
                view: view,
                onAction: widget.onAction,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: BridgeInk.divider),
            ),
            if (org.tab != 'members' && view.refreshing && !org.bodyLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MenuLoading(feedback: view.readFeedback),
              ),
            Expanded(
              child: org.tab == 'members'
                  ? SingleChildScrollView(
                      key: const ValueKey('menu-org-body-members'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: MenuOrganizationMembersBoard(
                          key: ValueKey('${view.scope}/${org.identity}'),
                          view: view,
                          searchController: _query,
                          onAction: widget.onAction,
                          onProfile: widget.onProfile,
                        ),
                      ),
                    )
                  : org.bodyLoading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: MenuLoading(feedback: view.readFeedback),
                            ),
                            BridgeCaption(
                              menuText(
                                context,
                                'menu.overlay.window.readingEllipsis',
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : org.bodyError
                  ? Center(
                      child: StarBridgeActionButton(
                        kind: StarBridgeActionKind.quiet,
                        onActivate: (_) => widget.onAction('refresh', ''),
                        child: Text(
                          menuText(
                            context,
                            'menu.overlay.organizations.retryRead',
                          ),
                        ),
                      ),
                    )
                  : org.tab == 'chat' && view.chat != null
                  ? MenuChannelPanel(
                      view: view,
                      embeddedOrganization: true,
                      onAction: widget.onAction,
                      active: widget.active,
                      onProfile: widget.onProfile,
                    )
                  : SingleChildScrollView(
                      key: ValueKey('menu-org-body-${org.tab}'),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: body,
                      ),
                    ),
            ),
          ],
        );
        if (org.navigation.isEmpty) return content;
        final sidebar = MenuOrganizationSidebar(
          items: org.navigation,
          busy:
              view.busy ||
              view.refreshing ||
              org.sections.values.every((key) => key == null),
          onSelect: (key) {
            setState(() => _showOrganizations = false);
            widget.onAction(key, '');
          },
        );
        if (showSidebar) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: sidebarWidth, child: sidebar),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          );
        }
        return Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _organizationToggle(),
            ),
            Expanded(child: _showOrganizations ? sidebar : content),
          ],
        );
      },
    );
    if (_statisticsDismissed ||
        org.fleetStatistics == null ||
        statistics == null ||
        org.tab != 'ships') {
      return layout;
    }
    void closeStatistics() {
      setState(() => _statisticsDismissed = true);
      final close = view.buttons
          .where((b) => b.role == 'closeStatistics')
          .firstOrNull;
      if (close != null) widget.onAction(close.key, '');
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): closeStatistics,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            layout,
            const Positioned.fill(
              child: ModalBarrier(dismissible: false, color: Colors.black54),
            ),
            Positioned.fill(
              child: CommunityFleetStatisticsDialog(
                statistics: org.fleetStatistics!,
                onClose: closeStatistics,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(MenuFeatureRow row, MenuOrganizationRow data, String tab) {
    Widget name() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${row.title}${data.isSelf ? menuText(context, 'menu.overlay.organizations.youSuffix') : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (data.handle.isNotEmpty && data.handle != row.title)
          BridgeCaption(
            data.handle.startsWith('@') ? data.handle : '@${data.handle}',
            color: MenuBridgeColors.of(context).blue,
          ),
      ],
    );
    Widget identity() => name();
    Widget status() => Text(
      organizationPresenceText(data.presence, context),
      style: TextStyle(color: menuPresenceColor(data.presence)),
    );
    if (tab == 'announcements') {
      final date = DateTime.tryParse(data.announcementTime);
      final colors = context.tokens.colors;
      return CommunityAnnouncementCard(
        title: row.title,
        content: row.detail.isEmpty
            ? communityAnnouncementText(context, 'emptyBody')
            : row.detail,
        maxLines: data.currentAnnouncement ? 4 : 2,
        metadata: Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            if (const {
              'published',
              'archived',
              'withdrawn',
            }.contains(data.announcementState))
              Text(
                communityAnnouncementText(context, data.announcementState),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: data.announcementState == 'published'
                      ? colors.success
                      : data.announcementState == 'withdrawn'
                      ? colors.warning
                      : colors.textSecondary,
                ),
              ),
            if (date != null)
              Text(
                communicationTime(date, AppStrings.of(context).locale),
                style: TextStyle(color: colors.textSecondary),
              ),
          ],
        ),
        actions: data.announcement == null
            ? const SizedBox.shrink()
            : MenuAnnouncementDetailsControl(
                key: ValueKey('${widget.view.scope}/${data.announcement!.key}'),
                view: data.announcement!,
                active: widget.active,
                action: row.buttons.firstOrNull?.key,
                enabled: !widget.view.busy,
                dispatch: widget.onAction,
              ),
      );
    }
    if (tab == 'ships') {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CommunityShipRowSurface(
          child: CommunityShipBanner(
            showImportedAt: false,
            identity: Row(
              children: [
                SizedBox(
                  width: 76,
                  height: 48,
                  child: CommunityCatalogShipImage(
                    asset: data.image,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      name(),
                      if (row.detail.isNotEmpty) BridgeCaption(row.detail),
                    ],
                  ),
                ),
              ],
            ),
            spec: ShipClassificationTag(
              label: communityShipDisplayText(context, data.spec),
              color: shipSizeColor(context, data.spec),
            ),
            role: ShipClassificationTag(
              label: communityShipDisplayText(context, data.role),
              color: shipCategoryColor(context, data.role),
            ),
            vehicleIcon: CatalogVehicleIcon.supportsKey(data.iconKey)
                ? CatalogVehicleIcon.byKey(iconKey: data.iconKey)
                : const SizedBox.square(dimension: 28),
            status: Text(communityShipDisplayText(context, data.status)),
            price: Text(
              data.price,
              style: TextStyle(color: context.tokens.colors.info),
            ),
            owner: Row(
              children: [
                MenuInlineAvatar(source: data.avatar, name: data.owner),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StarBridgeTooltip(
                        message: data.owner,
                        child: Text(
                          data.owner,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      status(),
                    ],
                  ),
                ),
              ],
            ),
            importedAt: const SizedBox.shrink(),
            action: const SizedBox.shrink(),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.tokens.surfaces.panel.fill,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: data.isSelf
              ? context.tokens.colors.info
              : context.tokens.surfaces.panel.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          identity(),
          if (row.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(row.detail),
            ),
          for (final action in row.buttons)
            MenuFeatureAction(
              key: ValueKey(
                '${widget.view.scope}/${row.title}/${action.role ?? action.label}',
              ),
              identity: (widget.view.scope, data.profileKey),
              action: action,
              enabled: !widget.view.busy,
              onAction: widget.onAction,
            ),
        ],
      ),
    );
  }
}
