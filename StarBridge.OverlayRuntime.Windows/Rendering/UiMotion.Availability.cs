using System.Windows;
using System.Windows.Media;

namespace StarBridge.Desktop;

public static partial class UiMotion
{
    public static bool IsEnabled =>
        SystemParameters.ClientAreaAnimation && (RenderCapability.Tier >> 16) > 0;
}
