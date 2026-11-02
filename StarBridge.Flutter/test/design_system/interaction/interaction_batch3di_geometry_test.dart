import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/surfaces/starbridge_surface.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/settings/help_support_disclosure.dart';
import 'package:starbridge_flutter/features/settings/help_support_expansion_tile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

// Literal pre-3di card fixture: compare public native geometry, not screenshots
// of an isolated lab component. No product/business code imports this fixture.
Widget nativeCard(BuildContext context, bool open) {
  final tokens = context.tokens;
  final strings = AppStrings.of(context);
  return StarBridgeSurface(
    role: SurfaceRole.panel,
    padding: EdgeInsets.zero,
    child: Material(
      color: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: open,
          tilePadding: EdgeInsets.symmetric(
            horizontal: tokens.space.md,
            vertical: tokens.space.xxs,
          ),
          childrenPadding: EdgeInsetsDirectional.fromSTEB(
            tokens.space.md,
            0,
            tokens.space.md,
            tokens.space.md,
          ),
          leading: Container(
            width: 4,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.cyan,
              borderRadius: tokens.shape.small,
            ),
          ),
          title: Text(
            strings.text('help.log.catalog'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          trailing: StarBridgeIcon(
            StarBridgeIconSemantic.menuDown,
            size: tokens.icons.small,
            color: tokens.colors.textSecondary,
          ),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                strings.text('help.log.troubleshoot.body'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.colors.textSecondary,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const title = 'v0.0.0 · A longer release title for wrapping at narrow widths';
const date = '2026-10-16';
const body = 'Release summary';
Widget release(BuildContext context, bool adapted, bool open) {
  final padding = EdgeInsets.all(context.tokens.space.md);
  const children = [
    Text(body),
    Padding(padding: EdgeInsets.only(top: 8), child: Text('• One highlight')),
  ];
  return Material(
    color: Colors.transparent,
    child: adapted
        ? HelpSupportExpansionTile(
            title: const Text(title),
            subtitle: const Text(date),
            initiallyExpanded: open,
            childrenPadding: padding,
            childrenCrossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          )
        : ExpansionTile(
            title: const Text(title),
            subtitle: const Text(date),
            initiallyExpanded: open,
            childrenPadding: padding,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
  );
}

List<Rect> geometry(WidgetTester t, Finder host, bool open, bool card) {
  final tile = find.descendant(of: host, matching: find.byType(ListTile)).first;
  final widget = t.widget<ListTile>(tile);
  return [
    t.getRect(host),
    t.getRect(tile),
    t.getRect(find.byWidget(widget.title!)),
    t.getRect(find.byWidget(widget.trailing!)),
    if (widget.leading != null) t.getRect(find.byWidget(widget.leading!)),
    if (widget.subtitle != null) t.getRect(find.byWidget(widget.subtitle!)),
    if (open)
      t.getRect(
        card
            ? find.descendant(of: host, matching: find.byType(Text)).last
            : find.descendant(of: host, matching: find.text(body)),
      ),
  ];
}

List<Color?> titleColors(WidgetTester t, Finder host) {
  final tile = t.widget<ListTile>(
    find.descendant(of: host, matching: find.byType(ListTile)).first,
  );
  return [
    for (final content in [
      tile.title,
      if (tile.subtitle != null) tile.subtitle,
    ])
      t
          .widget<RichText>(
            find
                .descendant(
                  of: find.byWidget(content!),
                  matching: find.byType(RichText),
                )
                .first,
          )
          .text
          .style
          ?.color,
  ];
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3di');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final dense in [false, true]) {
          for (final card in [false, true]) {
            testWidgets(
              '$suite light=$light scale=$scale dense=$dense card=$card native rectangles',
              (t) async {
                size(t, const Size(420, 1600));
                for (final open in [false, true]) {
                  List<Rect>? original;
                  List<Color?>? originalColors;
                  for (final adapted in [false, true]) {
                    final frame = GlobalKey();
                    await t.pumpWidget(
                      scopedApp(
                        Builder(
                          builder: (context) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(textScaler: TextScaler.linear(scale)),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                listTileTheme: ListTileThemeData(dense: dense),
                              ),
                              child: SingleChildScrollView(
                                child: RepaintBoundary(
                                  key: frame,
                                  child: Builder(
                                    builder: (context) => ColoredBox(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface,
                                      child: card
                                          ? (adapted
                                                ? HelpSupportDisclosureCard(
                                                    titleKey:
                                                        'help.log.catalog',
                                                    bodyKey: 'help.log.troubleshoot.body',
                                                    accent: Colors.cyan,
                                                    initiallyExpanded: open,
                                                  )
                                                : nativeCard(context, open))
                                          : release(context, adapted, open),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        suite,
                        light: light,
                      ),
                    );
                    await t.pumpAndSettle();
                    expect(t.takeException(), isNull);
                    final current = geometry(t, find.byKey(frame), open, card);
                    if (!adapted) {
                      original = current;
                      originalColors = titleColors(t, find.byKey(frame));
                    } else {
                      expect(
                        titleColors(t, find.byKey(frame)),
                        originalColors,
                        reason: 'Retain native Material 3 title/date colors',
                      );
                      expect(
                        current,
                        original,
                        reason: 'Retain the original native header/body bounds',
                      );
                      if (!dense) {
                        await capture(
                          t,
                          frame,
                          '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}-${card ? 'card' : 'release'}-${open ? 'open' : 'closed'}',
                        );
                      }
                    }
                    await t.pumpWidget(const SizedBox());
                  }
                }
              },
            );
          }
        }
      }
    }
  }
}
