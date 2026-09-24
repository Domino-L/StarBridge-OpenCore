import '../../design_system/icons/standard_icon.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/ships/ship_catalog_display.dart';
import '../common/user_avatar_menu.dart';
import 'community_ship_detail_controller.dart';
import 'community_ships_copy.dart';
import 'community_ships_port.dart';
import 'community_ship_loaners.dart';
import 'community_workspace_image.dart';
import 'community_catalog_ship_image.dart';
import 'community_visible_refresh.dart';

class CommunityShipDetailDialog extends StatefulWidget {
  const CommunityShipDetailDialog({
    required this.port,
    required this.page,
    required this.shipRef,
    this.avatar,
    super.key,
  });
  final CommunityShipsPort port;
  final CommunityShipsPage page;
  final String shipRef;
  final Uint8List? avatar;
  @override
  State<CommunityShipDetailDialog> createState() =>
      _CommunityShipDetailDialogState();
}

class _CommunityShipDetailDialogState extends State<CommunityShipDetailDialog>
    with CommunityVisibleRefresh<CommunityShipDetailDialog> {
  late final model = CommunityShipDetailController(
    widget.port,
    widget.page,
    widget.shipRef,
  );
  String t(String key) => communityShipsText(context, key);
  @override
  Future<void> refreshVisibleCommunity() async {
    if (model.error == null) await model.load(background: true);
  }

  @override
  void initState() {
    super.initState();
    model.addListener(_changed);
    unawaited(model.load());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (model.invalidated) {
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
    width: 190,
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
  @override
  Widget build(BuildContext context) {
    final ship = model.ship;
    final screen = MediaQuery.sizeOf(context);
    final owner = ship == null
        ? ''
        : ship.ownerCallsign.isNotEmpty
        ? ship.ownerCallsign
        : ship.ownerGameName;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 960,
        height: (screen.height - 48).clamp(0, 760),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('detailTitle'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: t('close'),
                    onPressed: () => Navigator.pop(context, false),
                    icon: const StandardIcon(StandardIconSemantic.close),
                  ),
                ],
              ),
              const Divider(height: 20),
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
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              ship.displayName.isEmpty
                                  ? ship.code
                                  : ship.displayName,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (ship.subtitleFor(
                                  Localizations.localeOf(context).languageCode,
                                )
                                case final subtitle?)
                              SelectableText(
                                subtitle,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color:
                                          context.tokens.colors.textSecondary,
                                    ),
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
                                      UserAvatarMenu(
                                        name: owner,
                                        avatarBytes: widget.avatar,
                                        isSelf: ship.ownerIsSelf,
                                        target: UserTarget.community(widget.page.targetRef, ship.ownerMemberRef, query: ship.ownerGameName),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t('owner'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: context
                                                        .tokens
                                                        .colors
                                                        .textSecondary,
                                                  ),
                                            ),
                                            Text(
                                              owner.isEmpty
                                                  ? t('unknown')
                                                  : owner,
                                            ),
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
                                  communityShipDisplayText(
                                    context,
                                    ship.displaySpec,
                                  ),
                                ),
                                fact(
                                  'status',
                                  ship.catalogStatus ?? t('unknown'),
                                ),
                                fact(
                                  'role',
                                  communityShipDisplayText(
                                    context,
                                    ship.displayRole,
                                  ),
                                ),
                                fact(
                                  'price',
                                  ShipCatalogDisplay.usdText(
                                        ship.catalogPriceUsd,
                                      ) ??
                                      t('unpublished'),
                                  price:
                                      ShipCatalogDisplay.usdCents(
                                        ship.catalogPriceUsd,
                                      ) !=
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
                              height:
                                  (screen.width - 68).clamp(0, 924) *
                                  420 /
                                  1200,
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
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (model.error == 'shipsChanged')
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('refreshLibrary')),
                    )
                  else if (!model.invalidated)
                    TextButton(
                      onPressed: model.busy
                          ? null
                          : () => unawaited(model.load()),
                      child: Text(t('imageRetry')),
                    ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(t('close')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
