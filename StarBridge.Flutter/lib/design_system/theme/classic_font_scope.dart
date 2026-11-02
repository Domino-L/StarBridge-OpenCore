import 'package:flutter/material.dart';

import '../interaction/starbridge_interaction_theme.dart';
import '../tokens/starbridge_tokens.dart';
import 'theme_builder.dart';

/// QualityPass ⑧ (user 2026-10-29): Saira and Rajdhani replace Source Sans 3
/// across the app, but the holo pages (main fleet, joined communities) keep the
/// look the user accepted. Everything below this scope resolves the previous
/// families, while colors, motion and the interaction suite stay as they are.
class ClassicFontScope extends StatefulWidget {
  const ClassicFontScope({required this.child, super.key});

  final Widget child;

  @override
  State<ClassicFontScope> createState() => _ClassicFontScopeState();
}

class _ClassicFontScopeState extends State<ClassicFontScope> {
  StarBridgeTokens? _tokens;
  Locale? _locale;
  InteractionSuite? _suite;
  ThemeData? _theme;

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context);
    final tokens = outer.extension<StarBridgeTokens>();
    if (tokens == null) return widget.child;
    final locale = Localizations.localeOf(context);
    final suite =
        outer.extension<StarBridgeInteractionTheme>()?.suite ??
        InteractionSuite.standard;
    if (!identical(tokens, _tokens) || locale != _locale || suite != _suite) {
      _tokens = tokens;
      _locale = locale;
      _suite = suite;
      _theme = buildStarBridgeTheme(
        tokens.copyWith(typography: tokens.typography.withClassicFamilies()),
        locale,
        interactionSuite: suite,
      );
    }
    final theme = _theme!;
    return Theme(
      data: theme,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontFamily: theme.textTheme.bodyMedium?.fontFamily),
        child: widget.child,
      ),
    );
  }
}
