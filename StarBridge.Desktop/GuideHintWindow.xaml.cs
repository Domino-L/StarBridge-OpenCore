using System.Windows;
using System.Windows.Input;

namespace StarBridge.Desktop;

public partial class GuideHintWindow : Window
{
    public GuideHintWindow(string title, string message)
    {
        InitializeComponent();
        HintTitleText.Text = title;
        HintMessageText.Text = message;
    }

    private void OkButton_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }
}
