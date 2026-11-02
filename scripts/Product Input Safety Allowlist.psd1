@{
    # Exact reviewed references only. No directory or whole-file exemptions.
    # Changing the target, message, arguments, or count requires review.
    # RegisterHotKey keeps the chord from other programs, so it stays behind an
    # off-by-default user choice in these files. Hooks have no allowance at all.
    # The only queue attachment: the menu's retry after Windows refuses it the foreground
    # with the game in front, released at once. The user's decision of 2026-11-01. Each
    # whole line must appear exactly once, so the attach and its release stay a pair inside
    # the one helper. The second file is a test fixture that does not ship.
    QueueAttachmentHelperFile = 'StarBridge.Flutter/windows/runner/menu_overlay_window.cpp'
    QueueAttachmentReferences = @{
        'StarBridge.Flutter/windows/runner/menu_overlay_window.cpp' = @(
            '      attached_(target && current != target && AttachThreadInput(current, target, TRUE)) {}'
            '  ~ScopedMenuThreadInput() { if (attached_) AttachThreadInput(current_, target_, FALSE); }'
        )
        # The notice that tells users about the call names it; text only, no call.
        'StarBridge.Flutter/lib/app/localization/help_support_strings.dart' = @(
            "const _menuFocusCall = 'AttachThreadInput';"
        )
        'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp' = @(
            '#define AttachThreadInput ProbeAttachThreadInput'
        )
    }
    # The menu screenshot tool captures only after a user click. The WPF file is the
    # old client's tool and is not in the installer.
    # A game handle is opened only here: once per new PID, query rights, closed at once.
    OpenProcessFile = 'StarBridge.HostRuntime/Presence/GameProcessSnapshot.cs'
    # Process.StartTime opens the process, so this stays out of every release path.
    TryGetStartFiles = @(
        'StarBridge.Desktop/StarCitizenProcessProbe.cs'
        'StarBridge.Desktop/MainWindow.RuntimePresence.cs'
    )
    ScreenCaptureFiles = @(
        'StarBridge.Flutter/windows/runner/menu_local_tools.cpp'
        'StarBridge.Desktop/InGameMenuToolSupport.cs'
    )
    RegisterHotKeyCopyFiles = @(
        'StarBridge.Flutter/lib/app/localization/overlay_workspace_en_strings.dart'
        'StarBridge.Flutter/lib/app/localization/overlay_workspace_zh_cn_strings.dart'
        'StarBridge.Flutter/lib/app/localization/overlay_workspace_zh_tw_strings.dart'
    )
    RegisterHotKeyFiles = @(
        'StarBridge.Desktop/NativeInformationOverlayRuntime.cs'
        'StarBridge.Desktop/NativeInformationOverlayRuntime.SafeHotkeys.cs'
        'StarBridge.Desktop/MainWindow.OverlayRuntime.cs'
    )
    # Exact source/destination pairs in open-core-manifest.json. Both names share
    # the same reviewed content and count; no directory prefix exemption.
    ExportedFiles = @{
        'StarBridge.OverlayRuntime.Windows/Rendering/GameCompatibleHotkeyListener.cs' = 'StarBridge.Desktop/GameCompatibleHotkeyListener.cs'
        'StarBridge.OverlayRuntime.Windows/Rendering/StarCitizenProcessProbe.cs' = 'StarBridge.Desktop/StarCitizenProcessProbe.cs'
        'StarBridge.OverlayRuntime.Windows/Rendering/NativeInformationOverlayRuntime.cs' = 'StarBridge.Desktop/NativeInformationOverlayRuntime.cs'
        'StarBridge.OverlayRuntime.Windows/Rendering/NativeInformationOverlayRuntime.SafeHotkeys.cs' = 'StarBridge.Desktop/NativeInformationOverlayRuntime.SafeHotkeys.cs'
    }
    Entries = @(
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsCommunityLogoPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero)'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsCommunityLogoPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam)'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsFirstUseLogPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(window, 0x0010, 0, 0)'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsFirstUseLogPicker.cs'
            Symbol = 'PostMessageW'
            Reference = '[DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "PostMessageW")]'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsFirstUseLogPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(nint window, uint message, nint wParam, nint lParam)'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsLegacyHangarFilePicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(window, 0x0010, 0, 0)'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsLegacyHangarFilePicker.cs'
            Symbol = 'PostMessageW'
            Reference = '[DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "PostMessageW")]'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.OverlayRuntime.Windows/WindowsLegacyHangarFilePicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(nint window, uint message, nint wParam, nint lParam)'
            Reason = 'Closes this process own file dialog (WM_CLOSE) when the request is cancelled; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/GameCompatibleHotkeyListener.cs'
            Symbol = 'PostThreadMessage'
            Reference = 'PostThreadMessage(listenerThreadId, WmQuit, UIntPtr.Zero, IntPtr.Zero)'
            Reason = 'Internal hotkey command dispatch and listener-thread shutdown; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/GameCompatibleHotkeyListener.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage( targetWindow, targetMessage, new UIntPtr(unchecked((uint)commandId)), IntPtr.Zero)'
            Reason = 'Internal hotkey command dispatch and listener-thread shutdown; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/GameCompatibleHotkeyListener.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage( IntPtr window, uint message, UIntPtr wParam, IntPtr lParam)'
            Reason = 'Internal hotkey command dispatch and listener-thread shutdown; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/GameCompatibleHotkeyListener.cs'
            Symbol = 'PostThreadMessage'
            Reference = 'PostThreadMessage( uint threadId, uint message, UIntPtr wParam, IntPtr lParam)'
            Reason = 'Internal hotkey command dispatch and listener-thread shutdown; includes P/Invoke declarations.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/InGameFleetModels.cs'
            Symbol = 'SendMessage'
            Reference = 'SendMessage'
            Reason = 'Chat action enum named SendMessage; not a Windows API.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/InGameFleetWindow.xaml.cs'
            Symbol = 'SendMessage'
            Reference = '? InGameFleetMemberAction.SendMessage'
            Reason = 'Chat action enum reference; not a Windows API.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/InGameFleetWindow.xaml.cs'
            Symbol = 'SendMessage'
            Reference = 'requestedAction == InGameFleetMemberAction.SendMessage &&'
            Reason = 'Chat action enum reference; not a Windows API.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/InGameMenuCoordinator.cs'
            Symbol = 'SendMessage'
            Reference = 'if (e.Action == InGameFleetMemberAction.SendMessage)'
            Reason = 'Chat action enum reference; not a Windows API.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/MainWindow.InGameMenu.cs'
            Symbol = 'SendMessage'
            Reference = 'if (e.Action != InGameFleetMemberAction.SendMessage ||'
            Reason = 'Chat action enum reference; not a Windows API.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/SmallApplicationIcons.cs'
            Symbol = 'SendMessage'
            Reference = 'SendMessage(_window, 0x0080, IntPtr.Zero, next.Handle)'
            Reason = 'Set or clear the application window icon; includes P/Invoke declaration.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/SmallApplicationIcons.cs'
            Symbol = 'SendMessage'
            Reference = 'SendMessage(_window, 0x0080, IntPtr.Zero, IntPtr.Zero)'
            Reason = 'Set or clear the application window icon; includes P/Invoke declaration.'
            Count = 1
        }
        @{
            File = 'StarBridge.Desktop/SmallApplicationIcons.cs'
            Symbol = 'SendMessage'
            Reference = 'SendMessage(IntPtr window, int message, IntPtr wparam, IntPtr lparam)'
            Reason = 'Set or clear the application window icon; includes P/Invoke declaration.'
            Count = 1
        }
        @{
            File = 'StarBridge.NativeHost/WindowsGameplayExportPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(dialog, 0x0010, 0, 0)'
            Reason = 'Cancel the client-owned save dialog with WM_CLOSE (0x0010); includes P/Invoke and EntryPoint.'
            Count = 1
        }
        @{
            File = 'StarBridge.NativeHost/WindowsGameplayExportPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(window, 0x0010, 0, 0)'
            Reason = 'Cancel the client-owned save dialog with WM_CLOSE (0x0010); includes P/Invoke and EntryPoint.'
            Count = 1
        }
        @{
            File = 'StarBridge.NativeHost/WindowsGameplayExportPicker.cs'
            Symbol = 'PostMessageW'
            Reference = '[DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "PostMessageW")]'
            Reason = 'Cancel the client-owned save dialog with WM_CLOSE (0x0010); includes P/Invoke and EntryPoint.'
            Count = 1
        }
        @{
            File = 'StarBridge.NativeHost/WindowsGameplayExportPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(nint window, uint message, nuint wParam, nint lParam)'
            Reason = 'Cancel the client-owned save dialog with WM_CLOSE (0x0010); includes P/Invoke and EntryPoint.'
            Count = 1
        }
        @{
            File = 'StarBridge.NativeHost/WindowsStorageFolderPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(handle, 0x10, 0, 0)'
            Reason = 'Cancel the client-owned folder picker with WM_CLOSE (0x10); includes P/Invoke and EntryPoint.'
            Count = 2
        }
        @{
            File = 'StarBridge.NativeHost/WindowsStorageFolderPicker.cs'
            Symbol = 'PostMessageW'
            Reference = '[DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "PostMessageW")]'
            Reason = 'Cancel the client-owned folder picker with WM_CLOSE (0x10); includes P/Invoke and EntryPoint.'
            Count = 1
        }
        @{
            File = 'StarBridge.NativeHost/WindowsStorageFolderPicker.cs'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(nint window, uint message, nint wParam, nint lParam)'
            Reason = 'Cancel the client-owned folder picker with WM_CLOSE (0x10); includes P/Invoke and EntryPoint.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_NCACTIVATE, TRUE, 0)'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_CLOSE, 0, 0)'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 2
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_NCHITTEST, 0, point(80, 18))'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(GetWindow(window, GW_CHILD), WM_NCHITTEST, 0, point(80, 18))'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_NCHITTEST, 0, point(1, 1))'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_NCHITTEST, 0, MAKELPARAM(outer.right - MulDiv(22, dpi, 96), outer.top + MulDiv(18, dpi, 96)))'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_NCHITTEST, 0, point(80, 100))'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/friends_window_bridge_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_GETMINMAXINFO, 0, reinterpret_cast<LPARAM>(&limits))'
            Reason = 'Owned test window activation, hit-test, sizing and close assertions; no key/button delivery.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/installer_shutdown_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(hwnd, WM_CLOSE, 0, 0)'
            Reason = 'Owned test window close and installer end-session lifecycle assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/installer_shutdown_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(hwnd, WM_QUERYENDSESSION, 0, ENDSESSION_CLOSEAPP)'
            Reason = 'Owned test window close and installer end-session lifecycle assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/installer_shutdown_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(hwnd, WM_ENDSESSION, FALSE, ENDSESSION_CLOSEAPP)'
            Reason = 'Owned test window close and installer end-session lifecycle assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/installer_shutdown_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(hwnd, WM_ENDSESSION, TRUE, ENDSESSION_CLOSEAPP)'
            Reason = 'Owned test window close and installer end-session lifecycle assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_image_tools_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(pinned,WM_NCHITTEST,0,0)'
            Reason = 'Owned pinned-window hit-test and activation refusal assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_image_tools_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(pinned,WM_MOUSEACTIVATE,0,0)'
            Reason = 'Owned pinned-window hit-test and activation refusal assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(unrelated_target))'
            Reason = 'Synthetic fixture activation and timeout assertions; no keyboard or mouse input messages.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(focus_target, WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(unrelated_target))'
            Reason = 'Synthetic fixture activation and timeout assertions; no keyboard or mouse input messages.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(menu.handle(), WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(game_target))'
            Reason = 'Synthetic fixture activation and timeout assertions; no keyboard or mouse input messages.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(menu.handle(), WM_ACTIVATE, WA_INACTIVE, reinterpret_cast<LPARAM>(unrelated_target))'
            Reason = 'Synthetic fixture activation and timeout assertions; no keyboard or mouse input messages.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(menu.handle(), WM_TIMER, 0x534f, 0)'
            Reason = 'Synthetic fixture activation and timeout assertions; no keyboard or mouse input messages.'
            Count = 2
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(menu.handle(), WM_ACTIVATE, WA_ACTIVE, 0)'
            Reason = 'Synthetic fixture activation and timeout assertions; no keyboard or mouse input messages.'
            Count = 2
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_preview.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(label, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE)'
            Reason = 'Set fonts on preview-owned child controls.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_preview.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(button, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE)'
            Reason = 'Set fonts on preview-owned child controls.'
            Count = 2
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_preview.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(status_label, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE)'
            Reason = 'Set fonts on preview-owned child controls.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_window_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(created, WM_ACTIVATE, WA_INACTIVE, 0)'
            Reason = 'Owned test window activation, frame timeout and close assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_window_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(created, WM_TIMER, 0x534d, 0)'
            Reason = 'Owned test window activation, frame timeout and close assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/menu_overlay_window_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(created, WM_CLOSE, 0, 0)'
            Reason = 'Owned test window activation, frame timeout and close assertions.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/small_icon_dpi_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_GETICON, kind, dpi)'
            Reason = 'Owned test window icon queries and DPI-change assertion.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/small_icon_dpi_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(hwnd, WM_DPICHANGED, MAKELONG(192, 192), reinterpret_cast<LPARAM>(&rect))'
            Reason = 'Owned test window icon queries and DPI-change assertion.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/tray_surface_runtime_test.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(owner, WM_ACTIVATE, WA_INACTIVE, 0)'
            Reason = 'Owned fixture activation and private tray lifecycle/timeout notifications.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/tray_surface_runtime_test.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(panel, WM_TIMER, 0x5343, 0)'
            Reason = 'Owned fixture activation and private tray lifecycle/timeout notifications.'
            Count = 3
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tests/tray_surface_runtime_test.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(panel, WM_APP + 0x71, 1, 0)'
            Reason = 'Owned fixture activation and private tray lifecycle/timeout notifications.'
            Count = 2
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/application_lifecycle_bridge.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(window_, WM_CLOSE, 0, 0)'
            Reason = 'Close the application-owned window after an explicit exit request.'
            Count = 2
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/flutter_window.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(GetHandle(), SmallIconVariantChangedMessage(), 0, 0)'
            Reason = 'Application-owned window icon, close, and HTCAPTION title-bar drag from beginDrag.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/flutter_window.cpp'
            Symbol = 'SendMessage'
            Reference = 'SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0)'
            Reason = 'Application-owned window icon, close, and HTCAPTION title-bar drag from beginDrag.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/flutter_window.cpp'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(GetHandle(), WM_CLOSE, 0, 0)'
            Reason = 'Application-owned window icon, close, and HTCAPTION title-bar drag from beginDrag.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/flutter_window.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(next))'
            Reason = 'Application-owned window icon, close, and HTCAPTION title-bar drag from beginDrag.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/flutter_window.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(GetHandle(), WM_SETICON, ICON_BIG, 0)'
            Reason = 'Application-owned window icon, close, and HTCAPTION title-bar drag from beginDrag.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/friends_window_bridge.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window_, WM_SETICON, ICON_SMALL, SendMessageW(owner_, WM_GETICON, ICON_SMALL, 0))'
            Reason = 'App social window icon and private first-frame/viewport notifications.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/friends_window_bridge.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(owner_, WM_GETICON, ICON_SMALL, 0)'
            Reason = 'App social window icon and private first-frame/viewport notifications.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/friends_window_bridge.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(window, kFrameReady, 0, 0)'
            Reason = 'App social window icon and private first-frame/viewport notifications.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/friends_window_bridge.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(window, kViewportChanged, 0, 0)'
            Reason = 'App social window icon and private first-frame/viewport notifications.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/main.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(existing, RegisterWindowMessageW(kActivateInstanceMessage), 0, 0)'
            Reason = 'Activate a matching StarBridge instance with its registered private notification; no input message.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/menu_overlay_bridge.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(hwnd, kFrameReady, static_cast<WPARAM>(generation), 0)'
            Reason = 'Private frame-ready notification to the owned overlay window.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/native_host_bridge.cpp'
            Symbol = 'PostMessage'
            Reference = 'PostMessage(window_, kPipeEventMessage, 0, reinterpret_cast<LPARAM>(raw))'
            Reason = 'Private pipe-event notification to the application-owned bridge window.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/tray_surface_bridge.cpp'
            Symbol = 'PostMessageW'
            Reference = 'PostMessageW(window, kFrameReady, static_cast<WPARAM>(token), 0)'
            Reason = 'Private frame-ready notification to the owned tray surface.'
            Count = 1
        }
        @{
            File = 'StarBridge.Flutter/windows/runner/win32_window.cpp'
            Symbol = 'SendMessageW'
            Reference = 'SendMessageW(window_handle_, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(taskbar_icon_))'
            Reason = 'Set the icon of the application-owned window.'
            Count = 1
        }
    )
}
