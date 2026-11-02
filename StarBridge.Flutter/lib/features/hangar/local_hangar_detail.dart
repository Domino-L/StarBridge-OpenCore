import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'local_hangar_copy.dart';

/// A bounded quick-detail surface that can expand without replacing inventory.
/// The body owns existing domain actions; future ship features can add sections.
class LocalHangarDetail extends StatefulWidget {
  const LocalHangarDetail({required this.title, required this.body, super.key});
  final String title;
  final Widget body;
  @override
  State<LocalHangarDetail> createState() => _LocalHangarDetailState();
}

class _LocalHangarDetailState extends State<LocalHangarDetail> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    return LayoutBuilder(
      builder: (context, bounds) => Semantics(
        namesRoute: true,
        label: c.details,
        child: Align(
          alignment: _expanded ? Alignment.center : Alignment.centerRight,
          child: SizedBox(
            width: math.min(bounds.maxWidth, _expanded ? 880 : 440),
            height: double.infinity,
            child: Material(
              color: t.surfaces.panel.fill,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          StarBridgeIconAction(
                            controlKey: const Key('hangar-detail-expand'),
                            label: _expanded
                                ? c.compactDetails
                                : c.expandDetails,
                            consumeHintEscape: false,
                            onActivate: (_) =>
                                setState(() => _expanded = !_expanded),
                            icon: _expanded
                                ? const StandardIcon(
                                    StandardIconSemantic.unfoldLess,
                                  )
                                : const StarBridgeIcon(
                                    StarBridgeIconSemantic.resize,
                                  ),
                          ),
                          StarBridgeIconAction(
                            controlKey: const Key('hangar-detail-close'),
                            label: c.close,
                            consumeHintEscape: false,
                            onActivate: (source) => dismissStarBridgeDialog(
                              context,
                              source: source,
                            ),
                            icon: const StarBridgeIcon(
                              StarBridgeIconSemantic.windowClose,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: SingleChildScrollView(child: widget.body),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
