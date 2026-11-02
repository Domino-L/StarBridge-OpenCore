import 'package:flutter/material.dart';

import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/styles/marketplace_palette.dart';
import 'marketplace_contracts_copy.dart';
import 'marketplace_states.dart';
import 'marketplace_trade_style.dart';

/// Cancel / confirm for the contract's small dialogs; confirm returns [result].
List<Widget> contractDialogActions<T>(
  BuildContext dialog, {
  required T? Function() result,
}) => [
  marketButtonAction(
    key: const Key('market-contract-dialog-cancel'),
    TextButton(
      onPressed: () => dismissStarBridgeDialog<T>(
        dialog,
        source: StarBridgeActivationOrigin.sourceOf(dialog),
      ),
      child: Text(contractText(dialog, '取消')),
    ),
  ),
  marketButtonAction(
    key: const Key('market-contract-dialog-confirm'),
    FilledButton(
      style: tradePrimaryStyle(dialog),
      onPressed: result() == null
          ? null
          : () => dismissStarBridgeDialog<T>(
              dialog,
              source: StarBridgeActivationOrigin.sourceOf(dialog),
              result: result(),
            ),
      child: Text(contractText(dialog, '确认')),
    ),
  ),
];

/// Owns its field, so the closing animation never sees a disposed one.
class ContractTextDialog extends StatefulWidget {
  const ContractTextDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.required,
  });
  final String title, hint;
  final bool required;
  @override
  State<ContractTextDialog> createState() => ContractTextDialogState();
}

class ContractTextDialogState extends State<ContractTextDialog> {
  final _field = TextEditingController();
  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: TextField(
        key: const Key('market-contract-input'),
        controller: _field,
        autofocus: true,
        maxLength: 1000,
        maxLines: 4,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(hintText: widget.hint),
      ),
    ),
    actions: contractDialogActions<String>(
      context,
      result: () =>
          widget.required && _field.text.trim().isEmpty ? null : _field.text,
    ),
  );
}

class ContractReviewDialog extends StatefulWidget {
  const ContractReviewDialog({super.key});
  @override
  State<ContractReviewDialog> createState() => ContractReviewDialogState();
}

class ContractReviewDialogState extends State<ContractReviewDialog> {
  final _comment = TextEditingController();
  int _rating = 5;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(contractText(context, '去评价')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 5; i++)
              marketButtonAction(
                key: ValueKey(('market-contract-rating', i)),
                TextButton(
                  onPressed: () => setState(() => _rating = i),
                  child: MarketplaceIcon(
                    i <= _rating
                        ? MarketplaceGlyph.rating
                        : MarketplaceGlyph.ratingEmpty,
                    size: 22,
                    color: MarketplacePalette.gold,
                  ),
                ),
              ),
          ],
        ),
        TextField(
          controller: _comment,
          maxLength: 1000,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: contractText(context, '评价（可选）'),
          ),
        ),
      ],
    ),
    actions: contractDialogActions<(int, String)>(
      context,
      result: () => (_rating, _comment.text.trim()),
    ),
  );
}
