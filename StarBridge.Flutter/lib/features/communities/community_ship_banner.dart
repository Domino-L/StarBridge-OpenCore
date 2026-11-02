import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../shared/ships/ship_catalog_display.dart';
import '../../shared/ships/ship_category_colors.dart';
import '../../shared/ships/ship_classification_tag.dart';
import '../common/organization_ship_owner.dart';
import 'community_catalog_ship_image.dart';
import 'community_image_decoder.dart';
import 'community_ship_loaners.dart';
import 'community_ship_owner_avatar.dart';
import 'community_ship_row_surface.dart';
import 'community_ship_vehicle_icon.dart';
import 'community_ships_port.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'community_ships_copy.dart';

/// WPF-style horizontal inventory entry; only compact windows wrap metadata.
class CommunityShipBanner extends StatelessWidget {
  const CommunityShipBanner({
    required this.identity,
    required this.spec,
    required this.status,
    required this.price,
    required this.role,
    required this.vehicleIcon,
    required this.owner,
    required this.importedAt,
    this.action,
    this.showImportedAt = true,
    this.hero,
    super.key,
  });
  final Widget identity,
      spec,
      status,
      price,
      role,
      vehicleIcon,
      owner,
      importedAt;

  /// Null when the whole row is the action.
  final Widget? action;
  final bool showImportedAt;

  /// Card mode: the ship image above, then every field in the labelled
  /// compact layout, so a card shows exactly what a row shows.
  final Widget? hero;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final classification = Row(
        key: const ValueKey('community-ship-classification'),
        mainAxisSize: MainAxisSize.min,
        children: [
          vehicleIcon,
          const SizedBox(width: 8),
          Flexible(child: spec),
          const SizedBox(width: 8),
          Flexible(child: role),
        ],
      );
      final cells = [
        identity,
        classification,
        status,
        price,
        owner,
        if (showImportedAt) importedAt,
      ];
      if (hero == null && constraints.maxWidth >= 900) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: CommunityShipColumns(
            cells: [...cells, ?action],
            showImportedAt: showImportedAt,
          ),
        );
      }
      const labels = ['specRole', 'status', 'price', 'owner', 'importedAt'];
      final inset = hero == null ? 0.0 : 12.0;
      final width = constraints.maxWidth - inset * 2;
      final compact = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: identity),
              if (action != null) ...[const SizedBox(width: 12), action!],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (var i = 1; i < cells.length; i++)
                SizedBox(
                  width: ((width - 16) / 2).clamp(0, 220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        communityShipsText(context, labels[i - 1]),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.tokens.colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      cells[i],
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
      if (hero == null) return compact;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hero!,
          Padding(
            padding: EdgeInsets.fromLTRB(inset, 10, inset, inset),
            child: compact,
          ),
        ],
      );
    },
  );
}

/// Shared column geometry keeps headers and instances aligned on wide screens.
/// Classification, status and value stay together instead of stretching apart.
class CommunityShipColumns extends StatelessWidget {
  const CommunityShipColumns({
    required this.cells,
    this.showImportedAt = true,
    super.key,
  });
  final List<Widget> cells;
  final bool showImportedAt;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final generous = constraints.maxWidth >= 1150;
      final widths = <int, double>{
        1: !showImportedAt
            ? 230
            : generous
            ? 220
            : 176,
        2: generous ? 96 : 74,
        // The replacement count sits beside the price on the full page.
        3: showImportedAt ? (generous ? 150 : 124) : (generous ? 112 : 82),
        if (showImportedAt) 5: generous ? 112 : 94,
        if (showImportedAt) 6: 72 else 5: 0,
      };
      return Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            if (widths.containsKey(i))
              SizedBox(
                width: widths[i],
                child: Padding(
                  padding: EdgeInsetsDirectional.only(end: i == 6 ? 0 : 12),
                  child: cells[i],
                ),
              )
            else
              Expanded(
                flex: i == 0 ? 6 : 4,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: cells[i],
                ),
              ),
        ],
      );
    },
  );
}

class CommunityShipColumnHeader extends StatelessWidget {
  const CommunityShipColumnHeader({this.showImportedAt = true, super.key});
  final bool showImportedAt;
  @override
  Widget build(BuildContext context) => Padding(
    // Same border/padding and scrollbar gutter as the inventory rows.
    padding: const EdgeInsetsDirectional.fromSTEB(13, 0, 29, 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) return const SizedBox.shrink();
        return CommunityShipColumns(
          showImportedAt: showImportedAt,
          cells: [
            for (final key in [
              'shipColumn',
              'specRole',
              'status',
              'priceColumn',
              'owner',
              if (showImportedAt) 'importedAt',
            ])
              Text(
                communityShipsText(context, key),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.tokens.colors.textSecondary),
              ),
            // The menu overlay's rows still carry an action cell.
            if (!showImportedAt) const SizedBox.shrink(),
          ],
        );
      },
    ),
  );
}

/// One shared inventory row; the caller retains reads, scope and detail actions.
class CommunitySharedShipRow extends StatelessWidget {
  const CommunitySharedShipRow({
    required this.ship,
    required this.targetRef,
    required this.avatarBytes,
    required this.avatarLoading,
    required this.imageDecoder,
    required this.onDetails,
    required this.ownerTargetFactory,
    required this.includeSocialActions,
    this.card = false,
    this.selected = false,
    super.key,
  });

  /// Grid card: large unclipped catalog image instead of the 48px thumbnail.
  final bool card;

  /// Open in the ships page's side column.
  final bool selected;
  final CommunitySharedShip ship;
  final String targetRef;
  final Uint8List? avatarBytes;
  final bool avatarLoading;
  final CommunityImageDecoder imageDecoder;
  final VoidCallback onDetails;
  final OrganizationShipOwnerTargetFactory? ownerTargetFactory;
  final bool includeSocialActions;

  @override
  Widget build(BuildContext context) {
    String t(String key) => communityShipsText(context, key);
    final colors = context.tokens.colors;
    final owner = ship.ownerCallsign.isNotEmpty
        ? ship.ownerCallsign
        : ship.ownerGameName.isNotEmpty
        ? ship.ownerGameName
        : t('owner');
    final presenceKey = communityShipPresenceKey(ship);
    final status = ship.catalogStatus?.toLowerCase() ?? '';
    final statusColor = const {'flyable', '可飞', '可飛'}.contains(status)
        ? colors.success
        : status.contains('concept') || status.contains('概念')
        ? colors.warning
        : colors.textSecondary;
    final roleColor = shipCategoryColor(
      context,
      ship.displayCategory?.toLowerCase() ?? 'unknown',
    );
    final specColor = shipSizeColor(context, ship.displaySpec);
    String value(String? text, [String fallback = 'unknown']) =>
        text == null || text.isEmpty ? t(fallback) : text;
    Widget line(
      String text, {
      Color? color,
      bool bold = false,
      bool title = false,
    }) => StarBridgeTooltip(
      message: text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color ?? colors.textPrimary,
          fontWeight: bold ? FontWeight.w600 : null,
          fontSize: title ? 14 : null,
        ),
      ),
    );
    Widget badge(String text, Color color) =>
        ShipClassificationTag(label: text, color: color);
    final ownerRow = Row(
      children: [
        OrganizationShipOwner(
          targetRef: targetRef,
          ship: ship,
          name: owner,
          avatarBytes: avatarBytes,
          targetFactory: ownerTargetFactory,
          includeSocialActions: includeSocialActions,
          child: CommunityShipOwnerAvatar(
            ship: ship,
            bytes: avatarBytes,
            decoder: imageDecoder,
            maxWidth: 96,
            loading: avatarLoading,
            size: 32,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line(
                '$owner${ship.ownerIsSelf ? ' · ${t('self')}' : ''}',
                bold: true,
              ),
              line(
                ship.ownerGameName.isNotEmpty && ship.ownerGameName != owner
                    ? ship.ownerGameName
                    : AppStrings.of(context).text(presenceKey),
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ],
    );
    final imported = ship.hangarImportedAt?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = imported == null
        ? t('notRecorded')
        : '${imported.year}-${two(imported.month)}-${two(imported.day)}';
    final name = ship.displayName.isEmpty ? ship.code : ship.displayName;
    return CommunityShipRowSurface(
      card: card,
      selected: selected,
      child: StarBridgeActionRow(
        controlKey: ValueKey('community-ship-details-${ship.shipRef}'),
        semanticLabel: '$name · ${t('view')}',
        semanticSelected: selected,
        baseRadius: 0,
        hoverFace: false,
        inheritContentStyle: true,
        onActivate: (_, _) => onDetails(),
        child: CommunityShipBanner(
          key: ValueKey('community-ship-banner-${ship.shipRef}'),
          hero: card
              ? Container(
                  key: ValueKey('community-ship-card-image-${ship.shipRef}'),
                  height: 150,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        context.tokens.surfaces.raised.fill,
                        context.tokens.surfaces.panel.fill,
                      ],
                    ),
                  ),
                  // Contain, never crop (user decision 2026-10-22).
                  child: CommunityCatalogShipImage(
                    asset: ship.catalogImageAsset ?? ship.catalogThumbnailAsset,
                  ),
                )
              : null,
          identity: Row(
            children: [
              if (!card) ...[
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CommunityCatalogShipImage(
                    asset: ship.catalogThumbnailAsset ?? ship.catalogImageAsset,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    line(name, bold: true, title: true),
                    if (ship.subtitleFor(
                          Localizations.localeOf(context).languageCode,
                        )
                        case final subtitle?)
                      line(subtitle, color: colors.textSecondary),
                  ],
                ),
              ),
            ],
          ),
          spec: badge(
            communityShipDisplayText(context, ship.displaySpec),
            specColor,
          ),
          status: Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: line(value(ship.catalogStatus), color: statusColor),
              ),
            ],
          ),
          price: Row(
            children: [
              Flexible(
                child: line(
                  ShipCatalogDisplay.usdText(ship.catalogPriceUsd) ??
                      t('unpublished'),
                  color:
                      ShipCatalogDisplay.usdCents(ship.catalogPriceUsd) == null
                      ? colors.textSecondary
                      : colors.info,
                ),
              ),
              CommunityShipLoanerCount(ship: ship),
            ],
          ),
          role: badge(
            communityShipDisplayText(context, ship.displayRole),
            roleColor,
          ),
          vehicleIcon: CommunityShipVehicleIcon(ship: ship),
          owner: ownerRow,
          importedAt: StarBridgeTooltip(
            message: t('importedAt'),
            child: line(date, color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}
