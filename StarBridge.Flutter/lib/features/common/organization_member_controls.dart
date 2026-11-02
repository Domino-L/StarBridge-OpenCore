import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';

import '../../design_system/interaction/starbridge_field_frame.dart';
import '../../design_system/interaction/starbridge_choice_chip.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'organization_holo.dart';
import 'organization_holo_choice.dart';
import 'organization_member_copy.dart';
import 'organization_member_row.dart';

class OrganizationMemberPagination {
  const OrganizationMemberPagination({
    this.page,
    this.totalPages,
    this.onPrevious,
    this.onNext,
    this.onJump,
    this.pageSize,
    this.pageSizes = const [],
    this.onPageSize,
    this.showPrevious = true,
    this.showNext = true,
    this.onFirst,
    this.enabled = true,
    this.showNavigationWhenDisabled = false,
  });
  final int? page, totalPages, pageSize;
  final VoidCallback? onPrevious, onNext;
  final ValueChanged<int>? onJump, onPageSize;
  final List<int> pageSizes;
  final bool showPrevious, showNext, enabled;
  final bool showNavigationWhenDisabled;
  final VoidCallback? onFirst;
}

class OrganizationMemberToolbar extends StatelessWidget {
  const OrganizationMemberToolbar({
    required this.namespace,
    required this.searchController,
    required this.onSearch,
    this.filters = const [],
    this.filter = OrganizationMemberFilter.all,
    this.onFilter,
    this.pagination = const OrganizationMemberPagination(),
    this.maxSearchLength = 128,
    this.searchHint,
    this.searchLabel,
    this.searchButtonLabel,
    this.searchError,
    this.showSearch = true,
    this.enabled = true,
    super.key,
  });
  final String namespace;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final List<OrganizationMemberFilter> filters;
  final OrganizationMemberFilter filter;
  final ValueChanged<OrganizationMemberFilter>? onFilter;
  final OrganizationMemberPagination pagination;
  final int maxSearchLength;
  final String? searchHint, searchError, searchLabel, searchButtonLabel;
  final bool showSearch, enabled;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final holo = OrganizationHolo.of(context);
    final toolbar = LayoutBuilder(
      builder: (context, constraints) {
        final decoration = InputDecoration(
          counterText: '',
          labelText: searchLabel,
          hintText: searchLabel == null
              ? searchHint ?? memberBoardText(context, 'search')
              : null,
          errorText: searchError,
        );
        final submit = StarBridgeActionButton(
          controlKey: Key('$namespace-search-submit'),
          nativeStyle: holo
              ? organizationHoloButton(context, parallelogram: true)
              : null,
          onActivate: enabled ? (_) => onSearch(searchController.text) : null,
          child: Text(searchButtonLabel ?? memberBoardText(context, 'submit')),
        );
        final search = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StarBridgeFieldFrame(
                enabled: enabled,
                builder: (_, focus) => TextField(
                  focusNode: focus,
                  key: Key('$namespace-search'),
                  controller: searchController,
                  maxLength: maxSearchLength,
                  enabled: enabled,
                  onSubmitted: enabled
                      ? (value) => unawaited(
                          runStarBridgeActivation<void>(
                            InteractionSource.keyboard,
                            () => onSearch(value),
                          ),
                        )
                      : null,
                  decoration: holo
                      ? organizationHoloField(
                          context,
                          decoration,
                          slantEnd: true,
                        )
                      : decoration,
                ),
              ),
            ),
            // The holo button's slanted start sits against the field's
            // slanted end, a few pixels apart along the whole edge.
            if (holo)
              Transform.translate(
                offset: Offset(
                  4 - organizationHoloRun(organizationHoloFieldHeight(context)),
                  0,
                ),
                child: SizedBox(
                  height: organizationHoloFieldHeight(context),
                  child: submit,
                ),
              )
            else ...[
              const SizedBox(width: 8),
              submit,
            ],
          ],
        );
        final chips = Wrap(
          spacing: holo ? 10 : tokens.space.xs,
          children: [
            for (final value in filters)
              if (holo)
                OrganizationHoloChoice(
                  controlKey: Key('$namespace-filter-${value.name}'),
                  label: memberBoardText(context, value.name),
                  selected: value == filter,
                  onSelected: onFilter == null || !enabled
                      ? null
                      : (_) => onFilter!(value),
                )
              else
                StarBridgeChoiceChip(
                  controlKey: Key('$namespace-filter-${value.name}'),
                  label: memberBoardText(context, value.name),
                  selected: value == filter,
                  onSelected: onFilter == null || !enabled
                      ? null
                      : (_) => onFilter!(value),
                ),
          ],
        );
        final options = Wrap(
          spacing: tokens.space.md,
          runSpacing: tokens.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [if (filters.length > 1) chips],
        );
        // Holo surfaces keep search and filters on one line when wide.
        if (holo &&
            showSearch &&
            filters.length > 1 &&
            constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              options,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSearch) search,
            if (filters.length > 1) ...[
              if (showSearch) const SizedBox(height: 12),
              options,
            ],
          ],
        );
      },
    );
    // The slanted search pair and filters need the native control faces.
    return holo ? OrganizationHoloFace(child: toolbar) : toolbar;
  }
}

class OrganizationMemberPaginationBar extends StatefulWidget {
  const OrganizationMemberPaginationBar({
    required this.pagination,
    required this.namespace,
    this.enabled = true,
    super.key,
  });
  final OrganizationMemberPagination pagination;
  final String namespace;
  final bool enabled;
  @override
  State<OrganizationMemberPaginationBar> createState() => _PaginationBarState();
}

class _PaginationBarState extends State<OrganizationMemberPaginationBar> {
  final jump = TextEditingController();
  @override
  void dispose() {
    jump.dispose();
    super.dispose();
  }

  void go() {
    if (!widget.enabled || !widget.pagination.enabled) {
      return;
    }
    final page = int.tryParse(jump.text.trim());
    if (page != null &&
        page > 0 &&
        (widget.pagination.totalPages == null ||
            page <= widget.pagination.totalPages!)) {
      widget.pagination.onJump?.call(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.pagination;
    final enabled = widget.enabled && p.enabled;
    final holo = OrganizationHolo.of(context)
        ? organizationHoloButton(context)
        : null;
    final pageSizeAvailable = p.onPageSize != null && p.pageSizes.isNotEmpty;
    if (!p.showNavigationWhenDisabled &&
        p.page == null &&
        p.onNext == null &&
        p.onPrevious == null &&
        p.onFirst == null &&
        !pageSizeAvailable) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (p.onFirst != null)
          StarBridgeActionButton(
            controlKey: Key('${widget.namespace}-first-page'),
            nativeStyle: holo,
            onActivate: enabled ? (_) => p.onFirst!() : null,
            child: Text(memberBoardText(context, 'first')),
          ),
        if (p.showPrevious)
          StarBridgeActionButton(
            controlKey: Key('${widget.namespace}-previous-page'),
            nativeStyle: holo,
            onActivate: p.onPrevious == null || !enabled
                ? null
                : (_) => p.onPrevious!(),
            child: Text(memberBoardText(context, 'previous')),
          ),
        if (p.page != null)
          Text(
            memberBoardText(context, p.totalPages == null ? 'page' : 'pages')
                .replaceAll('{n}', '${p.page}')
                .replaceAll('{total}', '${p.totalPages}'),
          ),
        if (p.showNext)
          StarBridgeActionButton(
            controlKey: Key('${widget.namespace}-next-page'),
            nativeStyle: holo,
            onActivate: p.onNext == null || !enabled
                ? null
                : (_) => p.onNext!(),
            child: Text(memberBoardText(context, 'next')),
          ),
        if (p.onJump != null) ...[
          SizedBox(
            width: 72,
            child: StarBridgeFieldFrame(
              enabled: enabled,
              builder: (_, focus) => TextField(
                key: Key('${widget.namespace}-jump-input'),
                controller: jump,
                enabled: enabled,
                focusNode: focus,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: holo == null
                    ? InputDecoration(
                        hintText: memberBoardText(context, 'pageNumber'),
                      )
                    : organizationHoloField(
                        context,
                        InputDecoration(
                          hintText: memberBoardText(context, 'pageNumber'),
                        ),
                      ),
                onSubmitted: (_) => unawaited(
                  runStarBridgeActivation<void>(InteractionSource.keyboard, go),
                ),
              ),
            ),
          ),
          StarBridgeActionButton(
            controlKey: Key('${widget.namespace}-jump'),
            nativeStyle: holo,
            onActivate: enabled ? (_) => go() : null,
            child: Text(memberBoardText(context, 'jump')),
          ),
        ],
        if (pageSizeAvailable)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(memberBoardText(context, 'pageSize')),
              SizedBox(width: context.tokens.space.sm),
              StarBridgeCompactSelect<int>(
                identity: '${widget.namespace}-page-size',
                controlKey: Key('${widget.namespace}-page-size'),
                semanticLabel: memberBoardText(context, 'pageSize'),
                value: p.pageSize,
                options: [
                  for (final size in p.pageSizes)
                    StarBridgeSelectOption(value: size, label: '$size'),
                ],
                onSelected: enabled ? (value, _) => p.onPageSize!(value) : null,
              ),
            ],
          ),
      ],
    );
  }
}
