import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'key_bindings_caps.dart';
import 'key_bindings_index.dart';
import 'key_bindings_labels.dart';
import 'key_bindings_layouts.dart';

const _modifierKeys = {'lalt', 'ralt', 'lctrl', 'rctrl', 'lshift', 'rshift'};

/// What the keyboard shows right now. The page owns it, so the list stays in step.
final class KeyboardViewState {
  const KeyboardViewState({
    required this.size,
    required this.scene,
    required this.layer,
    required this.query,
    required this.allLayers,
    required this.selected,
    required this.shortcuts,
    this.quiet = false,
    this.onlyChanged = false,
  });
  final bool onlyChanged;
  final KeyBindingsKeyboardSize size;
  final String scene, layer, query;

  /// Without the defaults table only changed keys exist, on whatever layer.
  final bool allLayers;
  final String selected;
  final Set<String> shortcuts;

  /// The file could not be read: the shape stays, and nothing is lit.
  final bool quiet;
}

/// Key text never scales with the system setting: the key is a fixed shape, and
/// the hover, the opened key and the list carry the same words at full scale.
KeyCapFitter keyCapFitterFor(
  BuildContext context,
  double unit,
  double keys, [
  double rows = 1,
]) {
  final tight = unit < 56;
  final family = Theme.of(context).textTheme.bodyMedium?.fontFamily;
  final fallback = Theme.of(context).textTheme.bodyMedium?.fontFamilyFallback;
  return KeyCapFitter(
    style: TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: tight ? 10 : 10.5,
      height: tight ? 1.15 : 1.19,
    ),
    smallStyle: TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: tight ? 9 : 9.5,
      height: 1.16,
    ),
    // Key gap, side padding, then border and a pixel to spare: what the Text gets.
    width: keys * unit - 3 - (tight ? 10 : 12) - 3,
    // Below the key's own letter, which takes one line of its size.
    height:
        rows * unit - 3 - (tight ? 6 : 8) - 3 - (tight ? 11.5 : 12.5) * 1.15,
    textDirection: Directionality.of(context),
    textScaler: TextScaler.noScaling,
  );
}

final class KeyBindingsKeyboard extends StatelessWidget {
  const KeyBindingsKeyboard({
    required this.index,
    required this.view,
    required this.unit,
    required this.onKey,
    required this.anchor,
    super.key,
  });
  final KeyBindingsIndex? index;
  final KeyboardViewState view;
  final double unit;
  final ValueChanged<String> onKey;
  final LayerLink anchor;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final layout = keyboardLayouts[view.size]!;
    final bound = index == null || view.quiet
        ? const <String, List<KeyBindingRef>>{}
        : index!.keysFor(
            scene: view.scene,
            layer: view.layer,
            query: view.query,
            allLayers: view.allLayers,
            strings: strings,
            onlyChanged: view.onlyChanged,
          );
    final fade = view.query.isNotEmpty;
    final fitters = <double, KeyCapFitter>{};
    return SizedBox(
      key: const Key('key-bindings-keyboard'),
      width: layout.width * unit,
      height: layout.height * unit,
      child: Stack(
        children: [
          for (final spec in layout.keys)
            Positioned(
              left: spec.x * unit + 1.5,
              top: spec.y * unit + 1.5,
              width: spec.width * unit - 3,
              height: spec.height * unit - 3,
              child: _KeyCap(
                spec: spec,
                refs: bound[spec.token] ?? const [],
                fitter: fitters.putIfAbsent(
                  spec.width * 10 + spec.height,
                  () => keyCapFitterFor(context, unit, spec.width, spec.height),
                ),
                view: view,
                tight: unit < 56,
                faded: fade && !bound.containsKey(spec.token),
                anchor: anchor,
                onTap: () => onKey(spec.token),
              ),
            ),
        ],
      ),
    );
  }
}

/// The action a key names: the player's own choice first, then one that fits.
KeyBindingRef _mainRef(
  List<KeyBindingRef> refs,
  KeyCapFitter fitter,
  AppStrings strings,
) {
  for (final ref in refs) {
    if (ref.entry.customized) return ref;
  }
  for (final ref in refs) {
    if (!fitter.resolve(strings, ref.action.name, ref.name).small) return ref;
  }
  return refs.first;
}

final class _KeyCap extends StatelessWidget {
  const _KeyCap({
    required this.spec,
    required this.refs,
    required this.fitter,
    required this.view,
    required this.tight,
    required this.faded,
    required this.anchor,
    required this.onTap,
  });
  final KeyCapSpec spec;
  final List<KeyBindingRef> refs;
  final KeyCapFitter fitter;
  final KeyboardViewState view;
  final bool tight, faded;
  final LayerLink anchor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.$key');
    final colors = context.tokens.colors;
    final on = refs.isNotEmpty;
    final changed = refs.any((r) => r.entry.customized);
    final shared =
        !changed &&
        refs.any((r) => matchingShortcut(r.entry, view.shortcuts) != null);
    final held = view.layer.split('+').contains(spec.token);
    final selected = view.selected == spec.token;
    final main = on ? _mainRef(refs, fitter, strings) : null;
    final via =
        main != null &&
            main.modifiers.isNotEmpty &&
            main.modifiers != view.layer
        ? main.modifiers
              .split('+')
              .map((m) => keyCapLegend(strings, m))
              .join('+')
        : null;
    final tag = changed
        ? t('tag.changed')
        : shared
        ? t('tag.shared')
        : via != null
        ? '$via +'
        : refs.length > 1
        ? t('tag.count').replaceFirst('{0}', '${refs.length}')
        : null;
    // A tag that would touch the key's own letter moves in front of the name.
    final tagInline =
        tag != null &&
        _width(
                  keyCapLegend(strings, spec.token),
                  tight ? 11.5 : 12.5,
                  fitter.style,
                ) +
                _width(tag, tight ? 9 : 10, fitter.style) +
                6 >
            fitter.width;
    final label = main == null
        ? null
        : fitter.resolve(
            strings,
            main.action.name,
            main.name,
            prefix: tagInline ? tag : null,
          );
    final edge = selected
        ? colors.focusRing
        : changed
        ? colors.warning
        : held || on
        ? colors.accent.withValues(alpha: held ? 1 : .68)
        : context.tokens.surfaces.panel.border;
    final hoverText = on
        ? refs.map((r) => r.name ?? r.action.name).toSet().join(' / ')
        : '';
    Widget cap = Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      label: [
        keyCapLegend(strings, spec.token),
        if (hoverText.isNotEmpty) hoverText,
        if (changed) t('tag.changed'),
      ].join(' '),
      child: ExcludeSemantics(
        // Ink paints on the nearest Material, and the shell's opaque page ground hides the app's.
        // The glow sits outside, since the ink layer clips to the key; fixed, painted
        // once: no blur that re-renders while the page idles.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.focusRing.withValues(alpha: .35),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: Key('key-cap-${spec.token}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: edge, width: selected ? 1.5 : 1),
                  gradient: on || held
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.alphaBlend(
                              colors.accent.withValues(
                                alpha: selected ? .3 : .1,
                              ),
                              colors.accentSoft,
                            ),
                            colors.accentSoft,
                          ],
                        )
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tight ? 5 : 6,
                    vertical: tight ? 3 : 4,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          keyCapLegend(strings, spec.token),
                          textScaler: TextScaler.noScaling,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: tight ? 11.5 : 12.5,
                            height: 1.15,
                            fontWeight: on || held
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: on || held
                                ? colors.textPrimary
                                : colors.textDisabled,
                          ),
                        ),
                      ),
                      if (tag != null && !tagInline)
                        Align(
                          alignment: Alignment.topRight,
                          child: Text(
                            tag,
                            textScaler: TextScaler.noScaling,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: tight ? 9 : 10,
                              height: 1.2,
                              color: changed || shared
                                  ? colors.warning
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      if (label != null)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: _CapLabel(
                            label: label,
                            fitter: fitter,
                            tag: tagInline ? tag : null,
                            tagColor: changed || shared
                                ? colors.warning
                                : colors.textSecondary,
                            color: selected
                                ? colors.textPrimary
                                : colors.accent,
                          ),
                        )
                      else if (held)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            t('tag.held'),
                            textScaler: TextScaler.noScaling,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: fitter.style.copyWith(color: colors.accent),
                          ),
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
    if (hoverText.isNotEmpty) {
      cap = StarBridgeTooltip(
        // An opened key's panel would sit under the hint, so hints wait until it closes.
        message: view.selected.isEmpty ? hoverText : '',
        waitDuration: Duration.zero,
        child: cap,
      );
    }
    if (selected) cap = CompositedTransformTarget(link: anchor, child: cap);
    return Opacity(opacity: faded ? .26 : 1, child: cap);
  }
}

double _width(String text, double size, TextStyle family) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: family.copyWith(fontSize: size, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

final class _CapLabel extends StatelessWidget {
  const _CapLabel({
    required this.label,
    required this.fitter,
    required this.color,
    this.tag,
    this.tagColor,
  });
  final KeyCapText label;
  final KeyCapFitter fitter;
  final Color color;
  final String? tag;
  final Color? tagColor;

  @override
  Widget build(BuildContext context) {
    final style = (label.small ? fitter.smallStyle : fitter.style).copyWith(
      color: color,
    );
    // Nothing we wrote fits: shrink the whole name into the room rather than cut it.
    if (!label.fits) {
      return SizedBox(
        width: fitter.width,
        height: fitter.height,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: SizedBox(
            width: fitter.width,
            child: Text.rich(
              TextSpan(
                children: [
                  if (tag != null)
                    TextSpan(
                      text: '$tag ',
                      style: TextStyle(color: tagColor),
                    ),
                  TextSpan(text: label.text),
                ],
              ),
              textScaler: TextScaler.noScaling,
              style: fitter.smallStyle.copyWith(color: color),
            ),
          ),
        ),
      );
    }
    if (tag case final tag?) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$tag ',
              style: TextStyle(color: tagColor),
            ),
            TextSpan(text: label.text),
          ],
        ),
        textScaler: TextScaler.noScaling,
        maxLines: 3,
        overflow: TextOverflow.clip,
        style: fitter.smallStyle.copyWith(color: color),
      );
    }
    return Text(
      label.text,
      textScaler: TextScaler.noScaling,
      maxLines: label.small ? 3 : 2,
      overflow: TextOverflow.clip,
      style: style,
    );
  }
}

/// Bound keys this keyboard does not have. Their actions must stay reachable.
final class KeyBindingsMissingKeys extends StatelessWidget {
  const KeyBindingsMissingKeys({
    required this.index,
    required this.view,
    required this.anchor,
    required this.onKey,
    super.key,
  });
  final KeyBindingsIndex index;
  final KeyboardViewState view;
  final LayerLink anchor;
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.$key');
    final tokens = context.tokens;
    final layout = keyboardLayouts[view.size]!;
    final bound = index.keysFor(
      scene: view.scene,
      layer: view.layer,
      query: view.query,
      allLayers: view.allLayers,
      strings: strings,
      onlyChanged: view.onlyChanged,
    );
    final missing = [
      for (final entry in bound.entries)
        if (!layout.tokens.contains(entry.key)) entry,
    ];
    if (missing.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('key-bindings-missing'),
      width: double.infinity,
      margin: EdgeInsets.only(top: tokens.space.sm),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.md,
        vertical: tokens.space.sm,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.accentSoft.withValues(alpha: .35),
        border: Border(left: BorderSide(color: tokens.colors.accent, width: 2)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            t('missing').replaceFirst('{0}', '${missing.length}'),
            style: TextStyle(color: tokens.colors.textSecondary, fontSize: 13),
          ),
          for (final entry in missing)
            _MissingKey(
              token: entry.key,
              name: entry.value.first.name ?? entry.value.first.action.name,
              selected: view.selected == entry.key,
              anchor: anchor,
              onTap: () => onKey(entry.key),
            ),
        ],
      ),
    );
  }
}

final class _MissingKey extends StatelessWidget {
  const _MissingKey({
    required this.token,
    required this.name,
    required this.selected,
    required this.anchor,
    required this.onTap,
  });
  final String token, name;
  final bool selected;
  final LayerLink anchor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final strings = AppStrings.of(context);
    // Ink paints on the nearest Material; the shell's opaque page ground sits above the app's,
    // so each painted control brings its own transparent one.
    Widget chip = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: Key('key-missing-$token'),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.accentSoft,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: selected
                  ? colors.focusRing
                  : colors.accent.withValues(alpha: .68),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${keyCapLegend(strings, token)}  ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: keyCapShortened(name),
                  style: TextStyle(color: colors.accent),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
    if (selected) chip = CompositedTransformTarget(link: anchor, child: chip);
    return chip;
  }
}

/// All the actions on one key, beside it. Scenes other than the chosen one stay
/// listed, because the question is what this key does.
final class KeyBindingsKeyPanel extends StatelessWidget {
  const KeyBindingsKeyPanel({
    required this.index,
    required this.keyToken,
    required this.layer,
    required this.scene,
    required this.shortcuts,
    required this.onClose,
    super.key,
  });
  final KeyBindingsIndex index;
  final String keyToken, layer, scene;
  final Set<String> shortcuts;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String t(String key) => strings.text('keyBindings.$key');
    final tokens = context.tokens;
    final secondary = TextStyle(
      color: tokens.colors.textSecondary,
      fontSize: 12,
    );
    final all = index.onKey(keyToken);
    final here = all.where((r) => r.modifiers == layer).toList();
    final other = all.where((r) => r.modifiers != layer).toList();
    bool inScene(KeyBindingRef r) =>
        KeyBindingsIndex.inScene(r.map.name, scene);
    final ordered = [...here.where(inScene), ...here.where((r) => !inScene(r))];
    String title(String modifiers) => [
      if (modifiers.isNotEmpty) ...modifiers.split('+'),
      keyToken,
    ].map((m) => keyCapLegend(strings, m)).join(' + ');
    return Material(
      key: const Key('key-bindings-key-panel'),
      color: tokens.surfaces.panel.fill,
      elevation: 4,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.colors.focusRing),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SizedBox(
          width: 366,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tokens.space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      title(layer),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        here.isEmpty
                            ? t('panel.none')
                            : t('panel.count')
                                  .replaceFirst('{0}', '${here.length}'),
                        style: secondary,
                      ),
                    ),
                    TextButton(
                      key: const Key('key-bindings-panel-close'),
                      onPressed: onClose,
                      child: Text(t('panel.close')),
                    ),
                  ],
                ),
                for (final ref in ordered)
                  Opacity(
                    opacity: inScene(ref) ? 1 : .62,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(ref.name ?? t('noName'))),
                              if (ref.entry.customized)
                                Text(
                                  t('panel.changed'),
                                  style: TextStyle(
                                    color: tokens.colors.warning,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            '${index.mapNames[ref.map.name] ?? ref.map.name}  ${ref.action.name}',
                            style: secondary,
                          ),
                          if (matchingShortcut(ref.entry, shortcuts)
                              case final shared?)
                            Text(
                              t('sharedShortcut').replaceFirst('{0}', shared),
                              style: TextStyle(
                                color: tokens.colors.warning,
                                fontSize: 12.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (other.isNotEmpty) ...[
                  Divider(height: 18, color: tokens.surfaces.panel.border),
                  Text(
                    t('panel.other'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  for (final ref in other)
                    Text(
                      '${title(ref.modifiers)}: ${ref.name ?? ref.action.name}',
                      style: secondary,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool isKeyBindingModifier(String token) => _modifierKeys.contains(token);
