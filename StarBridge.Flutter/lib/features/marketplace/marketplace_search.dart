import '../../design_system/icons/marketplace_icon.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'marketplace_controller.dart';
import 'marketplace_copy.dart';
import 'marketplace_port.dart';
import 'marketplace_widgets.dart';

List<String> marketSearchTerms(
  List<MarketRow> rows,
  String query,
  String locale,
) {
  final result = <String>[];
  for (final row in rows) {
    final name = marketName(row, locale);
    final term = name.split(RegExp(r'[（(\[【]')).first.trim();
    if (term.isNotEmpty &&
        term.toLowerCase().contains(query.trim().toLowerCase()) &&
        !result.contains(term)) {
      result.add(term);
    }
  }
  result.sort(
    (a, b) => (a.toLowerCase().startsWith(query.toLowerCase()) ? 0 : 1)
        .compareTo(b.toLowerCase().startsWith(query.toLowerCase()) ? 0 : 1),
  );
  return result.take(3).toList();
}

class MarketplaceSearch extends StatefulWidget {
  const MarketplaceSearch(
    this.controller,
    this.text,
    this.focus, {
    this.onSearched,
    super.key,
  });
  final MarketplaceController controller;
  final TextEditingController text;
  final FocusNode focus;

  /// A search was really submitted (a term or an item chosen), not typed.
  final VoidCallback? onSearched;
  @override
  State<MarketplaceSearch> createState() => _SearchState();
}

class _SearchState extends State<MarketplaceSearch> {
  final _portal = OverlayPortalController(), _link = LayerLink();
  Timer? _debounce, _priceTimer;
  int _epoch = 0, _selected = -1;
  String _query = '';
  TextEditingValue? _lastValue;
  List<MarketRow> _items = [];
  List<String> _terms = [], _hot = [];
  num? _price;
  bool _failed = false,
      _loading = false,
      _hotAttempted = false,
      _closed = false;
  MarketplaceController get c => widget.controller;
  String get language => marketLocale(context);
  String tr(String cn, String en) => language == 'en' ? en : cn;
  @override
  void initState() {
    super.initState();
    widget.text.addListener(_changed);
    widget.focus.addListener(_focusChanged);
    widget.focus.onKeyEvent = _key;
  }

  @override
  void dispose() {
    _epoch++;
    _debounce?.cancel();
    _priceTimer?.cancel();
    widget.text.removeListener(_changed);
    widget.focus.removeListener(_focusChanged);
    widget.focus.onKeyEvent = null;
    super.dispose();
  }

  void _focusChanged() {
    if (widget.focus.hasFocus) {
      _closed = false;
      _portal.show();
      _loadHot();
      if (widget.text.text.isNotEmpty) {
        _lastValue = null;
        _changed();
      }
    } else {
      _portal.hide();
      _priceTimer?.cancel();
      _epoch++;
    }
  }

  Future<void> _loadHot() async {
    if (_hotAttempted) return;
    _hotAttempted = true;
    try {
      final result = await c.port.read('hotWords');
      if (mounted) {
        setState(
          () => _hot = result.rows
              .map((r) => marketName(r, language))
              .where((s) => s.isNotEmpty)
              .take(10)
              .toList(),
        );
      }
    } on Object {
      /* Optional hot words never block search. */
    }
  }

  void _changed() {
    final value = widget.text.value;
    if (_lastValue?.text == value.text &&
        _lastValue?.composing == value.composing) {
      return;
    }
    _lastValue = value;
    _debounce?.cancel();
    _priceTimer?.cancel();
    final version = ++_epoch;
    _closed = false;
    _selected = -1;
    _query = widget.text.text.trim();
    _price = null;
    _items = [];
    _terms = [];
    _failed = false;
    _loading = _query.isNotEmpty && widget.text.value.composing.isCollapsed;
    if (widget.focus.hasFocus) _portal.show();
    setState(() {});
    if (!_loading) return;
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _search(version, _query),
    );
  }

  Future<void> _search(int version, String query) async {
    try {
      final rows = [...await c.search(query)];
      if (!mounted || version != _epoch) return;
      int rank(MarketRow row) {
        final names = [
          marketName(row, language),
          row['itemName']?.toString() ?? '',
          row['itemNameEn']?.toString() ?? '',
        ].map((s) => s.toLowerCase());
        final q = query.toLowerCase();
        return names.contains(q)
            ? 0
            : names.any((s) => s.startsWith(q))
            ? 1
            : names.any((s) => s.contains(q))
            ? 2
            : 3;
      }

      final positions = {for (var i = 0; i < rows.length; i++) rows[i]: i};
      rows.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r == 0 ? positions[a]!.compareTo(positions[b]!) : r;
      });
      setState(() {
        _items = rows.take(5).toList();
        _terms = marketSearchTerms(rows, query, language);
        _loading = false;
      });
      if (_items.isNotEmpty) {
        final id = marketItemId(_items.first);
        if (id != null) {
          _priceTimer = Timer(
            const Duration(milliseconds: 200),
            () => _readPrice(version, id),
          );
        }
      }
    } on Object {
      if (mounted && version == _epoch) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _readPrice(int version, int id) async {
    if (!mounted ||
        version != _epoch ||
        !widget.focus.hasFocus ||
        !widget.text.value.composing.isCollapsed) {
      return;
    }
    final generation = c.port.generation, revision = c.contextRevision;
    try {
      final result = await c.port.read('offers', id: id, side: 1);
      if (!mounted ||
          version != _epoch ||
          generation != c.port.generation ||
          revision != c.contextRevision) {
        return;
      }
      final value = result.rows.isEmpty
          ? null
          : marketNumber(result.rows.first['unitPrice']);
      if (value != null && value.isFinite && value >= 0) {
        setState(() => _price = value);
      }
    } on Object {
      /* Unknown price is deliberately blank. */
    }
  }

  void _fill(String term) {
    widget.text.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    widget.focus.requestFocus();
  }

  Future<void> _market(String term) async {
    widget.focus.unfocus();
    if (term.isNotEmpty) widget.onSearched?.call();
    await c.rememberSearch(term);
    c.tab(1);
    await c.browser.choose(keyword: term);
  }

  Future<void> _open(MarketRow row) async {
    final id = marketItemId(row);
    widget.focus.unfocus();
    widget.onSearched?.call();
    if (id != null) await c.openItem(id, search: _query);
  }

  Future<void> _submit() async {
    if (_loading) {
      _debounce?.cancel();
      final version = _epoch;
      await _search(version, _query);
      if (!mounted || version != _epoch) return;
    }
    if (!widget.text.value.composing.isCollapsed) return;
    if (_selected >= 0 && _selected < _terms.length) {
      await _market(_terms[_selected]);
      return;
    }
    final index = _selected - _terms.length;
    if (_selected >= 0 && index < _items.length) {
      await _open(_items[index]);
      return;
    }
    if (_selected >= 0 || c.mainTab == 1 && !c.hasItem || _items.isEmpty) {
      await _market(widget.text.text.trim());
      return;
    }
    await _open(_items.first);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.text.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _closed = true;
      _epoch++;
      _portal.hide();
      _priceTimer?.cancel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isShiftPressed &&
        _terms.isNotEmpty &&
        widget.text.text != _terms.first &&
        !_closed) {
      _fill(_terms.first);
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) &&
        _query.isNotEmpty) {
      setState(
        () => _selected =
            (_selected + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(
              0,
              _terms.length + _items.length,
            ),
      );
      _closed = false;
      _portal.show();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && !_closed) {
      unawaited(_submit());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _highlight(String name) {
    final at = name.toLowerCase().indexOf(_query.toLowerCase());
    if (at < 0 || _query.isEmpty) {
      return Text(name, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: name.substring(0, at)),
          TextSpan(
            text: name.substring(at, at + _query.length),
            style: TextStyle(
              color: context.tokens.colors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: name.substring(at + _query.length)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _tag(String label, VoidCallback tap, {MarketRow? row}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: marketButtonAction(
          key: ValueKey(('market-search-tag', label)),
          TextButton(
            onPressed: tap,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: context.tokens.colors.textPrimary,
              backgroundColor: context.tokens.surfaces.panel.border.withValues(
                alpha: .25,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (row != null) ...[
                  SizedBox.square(
                    dimension: 20,
                    child: MarketArt.of(row),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  Widget _section(String title, VoidCallback clear) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: context.tokens.colors.textSecondary,
            fontSize: 12,
          ),
        ),
      ),
      marketTextAction(
        key: ValueKey(('market-search-clear', title)),
        onPressed: clear,
        child: Text(tr('清空', 'Clear')),
      ),
    ],
  );
  Widget _recent() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (c.recentSearches.isNotEmpty) ...[
        _section(marketText(context, 'recent'), () => c.clearHistory(false)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final term in c.recentSearches.take(8))
              _tag(term, () => _fill(term)),
          ],
        ),
      ],
      if (c.recentItems.isNotEmpty) ...[
        _section(
          marketText(context, 'recentItems'),
          () => c.clearHistory(true),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in c.recentItems.take(8))
              if (c.blocks['recent:$id'] case final MarketRead read)
                _tag(
                  marketName(read.data, language),
                  () => _open(read.data),
                  row: read.data,
                ),
          ],
        ),
      ],
      if (_hot.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(tr('大家都在搜', 'Popular searches')),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            children: [
              for (var i = 0; i < _hot.length; i++)
                SizedBox(
                  width: box.maxWidth / 2,
                  child: marketButtonAction(
                    key: ValueKey(('market-search-hot', i)),
                    TextButton(
                      onPressed: () => _market(_hot[i]),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${i + 1}  ${_hot[i]}',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      if (c.recentSearches.isEmpty && c.recentItems.isEmpty && _hot.isEmpty)
        Text(tr('输入物品名称开始搜索', 'Type an item name to search')),
    ],
  );
  Widget _typing() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(marketText(context, 'loading')),
        ),
      if (_failed)
        marketTextAction(
          key: const Key('market-search-retry'),
          onPressed: () {
            _lastValue = null;
            _changed();
          },
          child: Text(marketText(context, 'retry')),
        ),
      for (var i = 0; i < _terms.length; i++)
        ListTile(
          dense: true,
          minTileHeight: 36,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          selected: _selected == i,
          leading: const MarketplaceIcon(MarketplaceGlyph.search, size: 18),
          title: _highlight(_terms[i]),
          trailing: StarBridgeNativeIconAction(
            controlKey: ValueKey(('market-search-fill', i)),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(side: BorderSide.none),
            label: tr('填入关键词', 'Complete keyword'),
            onActivate: (_) => _fill(_terms[i]),
            icon: const Text('↖'),
          ),
          onTap: () => _market(_terms[i]),
        ),
      if (_items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Text(
            tr('物品', 'Items'),
            style: TextStyle(
              fontSize: 11,
              color: context.tokens.colors.textSecondary,
            ),
          ),
        ),
      for (var i = 0; i < _items.length; i++)
        ListTile(
          dense: true,
          minTileHeight: 56,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          selected: _selected == _terms.length + i,
          leading: SizedBox.square(
            dimension: 36,
            child: MarketArt.of(_items[i]),
          ),
          title: _highlight(marketName(_items[i], language)),
          subtitle: MarketListingCounts(_items[i]),
          trailing: i == 0 && _price != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      tr('最低卖价', 'Lowest sell'),
                      style: const TextStyle(fontSize: 10),
                    ),
                    MarketPrice(_price),
                  ],
                )
              : null,
          onTap: () => _open(_items[i]),
        ),
      ListTile(
        dense: true,
        selected: _selected == _terms.length + _items.length,
        title: Text('${tr('在市场中搜索', 'Search market for')} “$_query”'),
        onTap: () => _market(_query),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          tr(
            'Tab 补全关键词  /  ↑↓ 选择  /  Enter 搜索或打开  /  Esc 关闭',
            'Tab complete  /  ↑↓ select  /  Enter search or open  /  Esc close',
          ),
          style: TextStyle(
            fontSize: 11,
            color: context.tokens.colors.textSecondary,
          ),
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = math.min(
        math.max(520.0, box.maxWidth),
        MediaQuery.sizeOf(context).width - 32,
      );
      final ghost =
          _terms.isNotEmpty &&
              _terms.first.startsWith(widget.text.text) &&
              widget.text.text.isNotEmpty &&
              widget.text.value.composing.isCollapsed
          ? _terms.first.substring(widget.text.text.length)
          : '';
      return OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) {
          final render = context.findRenderObject() as RenderBox?;
          final left = render?.localToGlobal(Offset.zero).dx ?? 0;
          final shift = math.min(
            0.0,
            MediaQuery.sizeOf(context).width - 16 - left - width,
          );
          return Positioned(
            width: width,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: Offset(shift, 6),
              child: TextFieldTapRegion(
                child: Material(
                  elevation: 0,
                  color: context.tokens.surfaces.floating.fill,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: context.tokens.surfaces.panel.border,
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(
                        180,
                        MediaQuery.sizeOf(context).height - 150,
                      ),
                    ),
                    // Focus stays in the field (which owns the arrow keys);
                    // popup controls activate by pointer and reader only,
                    // as the native buttons here never took focus either.
                    child: ExcludeFocus(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: widget.text.text.isEmpty ? _recent() : _typing(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: CompositedTransformTarget(
          link: _link,
          child: Stack(
            children: [
              TextField(
                key: const Key('marketplace-search'),
                controller: widget.text,
                focusNode: widget.focus,
                onEditingComplete: () {},
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: marketText(context, 'search'),
                  prefixIcon: const MarketplaceIcon(
                    MarketplaceGlyph.search,
                    size: 18,
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 6),
                        Text(
                          ghost.isEmpty ? 'Ctrl K' : 'Tab',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (ghost.isNotEmpty)
                Positioned.fill(
                  left: 48,
                  right: 64,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: widget.text.text,
                              style: const TextStyle(color: Colors.transparent),
                            ),
                            TextSpan(
                              text: ghost,
                              style: TextStyle(
                                color: context.tokens.colors.textSecondary
                                    .withValues(alpha: .55),
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
