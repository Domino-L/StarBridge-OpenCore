import '../../design_system/icons/standard_icon.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../shared/ships/ship_category_colors.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../shared/ships/ship_catalog_display.dart';
import '../common/organization_ship_owner.dart';
import 'community_ship_detail_controller.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';
import 'community_ship_loaners.dart';
import 'community_ship_owner_avatar.dart';
import 'community_workspace_image.dart';
import 'community_catalog_ship_image.dart';
import 'community_visible_refresh.dart';
import 'community_image_decoder.dart';
import 'community_ship_report_port.dart';
import 'community_ship_report_dialog.dart';

/// A shared ship's details. The dialog shows it with a title and close
/// action; the ships page's side column shows it inline (user decision
/// 2026-10-29, option D). Either way the page is reauthorized first.
class CommunityShipDetailPane extends StatefulWidget {
  const CommunityShipDetailPane({
    required this.port,
    required this.page,
    required this.shipRef,
    this.avatar,
    this.ownerTargetFactory = communityShipOwnerTarget,
    this.includeSocialActions = true,
    this.imageDecoder = decodeCommunityImage,
    this.inline = false,
    this.pageIsCurrent = false,
    this.reconcile = false,
    this.onClose,
    this.onRefreshLibrary,
    super.key,
  });
  final CommunityShipsPort port;
  final CommunityShipsPage page;
  final String shipRef;
  final Uint8List? avatar;
  final OrganizationShipOwnerTargetFactory? ownerTargetFactory;
  final bool includeSocialActions;
  final CommunityImageDecoder imageDecoder;

  /// Inline: no title row or close action; the invalidation of the page is
  /// the owner's to handle, not a route to pop.
  final bool inline;

  /// Show [page]'s row without reading again.
  final bool pageIsCurrent;

  /// Inline only: the list on screen no longer covers this ship (another
  /// filter), so nothing else would notice it being withdrawn.
  final bool reconcile;
  final void Function(InteractionSource source)? onClose, onRefreshLibrary;
  @override
  State<CommunityShipDetailPane> createState() =>
      _CommunityShipDetailPaneState();
}

class _CommunityShipDetailPaneState extends State<CommunityShipDetailPane>
    with CommunityVisibleRefresh<CommunityShipDetailPane> {
  late final model = CommunityShipDetailController(
    widget.port,
    widget.page,
    widget.shipRef,
  );
  String t(String key) => communityShipsText(context, key);
  @override
  Duration get communityRefreshInterval => widget.inline
      ? const Duration(seconds: 60)
      : const Duration(seconds: 15);
  final _reportParentRetirements = StreamController<void>.broadcast();
  bool _reportOpen = false;
  Future<void> _openReport() async {
    final ship = model.ship, image = model.image, port = widget.port;
    if (_reportOpen ||
        !model.canReportImage ||
        ship == null ||
        image == null ||
        port is! CommunityShipReportPort) {
      return;
    }
    _reportOpen = true;
    await showStarBridgeDialog<void>(
      context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => CommunityShipReportDialog(
        port: port as CommunityShipReportPort,
        ships: widget.port,
        targetRef: widget.page.targetRef,
        shipRef: ship.shipRef,
        version: image.version,
        shipName: ship.displayName,
        parentRetirements: _reportParentRetirements.stream,
      ),
    );
    if (mounted) setState(() => _reportOpen = false);
  }

  @override
  Future<void> refreshVisibleCommunity() async {
    // The right column stays open on every ship page: no polling there, unless
    // the list cannot cover it, and then slowly.
    if (widget.inline && !widget.reconcile) return;
    if (model.error == null) await model.load(background: true);
  }

  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    unawaited(model.load(fromPage: widget.pageIsCurrent));
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (model.invalidated && !widget.inline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route?.isActive == true) route!.navigator?.removeRoute(route);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void dispose() {
    _reportParentRetirements.add(null);
    unawaited(_reportParentRetirements.close());
    model.removeListener(_changed);
    model.dispose();
    super.dispose();
  }

  String date(DateTime? value) {
    if (value == null) return t('notRecorded');
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget fact(String label, String value, {bool price = false}) => SizedBox(
    width: widget.inline ? 140 : 190,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(label),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.tokens.colors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: price ? TextStyle(color: context.tokens.colors.info) : null,
        ),
      ],
    ),
  );

  String _day(DateTime? value) {
    if (value == null) return t('notRecorded');
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  /// The side column's layout, as the approved preview (2026-10-29): the
  /// catalog art on top, the name, one line of model facts, then right-
  /// aligned rows for the owner, the sharing date and the price.
  Widget _inlineContent(CommunitySharedShip ship, String owner) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: tokens.colors.textSecondary);
    final subtitle = ship.subtitleFor(
      Localizations.localeOf(context).languageCode,
    );
    final priced = ShipCatalogDisplay.usdCents(ship.catalogPriceUsd) != null;
    final value = text.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    Widget row(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(t(label), style: muted)),
          child,
        ],
      ),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipPath(
            clipper: const _ChamferClipper(14),
            child: Container(
              height: 150,
              color: tokens.surfaces.raised.fill,
              child: CommunityCatalogShipImage(
                asset: ship.catalogImageAsset ?? ship.catalogThumbnailAsset,
                compact: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            ship.displayName.isEmpty ? ship.code : ship.displayName,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: muted,
              children: [
                if (subtitle != null) TextSpan(text: '$subtitle · '),
                TextSpan(
                  text: communityShipDisplayText(context, ship.displaySpec),
                ),
                const TextSpan(text: ' · '),
                TextSpan(
                  text: communityShipDisplayText(context, ship.displayRole),
                  style: TextStyle(
                    color: shipCategoryColor(
                      context,
                      ship.displayCategory?.toLowerCase() ?? 'unknown',
                    ),
                  ),
                ),
                TextSpan(text: ' · ${ship.catalogStatus ?? t('unknown')}'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          row(
            'owner',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OrganizationShipOwner(
                  targetRef: widget.page.targetRef,
                  ship: ship,
                  name: owner,
                  avatarBytes: widget.avatar,
                  targetFactory: widget.ownerTargetFactory,
                  includeSocialActions: widget.includeSocialActions,
                  child: CommunityShipOwnerAvatar(
                    ship: ship,
                    bytes: widget.avatar,
                    decoder: widget.imageDecoder,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Text(owner.isEmpty ? t('unknown') : owner, style: value),
              ],
            ),
          ),
          row('sharedAt', Text(_day(ship.sharedAt), style: value)),
          row(
            'price',
            Text(
              ShipCatalogDisplay.usdText(ship.catalogPriceUsd) ??
                  t('unpublished'),
              style: value?.copyWith(color: priced ? tokens.colors.info : null),
            ),
          ),
          CommunityShipLoaners(ship: ship),
          if (model.canReadImage) ...[
            const SizedBox(height: 12),
            Text(t('customImage'), style: muted),
            const SizedBox(height: 6),
            SizedBox(
              height: 160,
              child: CommunityWorkspaceImage(
                key: const Key('community-ship-custom-image'),
                bytes: model.image?.bytes,
                maxWidth: 1024,
                icon: StandardIconSemantic.brokenImage,
                loading: model.imageBusy,
                loadFailed: model.imageError != null,
                failureMessage: t('customImageUnavailable'),
                decoder: widget.imageDecoder,
                crop: model.image == null
                    ? null
                    : (
                        focusX: model.image!.focusX,
                        focusY: model.image!.focusY,
                        zoom: model.image!.zoom,
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _content(CommunitySharedShip ship, String owner) => widget.inline
      ? _inlineContent(ship, owner)
      : LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ship.displayName.isEmpty ? ship.code : ship.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (ship.subtitleFor(
                      Localizations.localeOf(context).languageCode,
                    )
                    case final subtitle?)
                  SelectableText(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: context.tokens.colors.textSecondary),
                  ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 24,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: 250,
                      child: Row(
                        children: [
                          OrganizationShipOwner(
                            targetRef: widget.page.targetRef,
                            ship: ship,
                            name: owner,
                            avatarBytes: widget.avatar,
                            targetFactory: widget.ownerTargetFactory,
                            includeSocialActions: widget.includeSocialActions,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CommunityWorkspaceImage(
                                bytes: widget.avatar,
                                icon: StandardIconSemantic.person,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t('owner'),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color:
                                            context.tokens.colors.textSecondary,
                                      ),
                                ),
                                Text(owner.isEmpty ? t('unknown') : owner),
                                if (ship.ownerGameName.isNotEmpty &&
                                    ship.ownerGameName != owner)
                                  Text(ship.ownerGameName),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    fact('sharedAt', date(ship.sharedAt)),
                    fact('importedAt', date(ship.hangarImportedAt)),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 24,
                  runSpacing: 14,
                  children: [
                    fact(
                      'spec',
                      communityShipDisplayText(context, ship.displaySpec),
                    ),
                    fact('status', ship.catalogStatus ?? t('unknown')),
                    fact(
                      'role',
                      communityShipDisplayText(context, ship.displayRole),
                    ),
                    fact(
                      'price',
                      ShipCatalogDisplay.usdText(ship.catalogPriceUsd) ??
                          t('unpublished'),
                      price:
                          ShipCatalogDisplay.usdCents(ship.catalogPriceUsd) !=
                          null,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                CommunityShipLoaners(ship: ship),
                Text(
                  t('catalogImage'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  height: constraints.maxWidth.clamp(0, 924) * 420 / 1200,
                  decoration: BoxDecoration(
                    color: context.tokens.surfaces.raised.fill,
                    border: Border.all(
                      color: context.tokens.surfaces.panel.border,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: CommunityCatalogShipImage(
                    asset: ship.catalogImageAsset,
                  ),
                ),
                if (model.canReadImage) ...[
                  const SizedBox(height: 20),
                  Text(
                    t('customImage'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: widget.inline ? 200 : 280,
                    child: CommunityWorkspaceImage(
                      key: const Key('community-ship-custom-image'),
                      bytes: model.image?.bytes,
                      maxWidth: 1024,
                      icon: StandardIconSemantic.brokenImage,
                      loading: model.imageBusy,
                      loadFailed: model.imageError != null,
                      failureMessage: t('customImageUnavailable'),
                      decoder: widget.imageDecoder,
                      crop: model.image == null
                          ? null
                          : (
                              focusX: model.image!.focusX,
                              focusY: model.image!.focusY,
                              zoom: model.image!.zoom,
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final ship = model.ship;
    final owner = ship == null
        ? ''
        : ship.ownerCallsign.isNotEmpty
        ? ship.ownerCallsign
        : ship.ownerGameName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.inline) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  t('detailTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              StarBridgeIconAction(
                controlKey: const Key('community-ship-detail-close-icon'),
                label: t('close'),
                onActivate: (source) => widget.onClose?.call(source),
                icon: const StandardIcon(StandardIconSemantic.close),
              ),
            ],
          ),
          const Divider(height: 20),
        ],
        Expanded(
          child: ship == null
              ? Center(
                  child: model.busy
                      ? const CircularProgressIndicator()
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            t(model.error ?? 'unavailable'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                )
              : _content(ship, owner),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: widget.inline ? WrapAlignment.start : WrapAlignment.end,
          spacing: 10,
          runSpacing: 8,
          children: [
            if (model.canReportImage)
              StarBridgeActionButton(
                controlKey: const Key('community-ship-report-image'),
                kind: widget.inline
                    ? StarBridgeActionKind.secondary
                    : StarBridgeActionKind.quiet,
                onActivate: _reportOpen ? null : (_) => _openReport(),
                child: Text(t('reportTitle')),
              ),
            if (model.error == 'shipsChanged')
              StarBridgeActionButton(
                controlKey: const Key('community-ship-detail-refresh-library'),
                kind: widget.inline
                    ? StarBridgeActionKind.secondary
                    : StarBridgeActionKind.quiet,
                onActivate: (source) => widget.onRefreshLibrary?.call(source),
                child: Text(t('refreshLibrary')),
              )
            else if (!model.invalidated)
              StarBridgeActionButton(
                controlKey: const Key('community-ship-detail-retry'),
                kind: widget.inline
                    ? StarBridgeActionKind.secondary
                    : StarBridgeActionKind.quiet,
                onActivate: model.busy ? null : (_) => unawaited(model.load()),
                child: Text(t('imageRetry')),
              ),
            if (!widget.inline)
              StarBridgeActionButton(
                controlKey: const Key('community-ship-detail-close'),
                onActivate: (source) => widget.onClose?.call(source),
                child: Text(t('close')),
              ),
          ],
        ),
        if (widget.inline)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              t('arrowHint'),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: context.tokens.colors.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// Cuts the bottom-end corner, as the holo panels do.
class _ChamferClipper extends CustomClipper<Path> {
  const _ChamferClipper(this.run);
  final double run;
  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - run)
    ..lineTo(size.width - run, size.height)
    ..lineTo(0, size.height)
    ..close();
  @override
  bool shouldReclip(_ChamferClipper oldClipper) => oldClipper.run != run;
}
