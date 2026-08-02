using System.Windows.Input;

namespace StarBridge.Desktop;

internal enum OverlayHotkeyBindingState
{
    Disabled,
    Ready,
    Invalid,
    ModifierRequired,
    Reserved,
    ConflictWithInformation
}

internal readonly record struct OverlayHotkeyChord(
    Key Key,
    uint VirtualKey,
    uint Modifiers)
{
    internal bool HasModifier =>
        (Modifiers & GameCompatibleHotkeyModifiers.SupportedMask) != 0;

    internal string StorageText => Format(" + ", compact: true);

    internal string DisplayText => Format(" + ", compact: false);

    internal GameCompatibleHotkeyBinding ToGameCompatibleBinding() =>
        new(VirtualKey, Modifiers & GameCompatibleHotkeyModifiers.SupportedMask);

    internal bool IsEquivalentTo(OverlayHotkeyChord other) =>
        VirtualKey == other.VirtualKey &&
        (Modifiers & GameCompatibleHotkeyModifiers.SupportedMask) ==
        (other.Modifiers & GameCompatibleHotkeyModifiers.SupportedMask);

    private string Format(string separator, bool compact)
    {
        var parts = new List<string>(5);
        if ((Modifiers & GameCompatibleHotkeyModifiers.Control) != 0)
        {
            parts.Add("Ctrl");
        }

        if ((Modifiers & GameCompatibleHotkeyModifiers.Alt) != 0)
        {
            parts.Add("Alt");
        }

        if ((Modifiers & GameCompatibleHotkeyModifiers.Shift) != 0)
        {
            parts.Add("Shift");
        }

        if ((Modifiers & GameCompatibleHotkeyModifiers.Windows) != 0)
        {
            parts.Add("Win");
        }

        parts.Add(Key.ToString());
        return string.Join(compact ? "+" : separator, parts);
    }
}

internal sealed record OverlayHotkeyBindingPlan(
    OverlayHotkeyBindingState InformationState,
    OverlayHotkeyChord? InformationHotkey,
    OverlayHotkeyBindingState MenuState,
    OverlayHotkeyChord? MenuHotkey)
{
    internal IReadOnlyList<GameCompatibleHotkeyRoute> CreateGameCompatibleRoutes(
        int informationCommandId,
        int menuCommandId)
    {
        var routes = new List<GameCompatibleHotkeyRoute>(2);
        if (InformationState == OverlayHotkeyBindingState.Ready &&
            InformationHotkey is { } informationHotkey)
        {
            routes.Add(new GameCompatibleHotkeyRoute(
                informationCommandId,
                informationHotkey.ToGameCompatibleBinding()));
        }

        if (MenuState == OverlayHotkeyBindingState.Ready &&
            MenuHotkey is { } menuHotkey)
        {
            routes.Add(new GameCompatibleHotkeyRoute(
                menuCommandId,
                menuHotkey.ToGameCompatibleBinding()));
        }

        return routes;
    }
}

internal static class OverlayHotkeyBindingPolicy
{
    internal static OverlayHotkeyBindingPlan Build(
        string? informationHotkeyText,
        bool informationEnabled,
        InGameMenuSettings menuSettings)
    {
        var informationParsed = TryParse(
            informationHotkeyText,
            out var informationHotkey);
        var informationState = !informationEnabled
            ? OverlayHotkeyBindingState.Disabled
            : informationParsed
                ? OverlayHotkeyBindingState.Ready
                : OverlayHotkeyBindingState.Invalid;

        var menuParsed = TryParse(
            menuSettings.Hotkey,
            out var menuHotkey);
        var menuState = ResolveMenuState(
            menuSettings.EnableHotkey,
            menuParsed,
            menuHotkey,
            informationState,
            informationHotkey);

        return new OverlayHotkeyBindingPlan(
            informationState,
            informationParsed ? informationHotkey : null,
            menuState,
            menuParsed ? menuHotkey : null);
    }

    internal static bool TryCapture(
        ModifierKeys modifiers,
        Key key,
        out OverlayHotkeyChord chord)
    {
        chord = default;
        if (IsModifierKey(key))
        {
            return false;
        }

        var normalizedModifiers = 0u;
        if (modifiers.HasFlag(ModifierKeys.Control))
        {
            normalizedModifiers |= GameCompatibleHotkeyModifiers.Control;
        }

        if (modifiers.HasFlag(ModifierKeys.Alt))
        {
            normalizedModifiers |= GameCompatibleHotkeyModifiers.Alt;
        }

        if (modifiers.HasFlag(ModifierKeys.Shift))
        {
            normalizedModifiers |= GameCompatibleHotkeyModifiers.Shift;
        }

        if (modifiers.HasFlag(ModifierKeys.Windows))
        {
            normalizedModifiers |= GameCompatibleHotkeyModifiers.Windows;
        }

        return TryCreate(key, normalizedModifiers, out chord);
    }

    internal static bool TryParse(
        string? text,
        out OverlayHotkeyChord chord)
    {
        chord = default;
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        var modifiers = 0u;
        var primaryKey = Key.None;
        foreach (var part in text.Split(
                     '+',
                     StringSplitOptions.RemoveEmptyEntries |
                     StringSplitOptions.TrimEntries))
        {
            if (part.Equals("Ctrl", StringComparison.OrdinalIgnoreCase) ||
                part.Equals("Control", StringComparison.OrdinalIgnoreCase))
            {
                modifiers |= GameCompatibleHotkeyModifiers.Control;
                continue;
            }

            if (part.Equals("Alt", StringComparison.OrdinalIgnoreCase))
            {
                modifiers |= GameCompatibleHotkeyModifiers.Alt;
                continue;
            }

            if (part.Equals("Shift", StringComparison.OrdinalIgnoreCase))
            {
                modifiers |= GameCompatibleHotkeyModifiers.Shift;
                continue;
            }

            if (part.Equals("Win", StringComparison.OrdinalIgnoreCase) ||
                part.Equals("Windows", StringComparison.OrdinalIgnoreCase))
            {
                modifiers |= GameCompatibleHotkeyModifiers.Windows;
                continue;
            }

            if (primaryKey != Key.None ||
                !Enum.TryParse(part, ignoreCase: true, out primaryKey))
            {
                return false;
            }
        }

        return TryCreate(primaryKey, modifiers, out chord);
    }

    private static OverlayHotkeyBindingState ResolveMenuState(
        bool enabled,
        bool parsed,
        OverlayHotkeyChord menuHotkey,
        OverlayHotkeyBindingState informationState,
        OverlayHotkeyChord informationHotkey)
    {
        if (!enabled)
        {
            return OverlayHotkeyBindingState.Disabled;
        }

        if (!parsed)
        {
            return OverlayHotkeyBindingState.Invalid;
        }

        if (IsReservedMenuHotkey(menuHotkey))
        {
            return OverlayHotkeyBindingState.Reserved;
        }

        if (!menuHotkey.HasModifier &&
            menuHotkey.Key is < Key.F1 or > Key.F12)
        {
            return OverlayHotkeyBindingState.ModifierRequired;
        }

        if (informationState == OverlayHotkeyBindingState.Ready &&
            menuHotkey.IsEquivalentTo(informationHotkey))
        {
            return OverlayHotkeyBindingState.ConflictWithInformation;
        }

        return OverlayHotkeyBindingState.Ready;
    }

    private static bool IsReservedMenuHotkey(OverlayHotkeyChord chord)
    {
        if (chord.Key == Key.Escape)
        {
            return true;
        }

        var hasAlt =
            (chord.Modifiers & GameCompatibleHotkeyModifiers.Alt) != 0;
        if (hasAlt && chord.Key is Key.Tab or Key.F4)
        {
            return true;
        }

        var hasControl =
            (chord.Modifiers & GameCompatibleHotkeyModifiers.Control) != 0;
        return hasAlt && hasControl && chord.Key == Key.Delete;
    }

    private static bool TryCreate(
        Key key,
        uint modifiers,
        out OverlayHotkeyChord chord)
    {
        chord = default;
        if (key == Key.None || IsModifierKey(key))
        {
            return false;
        }

        var virtualKey = KeyInterop.VirtualKeyFromKey(key);
        if (virtualKey == 0)
        {
            return false;
        }

        chord = new OverlayHotkeyChord(
            key,
            unchecked((uint)virtualKey),
            modifiers & GameCompatibleHotkeyModifiers.SupportedMask);
        return true;
    }

    private static bool IsModifierKey(Key key) =>
        key is Key.LeftCtrl or Key.RightCtrl or
            Key.LeftAlt or Key.RightAlt or
            Key.LeftShift or Key.RightShift or
            Key.LWin or Key.RWin;
}
