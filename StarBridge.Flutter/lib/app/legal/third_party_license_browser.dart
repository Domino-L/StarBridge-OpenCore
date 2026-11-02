import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/icons/standard_icon.dart';
import '../../design_system/interaction/starbridge_action_row.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_icon_action.dart';
import '../../design_system/interaction/starbridge_page_motion.dart';
import '../../features/settings/help_support_action.dart';
import '../../features/settings/help_support_waiting.dart';
import 'third_party_license_copy.dart';
import 'third_party_license_details.dart';
import 'third_party_license_index.dart';

/// Read-only presentation of LicenseRegistry. Registration stays at bootstrap.
/// The directory and exact entries are captured once per opening (or retry).
class ThirdPartyLicenseBrowser extends StatefulWidget {
  const ThirdPartyLicenseBrowser({
    required this.applicationName,
    required this.applicationLegalese,
    super.key,
  });
  final String applicationName;
  final String applicationLegalese;

  @override
  State<ThirdPartyLicenseBrowser> createState() => _BrowserState();
}

class _BrowserState extends State<ThirdPartyLicenseBrowser> {
  final _directoryScroll = ScrollController();
  final _backFocus = FocusNode();
  final _rowFocus = <String, FocusNode>{};
  StreamSubscription<LicenseEntry>? _subscription;
  ThirdPartyLicenseIndex? _index;
  ThirdPartyLicensePackage? _selected;
  InteractionSource _source = InteractionSource.programmatic;
  bool _detailFocused = false, _wide = false, _failed = false;
  int _epoch = 0;
  bool _openingResolved = false;

  @override
  void initState() {
    super.initState();
    _read(InteractionSource.programmatic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_openingResolved) {
      _source = resolveStarBridgeInitialReadSource(context, _source);
      _openingResolved = true;
    }
  }

  void _read(InteractionSource source) {
    final epoch = ++_epoch;
    _source = source;
    _index = null;
    _failed = false;
    unawaited(_subscription?.cancel());
    final entries = <LicenseEntry>[];
    void fail(Object _, [StackTrace? stack]) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }

    try {
      _subscription = LicenseRegistry.licenses.listen(
        entries.add,
        onError: fail,
        cancelOnError: true,
        onDone: () {
          if (!mounted || epoch != _epoch || _failed) return;
          try {
            final index = ThirdPartyLicenseIndex(entries);
            setState(() {
              _index = index;
              _selected = index.packages.firstOrNull;
            });
          } catch (error, stack) {
            fail(error, stack);
          }
        },
      );
    } catch (error, stack) {
      fail(error, stack);
    }
  }

  void _select(ThirdPartyLicensePackage package, InteractionSource source) {
    setState(() {
      _source = source;
      _selected = package;
      _detailFocused = true;
    });
    if (!_wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _detailFocused && !_wide) _backFocus.requestFocus();
      });
    }
  }

  void _back(InteractionSource source) {
    if (!_wide && _detailFocused) {
      setState(() {
        _source = source;
        _detailFocused = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_detailFocused) {
          _rowFocus[_selected?.name]?.requestFocus();
        }
      });
    } else {
      unawaited(
        runStarBridgeActivation<void>(source, () async {
          await Navigator.of(context).maybePop();
        }),
      );
    }
  }

  @override
  void dispose() {
    ++_epoch;
    unawaited(_subscription?.cancel());
    _directoryScroll.dispose();
    _backFocus.dispose();
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _about(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.widthOf(context) >= 720 ? 24 : 12,
      vertical: 24,
    ),
    child: Column(
      children: [
        Text(
          widget.applicationName,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (widget.applicationLegalese.isNotEmpty)
          Text(
            widget.applicationLegalese,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 18),
        Text(
          'Powered by Flutter',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _directory(BuildContext context) {
    final copy = thirdPartyLicenseCopy(context);
    final packages = _index?.packages;
    final safe = MediaQuery.paddingOf(context);
    return Material(
      color: Theme.of(context).cardColor,
      elevation: packages == null ? 0 : 4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: ListView.builder(
          key: const PageStorageKey('license-directory'),
          controller: _directoryScroll,
          padding: EdgeInsets.only(
            left: safe.left,
            right: safe.right,
            bottom: safe.bottom,
          ),
          itemCount: packages == null ? 2 : packages.length + 1,
          itemBuilder: (context, position) {
            if (position == 0) return _about(context);
            if (packages == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _failed
                    ? Column(
                        children: [
                          Semantics(liveRegion: true, child: Text(copy.failed)),
                          HelpSupportAction(
                            controlKey: const ValueKey(
                              'license-directory-retry',
                            ),
                            onActivate: (source) =>
                                setState(() => _read(source)),
                            child: Text(copy.retry),
                          ),
                        ],
                      )
                    : HelpSupportWaiting(
                        key: ValueKey(_epoch),
                        label: copy.loading,
                        source: _source,
                      ),
              );
            }
            final package = packages[position - 1];
            final selected = _wide && _selected == package;
            final subtitle = MaterialLocalizations.of(context)
                .licensesPackageDetailText(package.entries.length);
            return Ink(
              color: selected
                  ? Theme.of(context).highlightColor
                  : Theme.of(context).cardColor,
              child: StarBridgeActionRow(
                controlKey: ValueKey('license-package-${package.name}'),
                focusNode: _rowFocus.putIfAbsent(
                  package.name,
                  () => FocusNode(),
                ),
                semanticLabel: '${package.name}\n$subtitle',
                semanticSelected: selected,
                onActivate: (_, source) => _select(package, source),
                child: ExcludeSemantics(
                  child: ListTile(
                    title: Text(package.name),
                    subtitle: Text(subtitle),
                    selected: selected,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _backButton(BuildContext context) => StarBridgeIconAction(
    controlKey: const ValueKey('license-back'),
    label: MaterialLocalizations.of(context).backButtonTooltip,
    icon: const StandardIcon(StandardIconSemantic.arrowBack),
    focusNode: _backFocus,
    onActivate: _back,
  );

  Widget _details(ScrollController? controller) => ThirdPartyLicenseDetails(
    key: ValueKey(_selected!.name),
    package: _selected!,
    source: _source,
    scrollController: controller,
  );

  Widget _wideLayout(BuildContext context) {
    final height = MediaQuery.heightOf(context);
    final minimum = ((height - kToolbarHeight) / height).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          appBar: AppBar(
            leading: _backButton(context),
            title: Text(MaterialLocalizations.of(context).licensesPageTitle),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(kToolbarHeight),
              child: SizedBox(height: kToolbarHeight),
            ),
          ),
          body: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(width: 320, child: _directory(context)),
          ),
        ),
        if (_selected != null)
          SafeArea(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: 316,
                end: MediaQuery.widthOf(context) >= 720 ? 24 : 12,
              ),
              child: StarBridgePageSwitcher(
                instant: _source == InteractionSource.keyboard,
                child: SizedBox.expand(
                  key: ValueKey(_selected!.name),
                  child: DraggableScrollableSheet(
                    initialChildSize: minimum,
                    minChildSize: minimum,
                    expand: false,
                    builder: (context, controller) => MouseRegion(
                      child: Card(
                        color: Theme.of(context).cardColor,
                        elevation: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        clipBehavior: Clip.antiAlias,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                        child: _details(controller),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _wide = constraints.maxWidth >= 840;
      final inDetail = !_wide && _detailFocused && _selected != null;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _back(InteractionSource.keyboard),
        },
        child: Focus(
          autofocus: true,
          child: PopScope<void>(
            canPop: !inDetail,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop && inDetail) _back(InteractionSource.keyboard);
            },
            child: BlockSemantics(
              child: _wide
                  ? _wideLayout(context)
                  : Scaffold(
                      appBar: AppBar(
                        leading: _backButton(context),
                        title: inDetail
                            ? ThirdPartyLicenseTitle(package: _selected!)
                            : Text(
                                MaterialLocalizations.of(context)
                                    .licensesPageTitle,
                              ),
                      ),
                      body: StarBridgePageSwitcher(
                        instant: _source == InteractionSource.keyboard,
                        child: IndexedStack(
                          key: ValueKey(
                            inDetail
                                ? _selected!.name
                                : 'license-directory-active',
                          ),
                          index: inDetail ? 1 : 0,
                          children: [
                            Center(child: _directory(context)),
                            if (inDetail)
                              _details(null)
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    },
  );
}
