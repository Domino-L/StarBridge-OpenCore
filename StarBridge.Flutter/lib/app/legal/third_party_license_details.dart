import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/settings/help_support_action.dart';
import '../../features/settings/help_support_waiting.dart';
import 'third_party_license_copy.dart';
import 'third_party_license_index.dart';

/// Original entries, decoded lazily at animation priority just like LicensePage.
/// Changing selection retires old work; it never changes the shared registry.
class ThirdPartyLicenseDetails extends StatefulWidget {
  const ThirdPartyLicenseDetails({
    required this.package,
    required this.source,
    this.scrollController,
    super.key,
  });
  final ThirdPartyLicensePackage package;
  final InteractionSource source;
  final ScrollController? scrollController;

  @override
  State<ThirdPartyLicenseDetails> createState() => _DetailsState();
}

class _DetailsState extends State<ThirdPartyLicenseDetails> {
  final _paragraphs = <List<LicenseParagraph>>[];
  int _epoch = 0;
  bool _loaded = false, _failed = false;
  late InteractionSource _source;

  @override
  void initState() {
    super.initState();
    _read(widget.source);
  }

  @override
  void didUpdateWidget(ThirdPartyLicenseDetails old) {
    super.didUpdateWidget(old);
    if (old.package != widget.package) _read(widget.source);
  }

  void _read(InteractionSource source) {
    _source = source;
    _loaded = _failed = false;
    _paragraphs.clear();
    unawaited(_decode(++_epoch, widget.package.entries));
  }

  Future<void> _decode(int epoch, List<LicenseEntry> entries) async {
    try {
      for (final entry in entries) {
        // The task may already be queued when another package is selected.
        final paragraphs = await SchedulerBinding.instance
            .scheduleTask<List<LicenseParagraph>?>(
              () {
                if (!mounted || epoch != _epoch) return <LicenseParagraph>[];
                // TaskEntry reports a thrown callback globally instead of completing
                // its Future with an error. Capture here so the reader can retry.
                try {
                  return entry.paragraphs.toList();
                } catch (_) {
                  return null;
                }
              },
              Priority.animation,
              debugLabel: 'StarBridge license paragraphs',
            );
        if (!mounted || epoch != _epoch) return;
        if (paragraphs == null) {
          setState(() => _failed = true);
          return;
        }
        setState(() => _paragraphs.add(paragraphs));
      }
      if (mounted && epoch == _epoch) setState(() => _loaded = true);
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }
  }

  List<Widget> _body(BuildContext context) {
    final copy = thirdPartyLicenseCopy(context);
    return [
      for (final entry in _paragraphs) ...[
        const Padding(padding: EdgeInsets.all(18), child: Divider()),
        for (final paragraph in entry)
          Localizations.override(
            context: context,
            locale: const Locale('en', 'US'),
            child: Padding(
              padding: paragraph.indent == LicenseParagraph.centeredIndent
                  ? const EdgeInsets.only(top: 16)
                  : EdgeInsetsDirectional.only(
                      top: 8,
                      start: 16.0 * paragraph.indent,
                    ),
              child: Text(
                paragraph.text,
                textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                    ? TextAlign.center
                    : null,
                style: paragraph.indent == LicenseParagraph.centeredIndent
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null,
              ),
            ),
          ),
      ],
      if (_failed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(liveRegion: true, child: Text(copy.failed)),
              HelpSupportAction(
                controlKey: const ValueKey('license-detail-retry'),
                onActivate: (source) => setState(() => _read(source)),
                child: Text(copy.retry),
              ),
            ],
          ),
        )
      else if (!_loaded)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: HelpSupportWaiting(
            key: ValueKey(_epoch),
            label: copy.loading,
            source: _source,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pad = MediaQuery.widthOf(context) >= 720 ? 24.0 : 12.0;
    final safe = MediaQuery.paddingOf(context);
    final padding = EdgeInsets.fromLTRB(
      pad + safe.left,
      0,
      pad + safe.right,
      pad + safe.bottom,
    );
    final children = _body(context);
    final scrollController = widget.scrollController;
    final Widget body;
    if (scrollController != null) {
      body = CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverAppBar(
            automaticallyImplyLeading: false,
            pinned: true,
            backgroundColor: theme.cardColor,
            title: ThirdPartyLicenseTitle(package: widget.package),
          ),
          SliverPadding(
            padding: padding,
            sliver: SliverList.list(children: children),
          ),
        ],
      );
    } else {
      body = Center(
        child: Material(
          color: theme.cardColor,
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: Scrollbar(
                child: ListView(
                  primary: true,
                  padding: padding,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return DefaultTextStyle(style: theme.textTheme.bodySmall!, child: body);
  }
}

class ThirdPartyLicenseTitle extends StatelessWidget {
  const ThirdPartyLicenseTitle({required this.package, super.key});
  final ThirdPartyLicensePackage package;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        package.name,
        style: Theme.of(context).textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        MaterialLocalizations.of(context)
            .licensesPackageDetailText(package.entries.length),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    ],
  );
}
