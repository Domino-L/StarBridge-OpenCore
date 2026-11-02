import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_switch.dart';
import '../localization/app_strings.dart';
import 'menu_bridge_style.dart';
import 'menu_feature_view.dart';
import 'menu_hud_quick_view.dart';
import 'menu_tool_page.dart';
import 'menu_workspace_controller.dart';

/// Quick panel window: 640 wide, horizontally centred near the top on first
/// open. A moved or restored window keeps its own bounds.
MenuPanelSpec menuHudPanelSpec() => MenuPanelSpec(
  id: 'hud',
  initialBounds: const Rect.fromLTWH(320, 96, 640, 620),
  viewportBounds: (viewport) {
    final width = (viewport.width - 48).clamp(320.0, 640.0);
    final height = (viewport.height - 160).clamp(240.0, 620.0);
    return Rect.fromLTWH((viewport.width - width) / 2, 96, width, height);
  },
  minimumSize: const Size(320, 240),
);

/// Alt+M → 信息浮层. Every control sends an intent to the primary engine,
/// which owns the workspace; nothing is applied or saved in this engine.
class MenuHudQuickPanel extends StatefulWidget {
  const MenuHudQuickPanel({
    super.key,
    required this.view,
    required this.onAction,
  });
  final MenuFeatureView view;
  final void Function(String key, String value) onAction;

  @override
  State<MenuHudQuickPanel> createState() => _MenuHudQuickPanelState();
}

class _MenuHudQuickPanelState extends State<MenuHudQuickPanel> {
  bool _clientOpening = false, _clientFailed = false;

  /// Native hides the menu and raises the client once the primary engine
  /// accepts; only a refusal or timeout comes back here.
  Future<void> _openClient(MenuToolPageOpener opener) async {
    setState(() {
      _clientOpening = true;
      _clientFailed = false;
    });
    final opened = await opener.openHudSettings();
    if (!mounted) return;
    setState(() {
      _clientOpening = false;
      _clientFailed = !opened;
    });
  }

  /// Blue text link to the client's overlay page; absent without an opener.
  Widget? _clientLink(MenuBridgeColors ink, String key, String label) {
    final opener = MenuToolPageScope.of(context);
    if (opener == null) return null;
    return BridgeMenuAction(
      key: ValueKey(key),
      label: _t(label),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      onPressed: _clientOpening ? null : () => _openClient(opener),
      child: Text(
        _t(label),
        style: TextStyle(
          color: _clientOpening ? ink.muted : ink.blue,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _t(String key, [Map<String, String> args = const {}]) {
    var text = AppStrings.of(context).text(key);
    for (final entry in args.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  String _module(String key) => _t('menu.hudQuick.module.$key');

  @override
  Widget build(BuildContext context) {
    final ink = MenuBridgeColors.of(context);
    final view = widget.view;
    final quick = view.hudQuick;
    final on = view.hudEnabled == true;
    final busy = view.busy;
    const full = 'menu.hudQuick.fullSettings';
    return SingleChildScrollView(
      key: const ValueKey('menu-hud-quick'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _status(ink, on, busy, quick),
          if (view.notice.isNotEmpty) ...[
            const SizedBox(height: 8),
            BridgeCaption(view.notice, color: ink.amber),
          ],
          if (quick == null || !quick.available) ...[
            const SizedBox(height: 12),
            BridgeCaption(_t('menu.hudQuick.unavailable')),
            if (_clientLink(ink, 'menu-hud-quick-full-settings', full)
                case final link?)
              Align(alignment: Alignment.centerLeft, child: link),
          ] else ...[
            if (quick.dirty) _dirty(ink),
            if (quick.source case final source?) ...[
              _section(
                _t('menu.hudQuick.source'),
                _t('menu.hudQuick.sourceHelp'),
              ),
              _sourcePicker(ink, source),
            ],
            _section(
              _t('menu.hudQuick.presets'),
              _t('menu.hudQuick.presetsHelp'),
            ),
            _presets(ink, quick),
            _section(
              _t('menu.hudQuick.modules'),
              _t('menu.hudQuick.modulesHelp', {'preset': quick.presetName}),
            ),
            _modules(quick, on),
            const SizedBox(height: 16),
            _place(ink, quick, on),
          ],
          if (_clientFailed) ...[
            const SizedBox(height: 8),
            BridgeCaption(
              _t('menu.hudQuick.clientFailed'),
              key: const ValueKey('menu-hud-quick-client-failed'),
              color: ink.amber,
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: ink.divider),
          const SizedBox(height: 10),
          _footer(ink, quick?.note),
        ],
      ),
    );
  }

  Widget _status(
    MenuBridgeColors ink,
    bool on,
    bool busy,
    MenuHudQuickView? quick,
  ) => Container(
    key: const ValueKey('menu-hud-quick-status'),
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    decoration: BoxDecoration(
      color: ink.ground.withValues(alpha: .55),
      border: Border(
        left: BorderSide(color: on ? ink.green : ink.line, width: 2),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? ink.green : ink.line,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t(on ? 'menu.hudQuick.on' : 'menu.hudQuick.off'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              BridgeCaption(
                _t(on ? 'menu.hudQuick.onDetail' : 'menu.hudQuick.offDetail'),
              ),
              if (quick?.hotkey.isNotEmpty ?? false)
                BridgeCaption(
                  _t('menu.hudQuick.hotkey', {'key': quick!.hotkey}),
                ),
            ],
          ),
        ),
        StarBridgeSwitch(
          key: const ValueKey('menu-hud-quick-toggle'),
          value: on,
          label: _t('menu.hudQuick.toggle'),
          onChanged: busy || widget.view.hudEnabled == null
              ? null
              : (_) => widget.onAction('toggle', ''),
        ),
      ],
    ),
  );

  Widget _dirty(MenuBridgeColors ink) => Container(
    key: const ValueKey('menu-hud-quick-dirty'),
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: ink.amber.withValues(alpha: .08),
      border: Border(left: BorderSide(color: ink.amber, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _t('menu.hudQuick.dirtyTitle'),
                style: TextStyle(color: ink.amber, fontWeight: FontWeight.w700),
              ),
              TextSpan(text: _t('menu.hudQuick.dirtyBody')),
            ],
          ),
          style: const TextStyle(fontSize: 13, height: 1.55),
        ),
        ?_clientLink(
          ink,
          'menu-hud-quick-resolve-in-client',
          'menu.hudQuick.resolveInClient',
        ),
      ],
    ),
  );

  Widget _section(String title, String help) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        BridgeCaption(title),
        Text(
          help,
          style: TextStyle(
            fontSize: 12,
            color: MenuBridgeColors.of(context).line,
          ),
        ),
      ],
    ),
  );

  Widget _presets(MenuBridgeColors ink, MenuHudQuickView quick) =>
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          final columns = constraints.maxWidth >= 520 ? 5 : 3;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final preset in quick.presets)
                SizedBox(
                  width: width,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: preset.active
                          ? ink.selected
                          : ink.ground.withValues(alpha: .55),
                      border: Border(
                        top: BorderSide(
                          color: preset.active ? ink.blue : Colors.transparent,
                        ),
                      ),
                    ),
                    child: BridgeMenuAction(
                      key: ValueKey('menu-hud-quick-preset-${preset.id}'),
                      label: preset.name,
                      selected: preset.active,
                      padding: const EdgeInsets.fromLTRB(6, 9, 6, 8),
                      onPressed: !quick.editable || preset.active
                          ? null
                          : () => widget.onAction('preset', preset.id),
                      child: Column(
                        children: [
                          Text(
                            preset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: preset.active
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: !quick.editable && !preset.active
                                  ? ink.muted
                                  : null,
                            ),
                          ),
                          Text(
                            preset.bound.isEmpty
                                ? ' '
                                : _t('menu.hudQuick.bound', {
                                    'source': preset.bound,
                                  }),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: ink.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );

  // Every choice is visible; picking one is the remembered shared choice.
  // While the active plan fixes a source, the only action is to follow again.
  Widget _sourcePicker(
    MenuBridgeColors ink,
    ({
      String current,
      String label,
      String origin,
      bool canChange,
      List<MenuHudQuickSource> options,
    })
    source,
  ) {
    final fixed = source.origin == 'preset';
    final choices = source.options.where((o) => o.id != 'followShared');
    final follow = source.options.where((o) => o.id == 'followShared');
    return Column(
      key: const ValueKey('menu-hud-quick-source'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fixed) ...[
          BridgeCaption(
            _t('menu.hudQuick.planFixedNote', {'source': source.label}),
            color: ink.amber,
          ),
          for (final option in follow)
            Align(
              alignment: Alignment.centerLeft,
              child: BridgeMenuAction(
                key: const ValueKey('menu-hud-quick-source-follow'),
                label: option.label,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                onPressed: source.canChange
                    ? () => widget.onAction('source', option.id)
                    : null,
                child: Text(
                  option.label,
                  style: TextStyle(color: ink.blue, fontSize: 13),
                ),
              ),
            ),
          const SizedBox(height: 6),
        ],
        for (final option in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: !fixed && option.id == source.current
                    ? ink.blue.withValues(alpha: .16)
                    : ink.ground.withValues(alpha: .55),
                border: Border(
                  left: BorderSide(
                    width: 2,
                    color: !fixed && option.id == source.current
                        ? ink.blue
                        : Colors.transparent,
                  ),
                ),
              ),
              child: BridgeMenuAction(
                key: ValueKey('menu-hud-quick-source-${option.id}'),
                label: option.label,
                selected: !fixed && option.id == source.current,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                onPressed:
                    !option.enabled ||
                        !source.canChange ||
                        option.id == source.current
                    ? null
                    : () => widget.onAction('source', option.id),
                child: Row(
                  children: [
                    Text(
                      !fixed && option.id == source.current ? '◉' : '○',
                      style: TextStyle(
                        color: !fixed && option.id == source.current
                            ? ink.blue
                            : ink.muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        option.id == 'auto' &&
                                !fixed &&
                                source.current == 'auto'
                            ? source.label
                            : option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: option.enabled ? null : ink.line,
                          fontWeight: !fixed && option.id == source.current
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        BridgeCaption(_t('menu.hudQuick.sourceNote')),
      ],
    );
  }

  Widget _modules(MenuHudQuickView quick, bool on) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 520 ? 3 : 2;
      final width = (constraints.maxWidth - 18 * (columns - 1)) / columns;
      return Wrap(
        spacing: 18,
        children: [
          for (final key in menuHudQuickModules)
            if (quick.modules[key] case final bool visible)
              SizedBox(
                width: width,
                child: StarBridgeSwitch.tile(
                  key: ValueKey('menu-hud-quick-module-$key'),
                  value: visible,
                  label: _t('menu.hudQuick.show', {'module': _module(key)}),
                  titleWidget: Text(_module(key)),
                  onChanged: quick.editable && on
                      ? (_) => widget.onAction('module', key)
                      : null,
                ),
              ),
        ],
      );
    },
  );

  Widget _place(MenuBridgeColors ink, MenuHudQuickView quick, bool on) {
    final reason = !on
        ? _t('menu.hudQuick.placeOff')
        : quick.dirty
        ? _t('menu.hudQuick.placeDirty')
        : '';
    final enabled = on && quick.editable;
    final full = _clientLink(
      ink,
      'menu-hud-quick-full-settings',
      'menu.hudQuick.fullSettings',
    );
    final row = Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: enabled ? ink.blue : ink.divider),
          child: BridgeMenuAction(
            key: const ValueKey('menu-hud-quick-place'),
            label: _t('menu.hudQuick.place'),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            onPressed: enabled ? () => widget.onAction('placeBegin', '') : null,
            child: Text(
              _t('menu.hudQuick.place'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: enabled ? BridgeInk.onAccent : ink.muted,
              ),
            ),
          ),
        ),
        if (reason.isNotEmpty) BridgeCaption(reason),
      ],
    );
    if (full == null) return row;
    return Row(
      children: [
        Expanded(child: row),
        const SizedBox(width: 12),
        full,
      ],
    );
  }

  Widget _footer(MenuBridgeColors ink, MenuHudQuickNote? note) {
    if (note == null) {
      // With a working link the page name would only repeat it.
      final linked = MenuToolPageScope.of(context) != null;
      return BridgeCaption(
        _t(linked ? 'menu.hudQuick.footerLinked' : 'menu.hudQuick.footer'),
      );
    }
    final args = {
      ...note.args,
      if (note.args['module'] case final String module)
        'module': _module(module),
    };
    return Semantics(
      liveRegion: true,
      child: Wrap(
        key: const ValueKey('menu-hud-quick-note'),
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (note.ok) Text('✓', style: TextStyle(color: ink.green)),
          Text(
            _t('menu.hudQuick.note.${note.kind}', args),
            style: TextStyle(fontSize: 13, color: note.ok ? null : ink.amber),
          ),
          if (note.undo)
            BridgeMenuAction(
              key: const ValueKey('menu-hud-quick-undo'),
              label: _t('menu.hudQuick.undo'),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              onPressed: widget.view.busy
                  ? null
                  : () => widget.onAction('undo', ''),
              child: Text(
                _t('menu.hudQuick.undo'),
                style: TextStyle(color: ink.blue, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
