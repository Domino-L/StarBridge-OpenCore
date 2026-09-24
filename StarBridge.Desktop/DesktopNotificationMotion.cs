namespace StarBridge.Desktop;

using System.Windows;
using System.Windows.Media.Animation;
using System.Runtime.CompilerServices;
using System.Windows.Media;

internal static class DesktopNotificationMotion
{
    private sealed class Transition { internal long Version; }
    private static readonly ConditionalWeakTable<UIElement, Transition> Transitions = new();
    internal static bool Enabled(bool reduceMotion) => !reduceMotion && UiMotion.IsEnabled;

    internal static void EnterActivity(UIElement card, bool fromRight, bool enabled)
    {
        var translation = new TranslateTransform(enabled ? (fromRight ? 12 : -12) : 0, 0);
        card.RenderTransform = translation;
        card.Opacity = enabled ? 0 : 1;
        if (!enabled) return;
        translation.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(translation.X, 0, TimeSpan.FromMilliseconds(240)) {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }, FillBehavior = FillBehavior.HoldEnd
        });
        Fade(card, 1, 240, true);
    }

    internal static void ExitActivity(UIElement card, bool toRight, bool enabled, Action completed)
    {
        var translation = card.RenderTransform as TranslateTransform ?? new TranslateTransform();
        card.RenderTransform = translation;
        var from = translation.X;
        translation.BeginAnimation(TranslateTransform.XProperty, null);
        translation.X = enabled ? from : 0;
        if (enabled) {
            translation.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(from, toRight ? 8 : -8, TimeSpan.FromMilliseconds(180)) {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn }, FillBehavior = FillBehavior.HoldEnd
            }, HandoffBehavior.SnapshotAndReplace);
        }
        Fade(card, 0, 180, enabled, completed);
    }

    internal static void Cancel(UIElement target) {
        Transitions.GetOrCreateValue(target).Version++;
        target.BeginAnimation(UIElement.OpacityProperty, null);
    }

    // Opacity only: no moving HWND, clipping at work-area edges, or blurred notification text.
    // A new transition starts at the presented value, so close can interrupt entry smoothly.
    internal static void Fade(UIElement target, double to, int milliseconds, bool enabled, Action? completed = null)
    {
        var from = target.Opacity;
        Cancel(target);
        var transition = Transitions.GetOrCreateValue(target);
        var version = transition.Version;
        target.Opacity = enabled ? from : to;
        if (!enabled) { completed?.Invoke(); return; }
        var animation = new DoubleAnimation(from, to, TimeSpan.FromMilliseconds(milliseconds)) {
            EasingFunction = new CubicEase { EasingMode = to > from ? EasingMode.EaseOut : EasingMode.EaseIn },
            FillBehavior = FillBehavior.HoldEnd
        };
        animation.Completed += (_, _) => {
            if (transition.Version != version) return;
            target.Opacity = to;
            Cancel(target);
            completed?.Invoke();
        };
        target.BeginAnimation(UIElement.OpacityProperty, animation, HandoffBehavior.SnapshotAndReplace);
    }
}
