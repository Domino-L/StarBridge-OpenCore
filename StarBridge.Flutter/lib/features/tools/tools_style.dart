import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../marketplace/marketplace_surfaces.dart';
import '../marketplace/marketplace_widgets.dart';

export '../../design_system/tokens/starbridge_tokens.dart';
export '../marketplace/marketplace_banner.dart' show MarketSectionHeading;
export '../marketplace/marketplace_surfaces.dart';
export '../marketplace/marketplace_widgets.dart';

TextStyle toolNumber(BuildContext context, {double size = 24, Color? color}) =>
    TextStyle(
      fontFamily: context.tokens.typography.monoFamily,
      fontFamilyFallback: const ['Source Han Sans CN'],
      fontWeight: FontWeight.w600,
      fontSize: size,
      color: color ?? context.tokens.colors.textPrimary,
    );

class ToolsSurface extends StatelessWidget {
  const ToolsSurface({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.tokens.surfaces.ground.fill,
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class ToolsRule extends StatelessWidget {
  const ToolsRule({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(height: 1, color: marketLine(context)),
  );
}

class ToolsAction extends StatelessWidget {
  const ToolsAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  @override
  Widget build(BuildContext context) => marketButtonAction(
    outlined
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : TextButton(onPressed: onPressed, child: Text(label)),
  );
}

/// The fleet's square role badge treatment, including for grades and types.
class ToolsTag extends StatelessWidget {
  const ToolsTag(this.label, {super.key, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final ink = color ?? context.tokens.colors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: ink.withValues(alpha: .6)),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: ink)),
    );
  }
}

class ToolsStat extends StatelessWidget {
  const ToolsStat(
    this.label,
    this.value, {
    super.key,
    this.size = 30,
    this.color,
  });
  final String label, value;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.tokens.colors.textSecondary,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: toolNumber(context, size: size, color: color),
      ),
    ],
  );
}

class ToolsOption extends StatelessWidget {
  const ToolsOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final text = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected
              ? context.tokens.colors.textPrimary
              : context.tokens.colors.textSecondary,
        ),
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: selected ? MarketSlantFace(selected: true, child: text) : text,
      ),
    );
  }
}
