import 'package:flutter/material.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_image_editor.dart';
import 'local_hangar_images.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_ship_image.dart';
import 'ship_specifications_panel.dart';
import 'ship_specifications_port.dart';

/// Instance collection details and shared model facts remain separate surfaces.
class LocalHangarShipDetails extends StatefulWidget {
  const LocalHangarShipDetails({
    required this.ship,
    required this.former,
    required this.instanceIndex,
    required this.instanceCount,
    required this.onImageSaved,
    this.images,
    this.specifications,
    this.onFavorite,
    this.refreshImages,
    this.onEditPersonalData,
    super.key,
  });
  final LocalHangarShip ship;
  final bool former;
  final int instanceIndex, instanceCount;
  final LocalHangarImagePort? images;
  final ShipSpecificationsProvider? specifications;
  final VoidCallback onImageSaved;
  final Future<LocalHangarShip?> Function()? onFavorite;
  final LocalHangarImagePort? Function()? refreshImages;
  final Future<LocalHangarShip?> Function()? onEditPersonalData;

  @override
  State<LocalHangarShipDetails> createState() => _LocalHangarShipDetailsState();
}

class _LocalHangarShipDetailsState extends State<LocalHangarShipDetails> {
  late LocalHangarShip _ship = widget.ship;
  late LocalHangarImagePort? _images = widget.images;
  bool _busy = false;
  bool _failed = false;

  Future<void> _editPersonalData() async {
    setState(() => _busy = true);
    try {
      final ship = await widget.onEditPersonalData!();
      if (mounted && ship != null) {
        setState(() {
          _ship = ship;
          if (widget.refreshImages != null) _images = widget.refreshImages!();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _favorite() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final ship = await widget.onFavorite!();
      if (mounted) {
        setState(() {
          _failed = ship == null || ship.isFavorite == _ship.isFavorite;
          if (ship != null) {
            _ship = ship;
            if (!_failed && widget.refreshImages != null) {
              _images = widget.refreshImages!();
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context),
        item = LocalHangarPresentation.fromSaved(_ship);
    Widget field(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
    final metadata = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                c.thisShip,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (widget.onFavorite != null)
              StarBridgeIconAction(
                controlKey: const Key('hangar-detail-favorite'),
                label: _ship.isFavorite ? c.unfavorite : c.favorite,
                selected: _ship.isFavorite,
                consumeHintEscape: false,
                onActivate: _busy ? null : (_) => _favorite(),
                icon: StandardIcon(
                  _ship.isFavorite
                      ? StandardIconSemantic.bookmarked
                      : StandardIconSemantic.bookmark,
                ),
              ),
          ],
        ),
        if (_ship.nickname?.trim().isNotEmpty == true)
          field(c.pick('昵称', '暱稱', 'Nickname'), _ship.nickname!),
        if (_ship.notes?.trim().isNotEmpty == true)
          field(c.pick('备注', '備註', 'Notes'), _ship.notes!),
        if (widget.onEditPersonalData != null)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('hangar-edit-personal-data'),
            onActivate: _busy ? null : (_) => _editPersonalData(),
            child: Text(
              c.pick('编辑昵称与备注', '編輯暱稱與備註', 'Edit nickname and notes'),
            ),
          ),
        if (widget.instanceCount > 1) ...[
          Text(
            c.instance(widget.instanceIndex, widget.instanceCount),
            key: const Key('hangar-detail-instance'),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.former)
          field(
            c.removedAt,
            _ship.removedAt == null
                ? c.unknown
                : c.dateTime(context, _ship.removedAt!),
          ),
        if (_ship.addedAt case final added?)
          field(c.addedAt, c.dateTime(context, added)),
        const Divider(height: 28),
        Text(
          c.pick('型号', '型號', 'Model'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        field(c.original, _ship.title),
        if (_ship.liner?.trim().isNotEmpty == true)
          field(c.manufacturer, _ship.liner!.trim()),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            if (item.role != 'unknown') Text(c.category(item.role)),
            if (c.combatSize(item.sizeClass ?? _ship.size) case final size?)
              Text(size),
            if (item.status != 'unknown') Text(c.status(item.status)),
          ],
        ),
        if (item.priceCents case final cents?) ...[
          const SizedBox(height: 10),
          field(c.priceLabel, '${c.usd(cents / 100)} USD'),
          Text(c.priceBasis, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (_failed)
          Semantics(liveRegion: true, child: Text(c.favoriteFailure)),
      ],
    );
    return SelectionArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide =
              bounds.maxWidth >= 680 &&
              MediaQuery.textScalerOf(context).scale(14) <= 20;
          final imageWidth = wide
              ? (bounds.maxWidth - 24) / 2
              : bounds.maxWidth;
          final fallback = LocalHangarShipImage(
            item: item,
            width: imageWidth,
            height: imageWidth * 9 / 16,
            fit: BoxFit.contain,
          );
          final media = _images == null
              ? fallback
              : LocalHangarImageEditor(
                  port: _images!,
                  preserveImageOnPortChange: true,
                  editable: !widget.former,
                  fallback: fallback,
                  onSaved: widget.onImageSaved,
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: media),
                    const SizedBox(width: 24),
                    Expanded(child: metadata),
                  ],
                )
              else ...[
                media,
                const SizedBox(height: 12),
                metadata,
              ],
              if (widget.specifications case final provider?)
                ShipSpecificationsPanel(ship: _ship, provider: provider),
            ],
          );
        },
      ),
    );
  }
}
