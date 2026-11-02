/// Tour definitions. Copy keys are `tour.<id>.<n>.title/body/note`.
enum GuideTourKind { tour, doIt }

final class GuideTourStep {
  const GuideTourStep(
    this.anchor, {
    this.until,
    this.interactive = false,
    this.card,
    this.beside,
    this.flow,
  });

  /// A [GuideAnchor] id; when it is not on screen the card is centred.
  final String? anchor;

  /// Waits for this business event ([GuideHub.report]): the page reports it
  /// only after the action really succeeded (opened, read, saved, created),
  /// never on a click, so disabled buttons, failures and keyboard use agree.
  final String? until;

  /// The page stays fully usable (no scrim, no pointer capture), e.g. a form
  /// the user fills while the card explains it, including its pickers.
  final bool interactive;

  /// Puts the card inside this anchor instead of beside the highlight, e.g.
  /// next to the native RSI page, which draws above every Flutter layer.
  final String? card;

  /// Puts the card next to this anchor (e.g. beside a dialog) so it never
  /// covers the fields the user is filling.
  final String? beside;

  /// The business flow instance this step lives in (the create form, the
  /// hangar reader). Closing it without finishing ends the tour, unseen.
  final String? flow;

  bool get waits => until != null;
}

final class GuideTourSpec {
  const GuideTourSpec(this.id, this.kind, this.steps, {this.route});
  final String id;
  final GuideTourKind kind;
  final List<GuideTourStep> steps;

  /// Auto-start on the first visit of this route (eligible profiles only).
  /// Do-it tours have none: their first step's event starts them.
  final String? route;

  String get seenId => 'tour.$id';
}

/// Flow ids reported by [guideFlowClosed].
const guideFlowHangarReader = 'hangar.reader';
const guideFlowRoomForm = 'rooms.form';
const _reader = guideFlowHangarReader, _roomForm = guideFlowRoomForm;

const guideTours = <String, GuideTourSpec>{
  'market': GuideTourSpec('market', GuideTourKind.tour, route: '/marketplace', [
    GuideTourStep('market.search'),
    GuideTourStep('market.offers'),
    GuideTourStep('market.publish'),
    GuideTourStep('market.trades'),
    GuideTourStep(null),
  ]),
  'overlay': GuideTourSpec('overlay', GuideTourKind.tour, route: '/overlay', [
    GuideTourStep('overlay.runtime'),
    GuideTourStep('overlay.presets'),
    GuideTourStep('overlay.sources'),
    GuideTourStep('overlay.groups'),
    GuideTourStep('overlay.preview'),
    GuideTourStep('overlay.groups'),
    // Edits save on their own; there is no save bar to point at.
    GuideTourStep(null),
  ]),
  'fleet': GuideTourSpec('fleet', GuideTourKind.tour, route: '/fleet', [
    GuideTourStep('fleet.overview'),
    GuideTourStep('fleet.members'),
    GuideTourStep('fleet.channel'),
    GuideTourStep('fleet.ships'),
    GuideTourStep('fleet.share'),
  ]),
  // Starts when the reader opens on the user's own Read hangar (at step 2).
  'hangar': GuideTourSpec('hangar', GuideTourKind.doIt, [
    // Entering the reader also opens the RSI page.
    GuideTourStep('hangar.read', until: 'hangar.readerOpened'),
    // Sign-in and the avatar click happen inside the RSI page, which the
    // reader cannot observe before reading starts: explained, not awaited.
    GuideTourStep(
      'hangar.browser',
      interactive: true,
      card: 'hangar.results',
      flow: _reader,
    ),
    GuideTourStep(
      'hangar.browser',
      interactive: true,
      card: 'hangar.results',
      flow: _reader,
    ),
    GuideTourStep(
      'hangar.action',
      until: 'hangar.readDone',
      card: 'hangar.results',
      flow: _reader,
    ),
    GuideTourStep('hangar.results', card: 'hangar.results', flow: _reader),
    GuideTourStep('hangar.save', until: 'hangar.saved', flow: _reader),
  ]),
  // Starts when the create form opens on the user's own click (at step 2).
  'rooms': GuideTourSpec('rooms', GuideTourKind.doIt, [
    GuideTourStep('rooms.create', until: 'rooms.formOpened'),
    GuideTourStep(
      'rooms.form.basic',
      interactive: true,
      beside: 'rooms.form',
      flow: _roomForm,
    ),
    GuideTourStep(
      'rooms.form.tags',
      interactive: true,
      beside: 'rooms.form',
      flow: _roomForm,
    ),
    GuideTourStep(
      'rooms.form.admission',
      interactive: true,
      beside: 'rooms.form',
      flow: _roomForm,
    ),
    GuideTourStep(
      'rooms.form.create',
      until: 'rooms.created',
      beside: 'rooms.form',
      flow: _roomForm,
    ),
    GuideTourStep('rooms.applications'),
  ]),
};
