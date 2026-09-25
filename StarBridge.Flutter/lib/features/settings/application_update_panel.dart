import 'package:flutter/material.dart';

/// Dedicated secondary surface: version masthead, scrollable announcement,
/// pinned actions. Uses the client's theme, never a separate blue palette.
class ApplicationUpdatePanel extends StatefulWidget {
  const ApplicationUpdatePanel({
    required this.title,
    required this.currentLabel,
    required this.current,
    required this.version,
    required this.body,
    required this.actions,
    super.key,
  });
  final String title, currentLabel;
  final String? current, version;
  final Widget body;
  final List<Widget> actions;
  @override
  State<ApplicationUpdatePanel> createState() => _ApplicationUpdatePanelState();
}

class _ApplicationUpdatePanelState extends State<ApplicationUpdatePanel> {
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 3, color: colors.primary),
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (widget.version != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.version!,
                          key: const Key('update-announcement-version'),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ],
                      if (widget.current != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${widget.currentLabel} · ${widget.current}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 20),
                      widget.body,
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: widget.actions,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deliberately limited announcement formatting: headings, paragraphs, bullets.
/// No embedded images, HTML, links, scripts or network fetches from remote notes.
class UpdateReleaseNotes extends StatelessWidget {
  const UpdateReleaseNotes(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = <Widget>[];
    for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      final bullet = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
      final content = heading?.group(2) ?? bullet?.group(1) ?? trimmed;
      final label = Text(
        content,
        style: heading != null
            ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
            : theme.textTheme.bodyMedium?.copyWith(height: 1.6),
      );
      blocks.add(
        Padding(
          padding: EdgeInsets.only(top: heading != null ? 18 : 8),
          child: heading != null
              ? Semantics(header: true, child: label)
              : bullet != null
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: label),
                  ],
                )
              : label,
        ),
      );
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }
}
