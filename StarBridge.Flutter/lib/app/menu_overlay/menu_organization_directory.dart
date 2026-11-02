import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/communities/community_logo.dart';
import '../../features/communities/community_gameplay_tags.dart';
import '../../features/communities/community_directory_card.dart'
    show communityLanguageLabel;
import 'menu_feature_view.dart';

/// Joined-organization chooser using the client's card, logo and tag language.
/// Only display data and expiring action keys are accepted here.
class MenuOrganizationDirectory extends StatefulWidget {
  const MenuOrganizationDirectory({
    super.key,
    required this.view,
    required this.onAction,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  @override
  State<MenuOrganizationDirectory> createState() =>
      _MenuOrganizationDirectoryState();
}

class _MenuOrganizationDirectoryState extends State<MenuOrganizationDirectory> {
  late final _query = TextEditingController(
    text: widget.view.organization!.query,
  );
  @override
  void didUpdateWidget(MenuOrganizationDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.scope != widget.view.scope) {
      _query.text = widget.view.organization!.query;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view, org = view.organization!, tokens = context.tokens;
    final colors = tokens.colors, text = Theme.of(context).textTheme;
    final search = view.buttons
        .where((a) => a.role == 'searchOrganizations')
        .firstOrNull;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    menuText(context, 'menu.overlay.organizations.mine'),
                    style: text.titleLarge,
                  ),
                ),
                StarBridgeActionButton(
                  controlKey: const ValueKey('menu-organization-refresh'),
                  onActivate: view.busy
                      ? null
                      : (_) => widget.onAction('refresh', ''),
                  child: Text(menuText(context, 'friends.refresh')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              menuText(context, 'menu.overlay.organizations.select'),
              style: text.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (search != null)
              Row(
                children: [
                  Expanded(
                    child: StarBridgeFieldFrame(
                      enabled: !view.busy,
                      builder: (context, focus) => TextField(
                        focusNode: focus,
                        controller: _query,
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
                    controlKey: const ValueKey(
                      'menu-organization-submit-search',
                    ),
                    onActivate: view.busy
                        ? null
                        : (_) => widget.onAction(search.key, _query.text),
                    child: Text(
                      menuText(context, 'menu.overlay.organizations.search'),
                    ),
                  ),
                ],
              ),
            if (view.notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  view.notice,
                  style: TextStyle(color: colors.warning),
                ),
              ),
            const SizedBox(height: 16),
            if (view.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  org.query.isEmpty
                      ? menuText(context, 'menu.overlay.organizations.empty')
                      : menuText(
                          context,
                          'menu.overlay.organizations.noResults',
                        ),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.maxWidth >= 760 &&
                        MediaQuery.textScalerOf(context).scale(1) < 1.5
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < view.rows.length; i++)
                      SizedBox(width: width, child: _card(context, i)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final action in view.buttons.where(
                  (a) => a.role != 'searchOrganizations',
                ))
                  StarBridgeActionButton(
                    controlKey: ValueKey(
                      'menu-organization-action-${action.key}',
                    ),
                    onActivate: view.busy
                        ? null
                        : (_) => widget.onAction(action.key, ''),
                    child: Text(action.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, int index) {
    final view = widget.view,
        row = view.rows[index],
        data = view.organization!.rows[index];
    final tokens = context.tokens, text = Theme.of(context).textTheme;
    final open = row.buttons
        .where((a) => a.role == 'openOrganization')
        .firstOrNull;
    void Function()? onOpen = view.busy || open == null
        ? null
        : () => widget.onAction(open.key, '');
    final relation = switch (data.relationship) {
      'owner' => menuText(context, 'menu.overlay.organizations.owner'),
      'member' => menuText(context, 'menu.overlay.organizations.joined'),
      _ => menuText(context, 'menu.overlay.organizations.member'),
    };
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommunityLogo(
          data: data.logo,
          size: 48,
          framed: false,
          downloadedBy: data,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                relation,
                style: text.bodySmall?.copyWith(
                  color: data.relationship == 'owner'
                      ? tokens.colors.warning
                      : tokens.colors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Material(
      color: tokens.surfaces.panel.fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: tokens.surfaces.panel.border),
      ),
      child: StarBridgeActionRow(
        controlKey: ValueKey('menu-organization-choice-$index'),
        baseRadius: 8,
        semanticLabel: row.title,
        onActivate: onOpen == null ? null : (_, _) => onOpen(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: 14),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  Text(
                    menuText(
                      context,
                      'menu.overlay.organizations.memberCount',
                      {'count': data.memberCount ?? '—'},
                    ),
                    style: text.titleMedium?.copyWith(
                      color: tokens.colors.info,
                    ),
                  ),
                  if (data.language.isNotEmpty)
                    Text(
                      communityLanguageLabel(context, data.language),
                      style: text.bodySmall,
                    ),
                ],
              ),
              if (data.activeTime.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    menuText(context, 'menu.overlay.organizations.activeTime', {
                      'time': data.activeTime,
                    }),
                    style: text.bodySmall?.copyWith(
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                ),
              if (data.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: CommunityGameplayTags(value: data.tags),
                ),
              if (row.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    row.detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: tokens.colors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: StarBridgeActionButton(
                  controlKey: ValueKey('menu-organization-enter-$index'),
                  kind: StarBridgeActionKind.primary,
                  onActivate: onOpen == null ? null : (_) => onOpen(),
                  child: Text(
                    menuText(context, 'menu.overlay.organizations.open'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
