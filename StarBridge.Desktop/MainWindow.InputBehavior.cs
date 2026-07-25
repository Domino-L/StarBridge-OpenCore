using System.Windows.Threading;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void EmptyPromptTextBox_PreviewMouseLeftButtonDown(
        object sender,
        System.Windows.Input.MouseButtonEventArgs eventArgs)
    {
        if (sender is not System.Windows.Controls.TextBox textBox || !string.IsNullOrEmpty(textBox.Text))
        {
            return;
        }

        textBox.Focus();
        System.Windows.Input.Keyboard.Focus(textBox);
        textBox.CaretIndex = 0;
        eventArgs.Handled = true;

        _ = textBox.Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            () =>
            {
                if (string.IsNullOrEmpty(textBox.Text))
                {
                    textBox.CaretIndex = 0;
                }
            });
    }
}
