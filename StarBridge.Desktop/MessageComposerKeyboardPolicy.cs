using System.Windows.Input;

namespace StarBridge.Desktop;

internal enum MessageComposerKeyAction
{
    None,
    Send,
    InsertLineBreak,
}

internal static class MessageComposerKeyboardPolicy
{
    public static MessageComposerKeyAction Resolve(Key key, ModifierKeys modifiers) =>
        key == Key.Enter
            ? modifiers.HasFlag(ModifierKeys.Shift)
                ? MessageComposerKeyAction.InsertLineBreak
                : MessageComposerKeyAction.Send
            : MessageComposerKeyAction.None;
}
