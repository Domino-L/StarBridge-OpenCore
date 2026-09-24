using System.Text.Json;
using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

internal static class InformationOverlayLayoutGeometryTests
{
    private const double Tolerance = 0.001;

    public static void RunAll()
    {
        var file = LoadConformanceFile();
        Equal(1, file.SchemaVersion, "supported conformance schema");

        foreach (var sample in file.ResolveCases)
        {
            var items = sample.Items.Select(CreateItem).ToArray();
            var original = InformationOverlayLayoutItem.SerializeMany(items);
            var resolved = InformationOverlayLayoutGeometry.ResolveItems(
                items,
                sample.SurfaceWidth,
                sample.SurfaceHeight);

            foreach (var expected in sample.Expected)
            {
                True(resolved.TryGetValue(expected.Key, out var actual),
                    $"{sample.Id} resolves {expected.Key}");
                Rect(expected.Value, actual, $"{sample.Id} {expected.Key}");
            }

            Equal(original, InformationOverlayLayoutItem.SerializeMany(items),
                $"{sample.Id} does not mutate persisted layout");
        }

        foreach (var sample in file.ApplyCases)
        {
            var item = CreateItem(sample.Item);
            InformationOverlayLayoutGeometry.ApplyRectToItem(
                item,
                CreateRect(sample.Rect),
                sample.SurfaceWidth,
                sample.SurfaceHeight);
            Values(
                sample.ExpectedNormalized,
                [item.X, item.Y, item.Width, item.Height],
                $"{sample.Id} normalized values");
            Rect(
                sample.ExpectedResolved,
                InformationOverlayLayoutGeometry.ResolveItemRect(
                    item,
                    sample.SurfaceWidth,
                    sample.SurfaceHeight),
                $"{sample.Id} resolved round trip");
        }

        foreach (var sample in file.EventCases)
        {
            True(Enum.TryParse<OverlayEventNotificationSide>(sample.Side, out var side),
                $"{sample.Id} side is valid");
            Rect(
                sample.Expected,
                InformationOverlayLayoutGeometry.ResolveEventNotificationRect(
                    sample.SurfaceWidth,
                    sample.SurfaceHeight,
                    side,
                    sample.NormalizedY,
                    sample.PreferredHeight,
                    sample.SnapSize),
                sample.Id);
        }

        foreach (var sample in file.SceneCases)
        {
            True(Enum.TryParse<OverlayScenePreference>(sample.Preference, out var preference),
                $"{sample.Id} preference is valid");
            True(Enum.TryParse<InformationOverlaySceneKind>(sample.ExpectedKind, out var expectedKind),
                $"{sample.Id} expected scene is valid");
            var actual = InformationOverlayRuntimeProjection.ResolveScene(
                preference,
                sample.HasCurrentPartyRoom);
            Equal(expectedKind, actual.Kind, $"{sample.Id} scene");
            Equal(sample.ExpectedFallback, actual.IsFallback, $"{sample.Id} fallback");
        }

        foreach (var sample in file.VisibilityCases)
        {
            var settings = InformationOverlayDefaults.DefaultSettings with
            {
                ShowNotice = sample.Settings.ShowNotice,
                ShowSquads = sample.Settings.ShowSquads,
                ShowMembers = sample.Settings.ShowMembers,
                ShowChat = sample.Settings.ShowChat,
                ShowCrosshair = sample.Settings.ShowCrosshair,
                ShowEventNotifications = sample.Settings.ShowEventNotifications
            };
            var actual = InformationOverlayRuntimeProjection.ResolveVisibility(
                settings,
                new InformationOverlayContentState(
                    sample.Content.NoticeHasContent,
                    sample.Content.ChatHasContent,
                    sample.Content.EventNotificationsHaveContent));
            Equal(sample.Expected.ShowNotice, actual.ShowNotice, $"{sample.Id} notice");
            Equal(sample.Expected.ShowSquads, actual.ShowSquads, $"{sample.Id} squads");
            Equal(sample.Expected.ShowMembers, actual.ShowMembers, $"{sample.Id} members");
            Equal(sample.Expected.ShowChat, actual.ShowChat, $"{sample.Id} chat");
            Equal(sample.Expected.ShowCrosshair, actual.ShowCrosshair, $"{sample.Id} crosshair");
            Equal(
                sample.Expected.ShowEventNotifications,
                actual.ShowEventNotifications,
                $"{sample.Id} event notifications");
        }
    }

    private static ConformanceFile LoadConformanceFile()
    {
        var path = Path.Combine(
            AppContext.BaseDirectory,
            "data",
            "information-overlay-layout-conformance-v1.json");
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        return JsonSerializer.Deserialize<ConformanceFile>(File.ReadAllText(path), options)
               ?? throw new InvalidOperationException("Overlay layout conformance file is empty.");
    }

    private static InformationOverlayLayoutItem CreateItem(LayoutInput input)
    {
        True(Enum.TryParse<OverlayHorizontalAnchor>(input.HorizontalAnchor, out var horizontal),
            $"{input.Key} horizontal anchor is valid");
        True(Enum.TryParse<OverlayVerticalAnchor>(input.VerticalAnchor, out var vertical),
            $"{input.Key} vertical anchor is valid");
        return new InformationOverlayLayoutItem(
            input.Key,
            input.X,
            input.Y,
            input.Width,
            input.Height,
            horizontal,
            vertical,
            input.IsLocked,
            input.TextOpacity,
            input.BackgroundOpacity);
    }

    private static InformationOverlayRect CreateRect(IReadOnlyList<double> values)
    {
        Equal(4, values.Count, "rectangle sample has four values");
        return new InformationOverlayRect(values[0], values[1], values[2], values[3]);
    }

    private static void Rect(
        IReadOnlyList<double> expected,
        InformationOverlayRect actual,
        string label) =>
        Values(expected, [actual.Left, actual.Top, actual.Width, actual.Height], label);

    private static void Values(
        IReadOnlyList<double> expected,
        IReadOnlyList<double> actual,
        string label)
    {
        Equal(expected.Count, actual.Count, $"{label} value count");
        for (var index = 0; index < expected.Count; index++)
        {
            if (Math.Abs(expected[index] - actual[index]) > Tolerance)
            {
                throw new InvalidOperationException(
                    $"{label}[{index}]: expected {expected[index]}, got {actual[index]}");
            }
        }
    }

    private static void True(bool value, string label)
    {
        if (!value)
        {
            throw new InvalidOperationException(label);
        }
    }

    private static void Equal<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"{label}: expected {expected}, got {actual}");
        }
    }

    private sealed record ConformanceFile(
        int SchemaVersion,
        List<ResolveCase> ResolveCases,
        List<ApplyCase> ApplyCases,
        List<EventCase> EventCases,
        List<SceneCase> SceneCases,
        List<VisibilityCase> VisibilityCases);

    private sealed record ResolveCase(
        string Id,
        double SurfaceWidth,
        double SurfaceHeight,
        List<LayoutInput> Items,
        Dictionary<string, List<double>> Expected);

    private sealed record ApplyCase(
        string Id,
        double SurfaceWidth,
        double SurfaceHeight,
        LayoutInput Item,
        List<double> Rect,
        List<double> ExpectedNormalized,
        List<double> ExpectedResolved);

    private sealed record EventCase(
        string Id,
        double SurfaceWidth,
        double SurfaceHeight,
        string Side,
        double NormalizedY,
        double PreferredHeight,
        double SnapSize,
        List<double> Expected);

    private sealed record SceneCase(
        string Id,
        string Preference,
        bool HasCurrentPartyRoom,
        string ExpectedKind,
        bool ExpectedFallback);

    private sealed record VisibilityCase(
        string Id,
        VisibilitySettings Settings,
        VisibilityContent Content,
        VisibilitySettings Expected);

    private sealed record VisibilitySettings(
        bool ShowNotice,
        bool ShowSquads,
        bool ShowMembers,
        bool ShowChat,
        bool ShowCrosshair,
        bool ShowEventNotifications);

    private sealed record VisibilityContent(
        bool NoticeHasContent,
        bool ChatHasContent,
        bool EventNotificationsHaveContent);

    private sealed record LayoutInput(
        string Key,
        double X,
        double Y,
        double Width,
        double Height,
        string HorizontalAnchor,
        string VerticalAnchor,
        bool IsLocked,
        double TextOpacity,
        double BackgroundOpacity);
}
