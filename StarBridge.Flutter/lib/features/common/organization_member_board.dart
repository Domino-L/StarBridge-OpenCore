import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'organization_holo.dart';
import 'organization_member_controls.dart';
import 'organization_member_copy.dart';
import 'organization_member_row.dart';
export 'organization_member_controls.dart';
export 'organization_member_copy.dart';
export 'organization_member_row.dart';

/// Presentation only: each source retains its authorization, fetch and paging
/// semantics, and supplies already visitor-safe rows and explicit capabilities.
class OrganizationMemberBoard extends StatefulWidget {
  const OrganizationMemberBoard({
    required this.rows,
    required this.searchController,
    required this.onSearch,
    required this.namespace,
    required this.roleLabel,
    this.columns = const OrganizationMemberColumns(),
    this.totalCount,
    this.summaryText,
    this.updatedText,
    this.onlineCount,
    this.inGameCount,
    this.fetchedAt,
    this.countsArePageScoped = false,
    this.hasMultiplePages,
    this.filters = const [],
    this.filter = OrganizationMemberFilter.all,
    this.onFilter,
    this.pagination = const OrganizationMemberPagination(),
    this.loading = false,
    this.refreshing = false,
    this.loadingIndicator,
    this.refreshingIndicator,
    this.error,
    this.onRetry,
    this.note,
    this.footerNote,
    this.searchHint,
    this.searchLabel,
    this.searchButtonLabel,
    this.searchError,
    this.showSearch = true,
    this.controlsEnabled = true,
    this.initialScrollOffset = 0,
    this.onScroll,
    this.rowBuilder,
    super.key,
  });
  final List<OrganizationMemberEntry> rows;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final String namespace, roleLabel;
  final OrganizationMemberColumns columns;
  final int? totalCount, onlineCount, inGameCount;
  final String? summaryText, updatedText, searchLabel, searchButtonLabel;
  final DateTime? fetchedAt;
  final bool countsArePageScoped;

  /// A source may know page coverage even when it offers no paging command.
  final bool? hasMultiplePages;
  final List<OrganizationMemberFilter> filters;
  final OrganizationMemberFilter filter;
  final ValueChanged<OrganizationMemberFilter>? onFilter;
  final OrganizationMemberPagination pagination;
  final bool loading, refreshing;

  /// Optional presentation slots; loading, reads and paging remain source-owned.
  /// Omitting these retains the existing shared board presentation.
  final Widget? loadingIndicator, refreshingIndicator;
  final bool showSearch, controlsEnabled;
  final String? error, note, footerNote, searchHint, searchError;
  final VoidCallback? onRetry;
  final double initialScrollOffset;
  final ValueChanged<double>? onScroll;
  final Widget Function(
    OrganizationMemberEntry,
    OrganizationMemberColumns,
    String,
    bool,
  )?
  rowBuilder;
  @override
  State<OrganizationMemberBoard> createState() => _MemberBoardState();
}

class _MemberBoardState extends State<OrganizationMemberBoard> {
  ScrollPosition? _position;

  // The containing page owns the viewport. Observe it only when the source
  // needs scroll restoration; a second viewport here makes short pages tall
  // and splits wheel/keyboard scrolling on long pages.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = widget.onScroll == null
        ? null
        : Scrollable.maybeOf(context)?.position;
    if (identical(position, _position)) return;
    _position?.removeListener(_remember);
    _position = position;
    position?.addListener(_remember);
    if (position == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_position, position) ||
          !position.hasContentDimensions) {
        return;
      }
      position.jumpTo(
        widget.initialScrollOffset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _remember() => widget.onScroll?.call(_position!.pixels);
  @override
  void dispose() {
    _position?.removeListener(_remember);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pagination = widget.pagination;
    final pageCounts =
        widget.countsArePageScoped &&
        (widget.hasMultiplePages ??
            ((pagination.totalPages ?? 1) > 1 ||
                (pagination.page ?? 1) > 1 ||
                pagination.onPrevious != null ||
                pagination.onNext != null ||
                pagination.onFirst != null));
    final summary = <String>[
      if (widget.totalCount != null)
        memberBoardText(
          context,
          'total',
        ).replaceAll('{n}', '${widget.totalCount}'),
      if (widget.onlineCount != null)
        '${memberBoardText(context, pageCounts ? 'pageOnline' : 'online')} ${widget.onlineCount}',
      if (widget.inGameCount != null)
        '${memberBoardText(context, pageCounts ? 'pageInGame' : 'inGame')} ${widget.inGameCount}',
    ];
    final summaryText = widget.summaryText ?? summary.join(' · ');
    final actions = widget.rows.any((row) => row.actions != null);
    final holo = OrganizationHolo.of(context);
    final updated = widget.fetchedAt != null || widget.updatedText != null
        ? Text(
            widget.updatedText ??
                memberBoardText(context, 'updated').replaceAll(
                  '{time}',
                  '${widget.fetchedAt!.toLocal().hour.toString().padLeft(2, '0')}:${widget.fetchedAt!.toLocal().minute.toString().padLeft(2, '0')}',
                ),
            key: Key('${widget.namespace}-updated'),
            style: TextStyle(
              color: tokens.colors.textSecondary,
              fontFamily: holo ? tokens.typography.monoFamily : null,
              fontSize: holo ? 12 : null,
            ),
          )
        : null;
    final footerNote = widget.footerNote?.isNotEmpty ?? false
        ? Text(
            widget.footerNote!,
            key: Key('${widget.namespace}-footer-note'),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          )
        : null;
    Widget paging = OrganizationMemberPaginationBar(
      pagination: widget.pagination,
      namespace: widget.namespace,
      enabled: widget.controlsEnabled,
    );
    if (holo) paging = OrganizationHoloFace(child: paging);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (holo)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  summaryText,
                  key: Key('${widget.namespace}-summary'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1),
                ),
              ),
              if (updated != null) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: updated,
                  ),
                ),
              ],
            ],
          )
        else if (summaryText.isNotEmpty ||
            widget.fetchedAt != null ||
            widget.updatedText != null)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            children: [
              if (summaryText.isNotEmpty)
                Text(
                  summaryText,
                  key: Key('${widget.namespace}-summary'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ?updated,
            ],
          ),
        const SizedBox(height: 12),
        OrganizationMemberToolbar(
          namespace: widget.namespace,
          searchController: widget.searchController,
          onSearch: widget.onSearch,
          filters: widget.filters,
          filter: widget.filter,
          onFilter: widget.onFilter,
          pagination: widget.pagination,
          searchHint: widget.searchHint,
          searchLabel: widget.searchLabel,
          searchButtonLabel: widget.searchButtonLabel,
          searchError: widget.searchError,
          showSearch: widget.showSearch,
          enabled: widget.controlsEnabled,
        ),
        if (widget.note?.isNotEmpty ?? false)
          Padding(
            padding: EdgeInsets.only(top: tokens.space.sm),
            child: Text(
              widget.note!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.colors.textSecondary),
            ),
          ),
        if (widget.refreshing)
          Padding(
            padding: EdgeInsets.only(top: tokens.space.sm),
            child:
                widget.refreshingIndicator ??
                Text(memberBoardText(context, 'refreshing')),
          ),
        if (widget.error != null)
          Padding(
            key: Key('${widget.namespace}-unavailable'),
            padding: EdgeInsets.only(top: tokens.space.sm),
            child: Row(
              children: [
                Expanded(child: Text(widget.error!)),
                if (widget.onRetry != null)
                  StarBridgeActionButton(
                    controlKey: Key('${widget.namespace}-retry'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: (_) => widget.onRetry!(),
                    child: Text(memberBoardText(context, 'retry')),
                  ),
              ],
            ),
          ),
        if (widget.loading && widget.rows.isEmpty)
          Padding(
            key: Key('${widget.namespace}-loading'),
            padding: EdgeInsets.all(tokens.space.lg),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child:
                      widget.loadingIndicator ??
                      const CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: tokens.space.md),
                Text(memberBoardText(context, 'loading')),
              ],
            ),
          )
        else if (widget.rows.isEmpty && widget.error == null)
          Padding(
            key: Key('${widget.namespace}-empty'),
            padding: EdgeInsets.all(tokens.space.lg),
            child: Text(memberBoardText(context, 'empty')),
          )
        else if (widget.rows.isNotEmpty) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              border: holo
                  ? Border(
                      bottom: BorderSide(
                        color: OrganizationHoloColors(context).hair,
                      ),
                    )
                  : null,
            ),
            child: OrganizationMemberHeader(
              columns: widget.columns,
              roleLabel: widget.roleLabel,
              showActions: actions,
            ),
          ),
          if (!holo) const SizedBox(height: 8),
          Column(
            key: Key('${widget.namespace}-rows'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.rows.length; i++) ...[
                if (i > 0 && !holo) const SizedBox(height: 8),
                widget.rowBuilder?.call(
                      widget.rows[i],
                      widget.columns,
                      widget.roleLabel,
                      actions,
                    ) ??
                    OrganizationMemberRow(
                      key: ValueKey('member-row-${widget.rows[i].reference}'),
                      entry: widget.rows[i],
                      columns: widget.columns,
                      roleLabel: widget.roleLabel,
                      showActions: actions,
                    ),
              ],
            ],
          ),
        ],
        SizedBox(height: holo ? 16 : 12),
        // Holo boards keep the roster source beside the paging controls.
        if (holo)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [paging, ?footerNote],
          )
        else ...[
          paging,
          if (footerNote != null)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.xs),
              child: footerNote,
            ),
        ],
      ],
    );
  }
}
