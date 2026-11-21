import 'dart:async';
import 'package:flutter/material.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listing_item_picker.dart';
import 'marketplace_listing_publish_widgets.dart';
import 'marketplace_listing_quantity.dart';
import 'marketplace_listings_controller.dart';
import 'marketplace_trade_feedback.dart';
import 'marketplace_widgets.dart';

/// A separate lookup controller keeps wanted-item searches out of offered items.
class ListingBarterFields extends StatefulWidget {
  const ListingBarterFields(this.c, this.draft, {required this.onChanged, super.key});
  final MarketplaceListingsController c;
  final ListingDraft draft;
  final VoidCallback onChanged;
  @override
  State<ListingBarterFields> createState() => _BarterState();
}

class _BarterState extends State<ListingBarterFields> {
  late final lookup = MarketplaceListingsController(widget.c.port);
  late final picked = ListingDraft(item: widget.draft.wantedItem);
  late final offered = TextEditingController(text: widget.draft.offeredQuantity);
  late final wanted = TextEditingController(text: widget.draft.wantedQuantity);
  @override
  void dispose() {
    lookup.dispose();
    offered.dispose();
    wanted.dispose();
    super.dispose();
  }

  Future<void> choose() async {
    unawaited(lookup.loadCategories());
    unawaited(lookup.searchItems(''));
    await tradeMotionDialog<void>(context, (ctx) => AlertDialog(
      title: Text(listingText(ctx, '想要的物品')),
      // The picker's two columns need about 640 px; on a narrower surface
      // (e.g. the in-game menu) it scrolls sideways instead of overflowing.
      content: SizedBox(width: 820, child: LayoutBuilder(
        builder: (_, box) {
          final picker = ListenableBuilder(
            listenable: lookup,
            builder: (_, _) => ListingItemPicker(lookup, picked, onPicked: () {
              widget.draft.wantedItem = Map.of(picked.item);
              widget.draft.wanted = '${picked.item['id']}';
              widget.onChanged();
              Navigator.pop(ctx);
            }),
          );
          return box.maxWidth >= 640 ? picker : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: 640, child: picker),
          );
        },
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx),
        child: Text(listingText(ctx, '取消')))],
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      marketTextAction(key: const Key('market-publish-wanted'),
        onPressed: choose,
        child: Text('${widget.draft.wantedItem['name'] ?? listingText(context, '请选择想要的物品')}')),
      if (widget.draft.manifestId == null) ...[
        const ListingLabel('每次给出'),
        ListingQuantityField(input: offered, identity: 'publish-offered-quantity', maximum: 999,
          onChanged: (v) => setState(() {
            widget.draft.offeredQuantity = v;
            widget.onChanged();
          })),
      ],
      const ListingLabel('想要数量'),
      ListingQuantityField(input: wanted, identity: 'publish-wanted-quantity', maximum: 999,
        onChanged: (v) => setState(() {
          widget.draft.wantedQuantity = v;
          widget.onChanged();
        })),
    ],
  );
}
