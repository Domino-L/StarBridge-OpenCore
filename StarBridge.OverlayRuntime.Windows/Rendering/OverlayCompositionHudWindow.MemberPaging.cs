using Vortice.Direct2D1;

namespace StarBridge.Desktop;

/// <summary>
/// Member pages: indicator, group dividers, the page flip and the row change cue.
/// Motion runs only while a flip or cue is in progress and never when the
/// animation frame rate is Off; pinned rows and the header never move.
/// </summary>
internal sealed partial class OverlayCompositionHudWindow
{
    private const double MemberFlipOutMs = 180;
    private const double MemberFlipOutStaggerMs = 25;
    private const double MemberFlipInMs = 240;
    private const double MemberFlipInStaggerMs = 30;
    private const float MemberRowPitch = 35f;
    private const float MemberDotSize = OverlayMemberPageIndicatorLayout.DotSize;
    private const float MemberDotActiveWidth = OverlayMemberPageIndicatorLayout.ActiveWidth;
    private const float MemberDotGap = OverlayMemberPageIndicatorLayout.Gap;

    // Relevance reads as the same green as an in-game status in every appearance;
    // some skins theme Palette.Online (NightShadow's is red, which reads as an alert).
    private static readonly HudColor MemberRelevantColor = FromBrush(StatusPalette.SuccessBrush, HudColor.FromRgb(121, 255, 158));

    private DateTimeOffset _memberFlipStartedAtUtc = DateTimeOffset.MinValue;
    private IReadOnlyList<OverlayCompositionMemberRow> _memberFlipOutgoing = [];

    private static bool IsRotatingMemberRow(OverlayCompositionMemberRow row) =>
        row.Group is not OverlayRosterGroup.Pinned;

    private void ObserveMemberFlip(OverlayCompositionFrameState? previous, OverlayCompositionFrameState next)
    {
        // Authorization/source invalidation precedes the sequence fast path.
        // An authorization reset is never an animated handoff from old rows.
        if (previous is null || previous.AppearanceEpoch != next.AppearanceEpoch ||
            previous.MemberPaging.AuthorizationGeneration != next.MemberPaging.AuthorizationGeneration ||
            next.MemberRows.Count == 0 || next.AnimationFrameRate == OverlayAnimationFrameRate.Off || !next.ShowMembers)
        {
            ResetMemberFlip();
            return;
        }

        if (previous.MemberPaging.FlipSequence == next.MemberPaging.FlipSequence)
        {
            return;
        }

        _memberFlipOutgoing = previous.MemberRows.Where(IsRotatingMemberRow).ToArray();
        _memberFlipStartedAtUtc = DateTimeOffset.UtcNow;
    }

    private void ResetMemberFlip()
    {
        _memberFlipStartedAtUtc = DateTimeOffset.MinValue;
        _memberFlipOutgoing = [];
    }

    private double MemberFlipOutTotalMs() =>
        _memberFlipOutgoing.Count == 0 ? 0 : MemberFlipOutMs + MemberFlipOutStaggerMs * (_memberFlipOutgoing.Count - 1);

    private double MemberFlipTotalMs(OverlayCompositionFrameState state)
    {
        var incoming = state.MemberRows.Count(IsRotatingMemberRow);
        return MemberFlipOutTotalMs() + MemberFlipInMs + MemberFlipInStaggerMs * Math.Max(0, incoming - 1);
    }

    private bool IsMemberMotionActive()
    {
        if (_state is not { ShowMembers: true } state || state.AnimationFrameRate == OverlayAnimationFrameRate.Off)
        {
            ResetMemberFlip();
            return false;
        }

        var now = DateTimeOffset.UtcNow;
        if (_memberFlipStartedAtUtc != DateTimeOffset.MinValue &&
            (now - _memberFlipStartedAtUtc).TotalMilliseconds < MemberFlipTotalMs(state) + 40)
        {
            return true;
        }
        if (_memberFlipStartedAtUtc != DateTimeOffset.MinValue) ResetMemberFlip();

        return state.MemberRows.Any(row =>
            row.CueStartedAtUtc is { } started && now - started < OverlayMemberPagingTracker.CueDuration);
    }

    private float MemberPageIndicatorWidth(OverlayCompositionFrameState state)
    {
        var left = (float)state.MembersRect.Left + (state.NightShadowStyle ? 28 : 20);
        return ResolveMemberPageIndicator(state, Math.Max(0, (float)state.MembersRect.Right - left - 28), _titleFormat).Width;
    }

    private OverlayMemberPageIndicatorLayout ResolveMemberPageIndicator(OverlayCompositionFrameState state,
        float headerWidth, Vortice.DirectWrite.IDWriteTextFormat? titleFormat)
    {
        var titleSpace = Math.Min(headerWidth * 0.5f, Math.Max(32, MeasureTextWidth(state.MembersTitle, titleFormat, 48) + 8));
        var sourceSpace = Math.Min(headerWidth * 0.35f, SourceLabelSpace(state.SourceLabels.Members));
        var label = $"{state.MemberPaging.PageIndex + 1}/{state.MemberPaging.PageCount}";
        var labelWidth = Math.Max(OverlayMemberPageIndicatorLayout.MinimumLabelWidth,
            MathF.Ceiling(MeasureTextWidth(label, _mutedRightFormat, label.Length * 7) + 2));
        return OverlayMemberPageIndicatorLayout.Resolve(state.MemberPaging.PageIndex, state.MemberPaging.PageCount,
            Math.Max(0, headerWidth - titleSpace - sourceSpace), labelWidth);
    }

    private void DrawMemberPageIndicator(ID2D1RenderTarget target, OverlayCompositionFrameState state,
        float right, float top, double textOpacity, OverlayMemberPageIndicatorLayout layout)
    {
        var paging = state.MemberPaging;
        if (layout.Width <= 0)
        {
            return;
        }

        var x = right - layout.Width;
        for (var index = 0; index < layout.Pages.Count; index++)
        {
            var page = layout.Pages[index];
            if (page is null)
            {
                var before = index > 0 ? layout.Pages[index - 1] ?? -1 : -1;
                var after = index + 1 < layout.Pages.Count ? layout.Pages[index + 1] ?? paging.PageCount : paging.PageCount;
                var pending = paging.PendingPages.Any(value => value > before && value < after);
                DrawText(target, "…", _mutedFormat, x, top + 1, OverlayMemberPageIndicatorLayout.EllipsisWidth, 14,
                    pending ? MemberRelevantColor : state.Palette.Muted, textOpacity * 0.6);
                x += OverlayMemberPageIndicatorLayout.EllipsisWidth + MemberDotGap;
                continue;
            }
            var active = page == paging.PageIndex;
            var width = active ? MemberDotActiveWidth : MemberDotSize;
            // A page holding an unseen relevant change carries the relevance colour until shown.
            var color = active ? state.Palette.Title
                : paging.PendingPages.Contains(page.Value) ? MemberRelevantColor
                : state.Palette.Muted;
            FillRect(target, x, top + 6, width, MemberDotSize, color, textOpacity * (active ? 1 : 0.6));
            x += width + MemberDotGap;
        }

        DrawText(target, layout.Label, _mutedRightFormat, right - layout.LabelWidth - (layout.Pages.Count > 0 ? 1 : 0), top + 1,
            layout.LabelWidth, 14, state.Palette.Muted, textOpacity);
    }

    private void DrawMemberRows(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        float left,
        float rowY,
        float contentWidth,
        float nameWidth,
        double textOpacity)
    {
        var now = DateTimeOffset.UtcNow;
        var motion = state.AnimationFrameRate != OverlayAnimationFrameRate.Off;
        var elapsed = motion && _memberFlipStartedAtUtc != DateTimeOffset.MinValue
            ? (now - _memberFlipStartedAtUtc).TotalMilliseconds
            : double.MaxValue;
        var outTotal = MemberFlipOutTotalMs();
        var outPhase = elapsed < outTotal;
        var flipping = elapsed < MemberFlipTotalMs(state);
        var rows = state.MemberRows.Where(row => !IsRotatingMemberRow(row))
            .Concat(outPhase ? _memberFlipOutgoing : state.MemberRows.Where(IsRotatingMemberRow));

        OverlayRosterGroup? previousGroup = null;
        var rotatingIndex = 0;
        foreach (var row in rows)
        {
            float offset = 0;
            double alpha = 1;
            if (flipping && IsRotatingMemberRow(row))
            {
                if (outPhase)
                {
                    var t = Math.Clamp((elapsed - rotatingIndex * MemberFlipOutStaggerMs) / MemberFlipOutMs, 0, 1);
                    offset = (float)(-8 * t * t);
                    alpha = 1 - t;
                }
                else
                {
                    var t = Math.Clamp((elapsed - outTotal - rotatingIndex * MemberFlipInStaggerMs) / MemberFlipInMs, 0, 1);
                    var eased = 1 - Math.Pow(1 - t, 3);
                    offset = (float)(10 * (1 - eased));
                    alpha = eased;
                }

                rotatingIndex++;
            }

            if (previousGroup is { } before && row.Group is { } group && group != before)
            {
                // A hairline in the 4px gap between rows; the pinned zone ends in the alert colour.
                var color = before == OverlayRosterGroup.Pinned ? state.Palette.Alert : state.Palette.Title;
                DrawLine(target, left, rowY - 2, left + contentWidth, rowY - 2, color, textOpacity * alpha * 0.4, 1);
            }

            previousGroup = row.Group ?? previousGroup;
            DrawMemberCue(target, state, row, left, rowY + offset, contentWidth, now, textOpacity * alpha);
            var opacity = textOpacity * alpha;
            var y = rowY + offset;
            // Status is the dot before the name; the place reads as text on the right;
            // the ship sits under the name. Hiding member status hides the dot.
            var nameLeft = state.HideMemberStatus || row.Key is null ? left : left + 14;
            var placeLeft = nameLeft + nameWidth;
            if (!state.HideMemberStatus && row.Presence is { } presence)
            {
                target.FillEllipse(new Ellipse(new System.Numerics.Vector2(left + 4, y + 9), 3.5f, 3.5f), GetBrush(target, PresenceDotColor(presence), opacity));
            }
            DrawText(
                target,
                row.DisplayName,
                _textFormat,
                nameLeft,
                y,
                nameWidth,
                18,
                state.Palette.Text,
                opacity);
            DrawText(target, row.Location, _textRightFormat, placeLeft, y, left + contentWidth - placeLeft, 18,
                state.Palette.Text, opacity * 0.9);
            if (!string.Equals(row.Ship, row.Location, StringComparison.Ordinal))
            {
                DrawText(target, row.Ship, _mutedFormat, nameLeft, y + 17, contentWidth - (nameLeft - left), 14, state.Palette.Muted, opacity);
            }
            rowY += MemberRowPitch;
        }
    }

    private void DrawMemberCue(ID2D1RenderTarget target, OverlayCompositionFrameState state,
        OverlayCompositionMemberRow row, float left, float y, float contentWidth, DateTimeOffset now, double opacity)
    {
        if (state.AnimationFrameRate == OverlayAnimationFrameRate.Off || row.CueStartedAtUtc is not { } started)
        {
            return;
        }

        var t = (now - started).TotalMilliseconds / OverlayMemberPagingTracker.CueDuration.TotalMilliseconds;
        if (t is < 0 or >= 1)
        {
            return;
        }

        // Hold briefly, then fade out. Same-server and same-location rows cue in the relevance colour.
        var strength = t < 0.14 ? 1 : 1 - (t - 0.14) / 0.86;
        var color = row.Group is OverlayRosterGroup.SameServer or OverlayRosterGroup.SameLocation
            ? MemberRelevantColor
            : state.Palette.Title;
        FillRect(target, left - 6, y - 2, contentWidth + 12, 33, color, opacity * 0.22 * strength);
        FillRect(target, left - 6, y - 2, 3, 33, color, opacity * strength);
    }
}
