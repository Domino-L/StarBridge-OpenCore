import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'menu_bridge_style.dart';

/// Same bounded inline PNG/JPEG contract as ChatAvatar; no network fetching.
class MenuInlineAvatar extends StatefulWidget {
  const MenuInlineAvatar({super.key, this.source, this.name});
  final String? source;
  final String? name;
  @override
  State<MenuInlineAvatar> createState() => _MenuInlineAvatarState();
}

class _MenuInlineAvatarState extends State<MenuInlineAvatar> {
  Uint8List? _bytes;
  @override
  void initState() {
    super.initState();
    _decode();
  }

  void _decode() {
    final source = widget.source;
    _bytes = null;
    if (source == null ||
        source.length > 128 * 1024 ||
        !(source.startsWith('data:image/png;base64,') ||
            source.startsWith('data:image/jpeg;base64,'))) {
      return;
    }
    try {
      _bytes = base64Decode(source.substring(source.indexOf(',') + 1));
    } on FormatException {
      /* Display a neutral fallback. */
    }
  }

  void _evict() {
    final bytes = _bytes;
    if (bytes != null) {
      unawaited(ResizeImage.resizeIfNeeded(96, 96, MemoryImage(bytes)).evict());
    }
  }

  @override
  void didUpdateWidget(MenuInlineAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _evict();
      _decode();
    }
  }

  @override
  void dispose() {
    _evict();
    _bytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: _bytes == null
        ? _fallback()
        : ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              _bytes!,
              width: 40,
              height: 40,
              cacheWidth: 96,
              cacheHeight: 96,
              fit: BoxFit.cover,
              gaplessPlayback: false,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => _fallback(),
            ),
          ),
  );

  Widget _fallback() => widget.name?.trim().isNotEmpty == true
      ? ColoredBox(
          color: MenuBridgeColors.of(context).selected,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              // The initial is a bounded portrait mark, not the full name.
              // Respect inherited text scaling, then fit its complete line box
              // inside the unchanged40px portrait without cropping a glyph.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.name!.trim().characters.first,
                  maxLines: 1,
                  style: TextStyle(
                    color: MenuBridgeColors.of(context).text,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
          ),
        )
      : const MenuGlyphView(MenuGlyph.person, size: 26);
}
