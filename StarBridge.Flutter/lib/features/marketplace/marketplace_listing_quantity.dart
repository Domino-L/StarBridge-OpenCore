import 'package:flutter/material.dart';
import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_listing_copy.dart';
import 'marketplace_listing_publish_widgets.dart';

/// Quantity − / + read as part of the field: no fill or outline of their own.
const _stepperStyle = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.transparent),
  side: WidgetStatePropertyAll(BorderSide.none),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
  ),
  visualDensity: VisualDensity.compact,
);

/// The publish quantity field, shared without changing its appearance.
class ListingQuantityField extends StatelessWidget {
  const ListingQuantityField({required this.input, required this.identity,
    required this.onChanged, this.maximum = 999999, super.key});
  final TextEditingController input;
  final String identity;
  final ValueChanged<String> onChanged;
  final int maximum;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens, qty = int.tryParse(input.text);
    void adjust(int value) {
      input.text = '$value';
      onChanged(input.text);
    }
    return TextFormField(
      key: ValueKey(identity),
      controller: input,
      keyboardType: TextInputType.number,
      style: TextStyle(
        fontFamily: t.typography.monoFamily,
        fontSize: 15,
      ),
      textAlign: TextAlign.center,
      decoration: listingInputDecoration(context).copyWith(
        // − and + read as part of the field: no own fill, a
        // hairline between them and the number.
        prefixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StarBridgeNativeIconAction(
              controlKey: ValueKey(identity == 'publish-quantity' ? 'market-publish-qty-dec' : '$identity-dec'),
              label: listingText(context, '减少数量'),
              style: _stepperStyle,
              onActivate: qty == null || qty <= 1
                  ? null
                  : (_) => adjust(qty - 1),
              icon: const MarketplaceIcon(
                MarketplaceGlyph.remove,
                size: 16,
              ),
            ),
            Container(width: 1, height: 18, color: t.surfaces.panel.border),
          ],
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 1, height: 18, color: t.surfaces.panel.border),
            StarBridgeNativeIconAction(
              controlKey: ValueKey(identity == 'publish-quantity' ? 'market-publish-qty-inc' : '$identity-inc'),
              label: listingText(context, '增加数量'),
              style: _stepperStyle,
              onActivate: qty == null || qty >= maximum
                  ? null
                  : (_) => adjust(qty + 1),
              icon: const MarketplaceIcon(
                MarketplaceGlyph.add,
                size: 16,
              ),
            ),
          ],
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 32),
        suffixIconConstraints: const BoxConstraints(minWidth: 32),
      ),
      onChanged: onChanged,
    );
  }
}
