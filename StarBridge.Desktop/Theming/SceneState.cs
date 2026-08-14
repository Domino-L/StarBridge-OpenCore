using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using MediaColor = System.Windows.Media.Color;

namespace StarBridge.Desktop.Theming;

/// <summary>
/// Holds the animated colours for the active workspace scene.
///
/// This Animatable must never be placed in a ResourceDictionary. Consumers use
/// an inline brush bound to these colours through <see cref="Current"/>, avoiding
/// WPF sealing the animation target when resources are inserted into a dictionary.
/// </summary>
public sealed class SceneState : Animatable
{
    public static SceneState Current { get; } = new();

    public static readonly DependencyProperty AccentColorProperty =
        DependencyProperty.Register(
            nameof(AccentColor),
            typeof(MediaColor),
            typeof(SceneState),
            new PropertyMetadata(MediaColor.FromRgb(0x3E, 0x8F, 0xBF)));

    public static readonly DependencyProperty AmbientColorProperty =
        DependencyProperty.Register(
            nameof(AmbientColor),
            typeof(MediaColor),
            typeof(SceneState),
            new PropertyMetadata(MediaColor.FromRgb(0x16, 0x30, 0x3F)));

    public MediaColor AccentColor
    {
        get
        {
            VerifyAccess();
            return (MediaColor)GetValue(AccentColorProperty);
        }
        set
        {
            VerifyAccess();
            SetValue(AccentColorProperty, value);
        }
    }

    public MediaColor AmbientColor
    {
        get
        {
            VerifyAccess();
            return (MediaColor)GetValue(AmbientColorProperty);
        }
        set
        {
            VerifyAccess();
            SetValue(AmbientColorProperty, value);
        }
    }

    protected override bool FreezeCore(bool isChecking) => false;

    protected override Freezable CreateInstanceCore() => new SceneState();
}
