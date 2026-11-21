import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import 'key_bindings_devices.dart';
import 'key_bindings_index.dart';
import 'key_bindings_keyboard.dart';
import 'key_bindings_list.dart';
import 'key_bindings_layouts.dart';
import 'key_bindings_names.dart';
import 'key_bindings_port.dart';
import 'key_bindings_split.dart';

const keyBindingsRoute = '/tools/key-bindings';

/// Shows the player's key bindings on a keyboard, with a list that follows it.
/// The files are read when the page opens or the player asks again; nothing here
/// polls or animates, so it costs nothing while it sits open.
final class KeyBindingsPage extends StatefulWidget {
  const KeyBindingsPage({super.key, this.port, this.shortcuts, this.onBack});
  final KeyBindingsPort? port;

  /// StarBridge's own shortcuts, for the line saying two programs share a key.
  final Future<Set<String>> Function()? shortcuts;
  final VoidCallback? onBack;

  @override
  State<KeyBindingsPage> createState() => _KeyBindingsPageState();
}

final class _KeyBindingsPageState extends State<KeyBindingsPage> {
  final _search = TextEditingController();
  final _anchor = LayerLink();
  final _panel = OverlayPortalController();
  String _channel = 'LIVE';
  String _device = 'keyboard';
  String _scene = 'flight';
  String _layer = '';
  String _gamepadLayer = '';
  String _selected = '';
  int _stick = 1;
  KeyBindingsSnapshot? _snapshot;
  KeyBindingsIndex? _index;
  Set<String> _shortcuts = const {};
  bool _busy = false, _failed = false, _onlyChanged = false;
  int _request = 0;
  String? _language;
  KeyBindingsKeyboardSize? _size;
  bool _manySideButtons = false;
  // the wished list height (a resize only clamps what shows); measured parts below
  double _lowerHeight = 476, _topHeight = 230, _between = 108, _toolbar = 52;

  bool _lowerOpen = true, _helpOpen = false;

  /// The chosen names language folder; null follows the interface.
  String? _localization;
  // The first answer sets the remembered view; later ones must not undo a choice.
  bool _viewApplied = false;
  // Saves wait for the saved view, so they never write defaults over it; what the
  // player chose meanwhile wins over it and is saved once it arrives.
  bool _loaded = false;
  final _chosen = <String>{};

  String t(String key) => AppStrings.of(context).text('keyBindings.$key');

  @override
  void initState() {
    super.initState();
    unawaited(_readShortcuts());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = keyBindingLanguage(AppStrings.of(context));
    if (language == _language) return;
    _language = language;
    // Names come with the answer, so a new interface language reads again.
    scheduleMicrotask(() {
      if (mounted) unawaited(_read());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _readShortcuts() async {
    try {
      final shortcuts = await widget.shortcuts?.call();
      if (mounted && shortcuts != null) setState(() => _shortcuts = shortcuts);
    } on Object {
      // The line is a convenience; the keys do not depend on it.
    }
  }

  Future<void> _read() async {
    final port = widget.port;
    final language = _language;
    if (port == null || language == null) return;
    final request = ++_request;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final snapshot = await port.read(
        _channel,
        language,
        localization: _localization,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _snapshot = snapshot;
        _index = KeyBindingsIndex(AppStrings.of(context), snapshot);
        _busy = false;
        _applyView(snapshot.view);
        if (!_loaded && _chosen.isNotEmpty) unawaited(_remember(null, true));
        _loaded = true;
      });
    } on Object {
      if (!mounted || request != _request) return;
      setState(() {
        _snapshot = null;
        _index = null;
        _busy = false;
        _failed = true;
      });
    }
  }

  void _applyView(KeyBindingsView? view) {
    if (_viewApplied || view == null) return;
    _viewApplied = true;
    bool keep(String field) => !_chosen.contains(field);
    if (keep('keyboard')) {
      _size = KeyBindingsKeyboardSize.values
          .where((s) => s.name == view.keyboard)
          .firstOrNull;
    }
    if (keep('mouse')) _manySideButtons = view.mouse == 'many';
    final height = view.listHeight?.toDouble();
    if (keep('listHeight') && height != null) _lowerHeight = height;
    if (keep('listOpen')) _lowerOpen = view.listOpen ?? _lowerOpen;
    if (keep('notesOpen')) _helpOpen = view.notesOpen ?? _helpOpen;
    // A search under way keeps its list in sight.
    if (_search.text.isNotEmpty) _lowerOpen = true;
    // Applied for the next read; this one already used the default.
    if (view.localization != null &&
        _localization == null &&
        keep('localization')) {
      _localization = view.localization;
      scheduleMicrotask(() {
        if (mounted) unawaited(_read());
      });
    }
  }

  // One save at a time, each with the whole view as it is when it runs.
  Future<void> _saving = Future.value();
  bool _saveFailed = false;

  // The keyboard size only when the player chose one; otherwise the width picks it.
  Future<void> _remember(String? field, [bool flush = false]) {
    if (field != null) _chosen.add(field);
    if (!_loaded && !flush) return Future.value();
    return _saving = _saving.then((_) async {
      try {
        await widget.port?.saveView(
          KeyBindingsView(
            keyboard: _size?.name,
            mouse: _manySideButtons ? 'many' : 'standard',
            localization: _localization,
            listHeight: _lowerHeight.clamp(160.0, 4000.0).round(),
            listOpen: _lowerOpen,
            notesOpen: _helpOpen,
          ),
        );
        if (mounted && _saveFailed) setState(() => _saveFailed = false);
      } on Object {
        // The choice still holds for this visit; say it will not be remembered.
        if (mounted) setState(() => _saveFailed = true);
      }
    });
  }

  void _switchChannel(String channel) {
    if (channel == _channel) return;
    setState(() {
      _channel = channel;
      _snapshot = null;
      _index = null;
      _close();
    });
    unawaited(_read());
  }

  void _close() {
    _selected = '';
    if (_panel.isShowing) _panel.hide();
  }

  void _openKey(String token) {
    final index = _index;
    setState(() {
      if (isKeyBindingModifier(token) &&
          (index?.layerCounts(_scene)[token] ?? 0) > 0) {
        _layer = _layer == token ? '' : token;
        _close();
        return;
      }
      if (_selected == token) {
        _close();
        return;
      }
      _selected = token;
      if (!_panel.isShowing) _panel.show();
    });
  }

  void _openRow(KeyBindingRef ref) {
    if (_device != 'keyboard' || ref.isMouse) return;
    setState(() {
      _layer = ref.modifiers;
      _selected = ref.key;
      if (!_panel.isShowing) _panel.show();
    });
  }

  /// A read that yields no keys of the player's says why, over a quiet keyboard.
  String? _blocking(KeyBindingsSnapshot? snapshot) {
    if (widget.port == null) return t('unavailable');
    if (_failed) return t('failed');
    return switch (snapshot?.state) {
      'notInstalled' => t('state.notInstalled'),
      'multiple' => t('state.multiple'),
      'unreadable' => t('state.unreadable'),
      'format' => t('state.format'),
      _ => null,
    };
  }

  String? _note(KeyBindingsSnapshot? snapshot) {
    if (snapshot == null) return null;
    final hasDefaults = snapshot.defaultsVersion != null;
    return switch (snapshot.state) {
      'ok' when snapshot.maps.isEmpty => t('state.empty'),
      'noFile' => t(hasDefaults ? 'state.noFileDefaults' : 'state.noFile'),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    final snapshot = _snapshot;
    final index = _index;
    final secondary = TextStyle(color: tokens.colors.textSecondary);
    final query = KeyBindingsIndex.squash(_search.text);
    final version = snapshot?.defaultsVersion;
    final blocking = _blocking(snapshot);
    final note = _note(snapshot);
    return LoadingContentProbe(
      route: keyBindingsRoute,
      status: widget.port == null
          ? LoadingContentStatus.unavailable
          : _failed
          ? LoadingContentStatus.failed
          : snapshot == null
          ? LoadingContentStatus.waiting
          : snapshot.maps.isEmpty
          ? LoadingContentStatus.empty
          : LoadingContentStatus.data,
      items: snapshot?.maps.length ?? 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth - tokens.space.lg * 2;
          final size = _size ?? defaultKeyboardSize(width);
          final layout = keyboardLayouts[size]!;
          final across = width / layout.width;
          final view = KeyboardViewState(
            size: size,
            scene: _scene,
            layer: _layer,
            query: query,
            allLayers: index != null && !index.hasDefaults,
            selected: _selected,
            shortcuts: _shortcuts,
            quiet: blocking != null,
            onlyChanged: _onlyChanged,
          );
          final keyboard = _device == 'keyboard';
          final chrome = _toolbar + tokens.space.xs;
          final (:most, :least, :lower, :unit) = keyBindingsRoom(
            window: constraints.maxHeight,
            above: tokens.space.lg * 2 + _topHeight,
            across: across,
            rows: layout.height,
            list: _lowerOpen ? _lowerHeight : null,
            keyboard: keyboard,
            between: _between,
            chrome: chrome,
            folded: _toolbar,
          );
          double to(double by) =>
              keyBindingsResized(_lowerHeight, by, least, most);
          return SingleChildScrollView(
            padding: EdgeInsets.all(tokens.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyBindingsMeasured(
                  onHeight: (height) => setState(() => _topHeight = height),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(strings, version, snapshot, secondary),
                      SizedBox(height: tokens.space.md),
                      Wrap(
                        spacing: tokens.space.lg,
                        runSpacing: tokens.space.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          keyBindingsChoices(
                            'device',
                            [
                              for (final device in const [
                                'keyboard',
                                'mouse',
                                'gamepad',
                                'stick',
                              ])
                                (device, t('tab.$device'), true),
                            ],
                            _device,
                            (value) => setState(() {
                              _device = value;
                              _close();
                            }),
                          ),
                          keyBindingsChoices(
                            'scene',
                            [
                              for (final scene in keyBindingScenes)
                                (scene, t('scene.$scene'), true),
                            ],
                            _scene,
                            (value) => setState(() {
                              _scene = value;
                              _close();
                            }),
                          ),
                        ],
                      ),
                      SizedBox(height: tokens.space.sm),
                      Divider(height: 1, color: tokens.surfaces.panel.border),
                      SizedBox(height: tokens.space.sm),
                      _stageControls(index, size, secondary),
                      SizedBox(height: tokens.space.sm),
                      if (note != null) ...[
                        Text(
                          note,
                          key: const Key('key-bindings-state'),
                          style: secondary,
                        ),
                        SizedBox(height: tokens.space.sm),
                      ],
                    ],
                  ),
                ),
                _stage(index, view, unit, blocking),
                keyBindingsBetween(
                  (height) => setState(() => _between = height),
                  [
                    if (keyboard && index != null && blocking == null)
                      KeyBindingsMissingKeys(
                        index: index,
                        view: view,
                        anchor: _anchor,
                        onKey: _openKey,
                      ),
                    if (keyboard) ...[
                      SizedBox(height: tokens.space.sm),
                      KeyBindingsLegend(
                        style: secondary.copyWith(fontSize: 12.5),
                      ),
                    ],
                    KeyBindingsSplitter(
                      open: _lowerOpen,
                      onToggle: () {
                        setState(() => _lowerOpen = !_lowerOpen);
                        unawaited(_remember('listOpen'));
                      },
                      onResize: (by) => setState(() => _lowerHeight = to(by)),
                      onSettled: () => unawaited(_remember('listHeight')),
                    ),
                  ],
                ),
                KeyBindingsLower(
                  index: index,
                  snapshot: snapshot,
                  query: query,
                  scene: _scene,
                  device: switch (_device) {
                    'gamepad' => 'gamepad',
                    'stick' => 'joystick',
                    _ => 'keyboardMouse',
                  },
                  mouse: switch (_device) {
                    'keyboard' => false,
                    'mouse' => true,
                    _ => null,
                  },
                  instance: _device == 'stick' ? _stick : null,
                  onlyChanged: _onlyChanged,
                  blocked: blocking != null,
                  search: _search,
                  onSearch: () => setState(() {
                    _close();
                    if (_search.text.isNotEmpty) _lowerOpen = true;
                  }),
                  onOnlyChanged: (value) =>
                      setState(() => _onlyChanged = value),
                  onOpen: _openRow,
                  width: width,
                  listHeight: _lowerOpen ? lower - chrome : null,
                  chrome: chrome,
                  onToolbarHeight: (h) => setState(() => _toolbar = h),
                  helpOpen: _helpOpen,
                  onHelp: () {
                    setState(() {
                      _helpOpen = !_helpOpen;
                      // The notes sit beside the list, so they bring it back.
                      if (_helpOpen) _lowerOpen = true;
                    });
                    if (_helpOpen) _chosen.add('listOpen');
                    unawaited(_remember('notesOpen'));
                  },
                ),
                OverlayPortal(
                  controller: _panel,
                  overlayChildBuilder: (_) => index == null || _selected.isEmpty
                      ? const SizedBox.shrink()
                      : KeyBindingsKeyPopover(
                          link: _anchor,
                          size: view.size,
                          keyToken: _selected,
                          unit: unit,
                          child: KeyBindingsKeyPanel(
                            index: index,
                            keyToken: _selected,
                            layer: _layer,
                            scene: _scene,
                            shortcuts: _shortcuts,
                            onClose: () => setState(_close),
                          ),
                        ),
                  child: const SizedBox.shrink(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header(
    AppStrings strings,
    String? version,
    KeyBindingsSnapshot? snapshot,
    TextStyle secondary,
  ) {
    final small = secondary.copyWith(fontSize: 12);
    final names = switch (snapshot?.namesState) {
      'ok' => t('notice.playerNames'),
      'bundled' => t(
        'notice.bundledNames',
      ).replaceFirst('{version}', version ?? ''),
      _ => t('notice.ownNames'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onBack != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: widget.onBack,
              icon: const StandardIcon(
                StandardIconSemantic.arrowBack,
                size: 18,
              ),
              label: Text(strings.text('tools.back')),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(t('description'), style: secondary),
                ],
              ),
            ),
            const SizedBox(width: 16),
            keyBindingsChoices(
              'channel',
              [
                for (final channel in const ['LIVE', 'PTU'])
                  (channel, strings.text('gameLog.$channel'), true),
              ],
              _channel,
              _switchChannel,
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: const Key('key-bindings-reload'),
              onPressed: _busy || widget.port == null ? null : _read,
              child: Text(t(_busy ? 'reading' : 'reload')),
            ),
          ],
        ),
        // Shown while a choice exists even where nothing is listed, so it can be cleared.
        if (snapshot != null &&
            (snapshot.localizations.isNotEmpty ||
                _localization != null ||
                snapshot.localizationFallback)) ...[
          const SizedBox(height: 8),
          _namesLanguage(snapshot, small),
        ],
        const SizedBox(height: 8),
        Text(
          [
            if (version != null)
              t(
                'notice.full',
              ).replaceFirst('{version}', snapshot?.defaultsRelease ?? version)
            else
              t('notice.changedOnly'),
            if (version != null && _channel != 'LIVE') t('notice.otherVersion'),
            names,
            t('notice.refresh'),
          ].join(' '),
          key: const Key('key-bindings-notice'),
          style: small,
        ),
      ],
    );
  }

  Widget _namesLanguage(KeyBindingsSnapshot snapshot, TextStyle small) {
    final follow = t('localization.follow');
    final options = [
      StarBridgeSelectOption<String>(value: '', label: follow),
      for (final folder in snapshot.localizations)
        StarBridgeSelectOption<String>(
          value: folder,
          label: keyBindingLocalizationName(folder),
        ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(t('localization.label'), style: small),
        SizedBox(
          width: 220,
          child: StarBridgeCompactSelect<String>(
            identity: 'key-bindings-localization',
            controlKey: const Key('key-bindings-localization'),
            semanticLabel: t('localization.label'),
            isDense: true,
            options: options,
            value: snapshot.localizationFallback ? '' : _localization ?? '',
            onSelected: (value, _) {
              setState(() => _localization = value.isEmpty ? null : value);
              unawaited(_remember('localization'));
              unawaited(_read());
            },
          ),
        ),
        if (snapshot.localizationFallback && _localization != null)
          Text(
            t(
              'localization.missing',
            ).replaceFirst('{0}', keyBindingLocalizationName(_localization!)),
            key: const Key('key-bindings-localization-missing'),
            style: small.copyWith(color: context.tokens.colors.warning),
          ),
      ],
    );
  }

  Widget _stageControls(
    KeyBindingsIndex? index,
    KeyBindingsKeyboardSize size,
    TextStyle secondary,
  ) {
    final label = secondary.copyWith(fontSize: 12.5);
    final counts = index?.layerCounts(_scene) ?? const <String, int>{};
    Widget labelled(String text, Widget child) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: label),
        const SizedBox(width: 8),
        child,
      ],
    );
    String layerName(String layer, int count) {
      final name = keyCapLegend(AppStrings.of(context), layer);
      return count > 0 ? '$name $count' : name;
    }

    final left = switch (_device) {
      'keyboard' => labelled(
        t('hold'),
        keyBindingsChoices(
          'layer',
          [
            ('', t('holdNone'), true),
            for (final layer in const ['lalt', 'ralt', 'lctrl', 'lshift'])
              (
                layer,
                layerName(layer, counts[layer] ?? 0),
                (counts[layer] ?? 0) > 0,
              ),
          ],
          _layer,
          (value) => setState(() {
            _layer = value;
            _close();
          }),
        ),
      ),
      'mouse' => labelled(
        t('hold'),
        keyBindingsChoices(
          'mouse-layer',
          [
            ('', t('holdNone'), true),
            ('lalt', layerName('lalt', 0), true),
            ('ralt', layerName('ralt', 0), true),
          ],
          _layer,
          (value) => setState(() => _layer = value),
        ),
      ),
      'gamepad' => labelled(
        t('hold'),
        keyBindingsChoices(
          'gamepad-layer',
          [('', t('holdNone'), true), ('shoulderl', t('device.bumperL'), true)],
          _gamepadLayer,
          (value) => setState(() => _gamepadLayer = value),
        ),
      ),
      _ => keyBindingsChoices(
        'stick',
        [
          for (final n in const [1, 2])
            ('$n', t('device.stickNumber').replaceFirst('{0}', '$n'), true),
        ],
        '$_stick',
        (value) => setState(() => _stick = int.parse(value)),
      ),
    };
    final right = switch (_device) {
      'keyboard' => labelled(
        t('keyboardSize'),
        keyBindingsChoices(
          'size',
          [
            for (final option in KeyBindingsKeyboardSize.values)
              (option.name, t('size.${option.name}'), true),
          ],
          size.name,
          (value) {
            final chosen = KeyBindingsKeyboardSize.values.byName(value);
            setState(() {
              _size = chosen;
              _close();
            });
            unawaited(_remember('keyboard'));
          },
        ),
      ),
      'mouse' => labelled(
        t('mouseStyle'),
        keyBindingsChoices(
          'mouse-style',
          [
            ('standard', t('mouse.standard'), true),
            ('many', t('mouse.many'), true),
          ],
          _manySideButtons ? 'many' : 'standard',
          (value) {
            setState(() {
              _manySideButtons = value == 'many';
            });
            unawaited(_remember('mouse'));
          },
        ),
      ),
      'gamepad' => Text(t('device.gamepadNote'), style: label),
      _ => Text(t('device.stickNote'), style: label),
    };
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 8,
      spacing: 16,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        left,
        right,
        if (_saveFailed)
          Text(
            t('saveFailed'),
            key: const Key('key-bindings-save-failed'),
            style: label.copyWith(color: context.tokens.colors.warning),
          ),
      ],
    );
  }

  Widget _stage(
    KeyBindingsIndex? index,
    KeyboardViewState view,
    double unit,
    String? blocking,
  ) {
    final tokens = context.tokens;
    final Widget stage = _device == 'keyboard'
        ? Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: KeyBindingsScaledKeyboard(
                size: view.size,
                unit: unit,
                builder: (unit) => KeyBindingsKeyboard(
                  index: index,
                  view: view,
                  unit: unit,
                  onKey: _openKey,
                  anchor: _anchor,
                ),
              ),
            ),
          )
        : KeyBindingsDeviceStage(
            device: switch (_device) {
              'mouse' => KeyBindingsDevice.mouse,
              'gamepad' => KeyBindingsDevice.gamepad,
              _ => KeyBindingsDevice.stick,
            },
            index: blocking == null ? index : null,
            scene: _scene,
            layer: _device == 'gamepad' ? _gamepadLayer : _layer,
            manySideButtons: _manySideButtons,
            stick: _stick,
            query: view.query,
            strings: AppStrings.of(context),
            onlyChanged: _onlyChanged,
          );
    if (blocking == null) return stage;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: .3, child: IgnorePointer(child: stage)),
        Container(
          key: Key(_failed ? 'key-bindings-failed' : 'key-bindings-state'),
          constraints: const BoxConstraints(maxWidth: 480),
          padding: EdgeInsets.all(tokens.space.md),
          color: tokens.surfaces.panel.fill,
          child: Text(blocking, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
