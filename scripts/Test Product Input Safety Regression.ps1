param()
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Test Product Input Safety.ps1') -LibraryOnly
$fixtureBase = Join-Path $repositoryRoot '.artifacts'
$fixture = Join-Path $fixtureBase ('cx-input-safety-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = 0
$failed = 0

function Test-InputCase([string]$Name, [string]$File, [string]$Text, [bool]$ShouldPass) {
    $path = Join-Path $fixture $File
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $Text, $utf8)
    $actualPass = $true
    $errorText = ''
    try { Invoke-ProductInputSafety $fixture 6>$null }
    catch { $actualPass = $false; $errorText = $_.Exception.Message }
    finally { Remove-Item -LiteralPath $path -Force }
    if ($actualPass -eq $ShouldPass -and ($actualPass -or $errorText -like 'Product input safety failed:*')) {
        $script:passed++
        Write-Output "PASS $Name"
    } else {
        $script:failed++
        Write-Output "FAIL ${Name}: expected=$ShouldPass actual=$actualPass $errorText"
    }
}

try {
    foreach ($symbol in @('SendInput','keybd_event','mouse_event','SendKeys','InputSimulator',
        'NtUserSendInput','INPUT_KEYBOARD','INPUT_MOUSE','SetCursorPos','CreateRemoteThread',
        'WriteProcessMemory','LLKHF_INJECTED')) {
        Test-InputCase $symbol 'StarBridge.Core/fixture.cs' "void Run() { $symbol(); }" $false
    }
    Test-InputCase 'Dart FFI SendInput' 'StarBridge.Flutter/lib/fixture.dart' "final f = dll.lookupFunction<Native, Dart>('SendInput');" $false
    Test-InputCase 'Dart FFI keybd_event' 'StarBridge.Flutter/packages/example/lib/fixture.dart' "final f = dll.lookup('keybd_event');" $false
    Test-InputCase 'XAML inline code' 'StarBridge.Desktop/fixture.xaml' '<x:Code>SendInput();</x:Code>' $false
    Test-InputCase 'Product shell script' 'StarBridge.NativeHost/fixture.cmd' 'AutoHotkey.exe replay.ahk' $false
    foreach ($message in @('WM_KEYDOWN','WM_KEYUP','WM_CHAR','WM_SYSKEYDOWN','WM_SYSKEYUP',
        'WM_LBUTTONDOWN','WM_LBUTTONUP','WM_RBUTTONDOWN','WM_MOUSEMOVE','WM_MOUSEWHEEL')) {
        Test-InputCase "PostMessage $message" 'StarBridge.NativeHost/fixture.cs' "PostMessage(other, $message, 0, 0);" $false
    }
    Test-InputCase 'SendMessage multiline input' 'StarBridge.Flutter/windows/runner/fixture.cpp' "SendMessageW(other,`n WM_KEYDOWN, 0, 0);" $false
    Test-InputCase 'Numeric input message' 'StarBridge.Desktop/fixture.cs' 'PostMessage(other, 0x0100, 0, 0);' $false
    Test-InputCase 'Dart FFI message lookup' 'StarBridge.Flutter/lib/fixture.dart' "final f = dll.lookup('PostMessageW');" $false
    Test-InputCase 'API function pointer' 'StarBridge.Flutter/windows/runner/fixture.cpp' 'auto send = &SendMessageW;' $false
    foreach ($text in @('AutoHotkey','AutoIt','pyautogui','interception_send(context, stroke)',
        'interception.sys','import interception','class KeyboardMacro {}','void ReplayInput() {}',
        'void RecordKeys() {}','class InputRecorder {}')) {
        Test-InputCase "Macro: $text" 'StarBridge.HostRuntime/fixture.cs' $text $false
    }
    Test-InputCase 'Interception package' 'StarBridge.Flutter/packages/example/pubspec.yaml' "dependencies:`n  interception: any" $false
    Test-InputCase 'Interception NuGet' 'StarBridge.NativeBridge/fixture.csproj' '<PackageReference Include="interception" />' $false
    Test-InputCase 'AHK script' 'StarBridge.Desktop/fixture.ahk' 'F1::return' $false
    Test-InputCase 'Hotkey registration outside reviewed files' 'StarBridge.Core/fixture.cs' 'RegisterHotKey(window, id, modifiers, key);' $false
    Test-InputCase 'Hotkey registration through Dart FFI' 'StarBridge.Flutter/lib/fixture.dart' "final f = dll.lookup('RegisterHotKey');" $false
    Test-InputCase 'Hotkey registration in native runner' 'StarBridge.Flutter/windows/runner/fixture.cpp' 'RegisterHotKey(window, id, modifiers, key);' $false
    Test-InputCase 'Hotkey registration in reviewed file' 'StarBridge.Desktop/NativeInformationOverlayRuntime.cs' 'RegisterHotKey(window, id, modifiers, key);' $true
    foreach ($symbol in @('AttachThreadInput','BlockInput','ClipCursor','RIDEV_NOLEGACY','RidevNoHotKeys','ReadProcessMemory','EnumProcessModules',
        'VirtualAllocEx','NtLoadDriver','CreateServiceW','MinHook','DuplicateOutput','IDXGIOutputDuplication')) {
        Test-InputCase "Blocked: $symbol" 'StarBridge.HostRuntime/fixture.cs' "void Run() { $symbol(); }" $false
    }
    Test-InputCase 'Raw input listener only' 'StarBridge.Core/fixture.cs' 'RegisterRawInputDevices(devices, 1, size);' $true
    foreach ($hook in @('SetWindowsHookEx(13, callback, module, 0);', 'SetWindowsHookExW(idHook, callback, module, 0);',
        'SetWindowsHookExA(idHook, callback, module, 0);', 'WH_KEYBOARD_LL', 'WH_KEYBOARD', 'WH_MOUSE_LL',
        'LowLevelKeyboardProc callback;', 'CallNextHookEx(hook, code, message, data);', 'UnhookWindowsHookEx(hook);')) {
        Test-InputCase "Hook: $hook" 'StarBridge.Core/fixture.cs' $hook $false
    }
    Test-InputCase 'Hook in a sibling of the listener file' 'StarBridge.Desktop/GameCompatibleHotkeyListener.Safe.cs' 'SetWindowsHookEx(13, _hookProcedure, GetModuleHandle(null), 0);' $false
    Test-InputCase 'Queue attachment in native runner' 'StarBridge.Flutter/windows/runner/fixture.cpp' 'AttachThreadInput(current, target, TRUE);' $false
    $menuWindow = 'StarBridge.Flutter/windows/runner/menu_overlay_window.cpp'
    $attachLine = '      attached_(target && current != target && AttachThreadInput(current, target, TRUE)) {}'
    $releaseLine = '  ~ScopedMenuThreadInput() { if (attached_) AttachThreadInput(current_, target_, FALSE); }'
    $helperUse = '  ScopedMenuThreadInput input(GetCurrentThreadId(), foreground_thread);'
    Test-InputCase 'Reviewed queue attachment in the menu window' $menuWindow "$attachLine`n$releaseLine`n$helperUse`n" $true
    Test-InputCase 'Queue attachment copied within the menu window' $menuWindow "$attachLine`n$attachLine`n$releaseLine`n$helperUse`n" $false
    Test-InputCase 'Queue attachment without its release' $menuWindow "$attachLine`n$helperUse`n" $false
    Test-InputCase 'Queue attachment helper used twice' $menuWindow "$attachLine`n$releaseLine`n$helperUse`n  ScopedMenuThreadInput again(a, b);`n" $false
    Test-InputCase 'Queue attachment helper braced a second time' $menuWindow "$attachLine`n$releaseLine`n$helperUse`n  ScopedMenuThreadInput extra{a, b};`n" $false
    Test-InputCase 'Queue attachment helper never used' $menuWindow "$attachLine`n$releaseLine`n" $false
    Test-InputCase 'Reviewed text hidden in a string' $menuWindow "char name[] = `"AttachThreadInput(current, target, TRUE)`";`n" $false
    Test-InputCase 'Function lookup beside the attachment' $menuWindow "$attachLine`n$releaseLine`n$helperUse`nauto f = GetProcAddress(module, name);`n" $false
    Test-InputCase 'Split lookup name' 'StarBridge.Flutter/windows/runner/fixture.cpp' 'GetProcAddress(user32, "AttachThread" "Input");' $false
    Test-InputCase 'Other queue attachment in the menu window' $menuWindow "$attachLine`n$releaseLine`n$helperUse`nAttachThreadInput(a, b, TRUE);`n" $false
    Test-InputCase 'Queue attachment by lookup in the menu window' $menuWindow 'GetProcAddress(user32, "AttachThreadInput");' $false
    Test-InputCase 'Reviewed call in the menu bridge' 'StarBridge.Flutter/windows/runner/menu_overlay_bridge.cpp' 'AttachThreadInput(current, target, TRUE);' $false
    Test-InputCase 'Reviewed call in the old client' 'StarBridge.Desktop/InGameToolWindowBehavior.cs' 'AttachThreadInput(current, target, true);' $false
    Test-InputCase 'Reviewed call in the Host' 'StarBridge.HostRuntime/fixture.cs' 'AttachThreadInput(current, target, TRUE);' $false
    $noticeLine = "const _menuFocusCall = 'AttachThreadInput';"
    Test-InputCase 'Notice constant in the help strings' 'StarBridge.Flutter/lib/app/localization/help_support_strings.dart' "$noticeLine`n" $true
    Test-InputCase 'Notice constant in another Dart file' 'StarBridge.Flutter/lib/app/localization/fixture.dart' "$noticeLine`n" $false
    Test-InputCase 'Lookup beside the notice constant' 'StarBridge.Flutter/lib/app/localization/help_support_strings.dart' "$noticeLine`nfinal f = dll.lookup('AttachThreadInput');`n" $false
    Test-InputCase 'Fixture define outside its test' 'StarBridge.Flutter/windows/runner/tests/fixture.cpp' '#define AttachThreadInput ProbeAttachThreadInput' $false
    Test-InputCase 'Fixture define in its test' 'StarBridge.Flutter/windows/runner/tests/menu_overlay_focus_regression_test.cpp' '#define AttachThreadInput ProbeAttachThreadInput' $true
    Test-InputCase 'Capture in the screenshot tool' 'StarBridge.Flutter/windows/runner/menu_local_tools.cpp' 'BitBlt(memory, 0, 0, w, h, screen, 0, 0, SRCCOPY);' $true
    foreach ($capture in @('BitBlt(a, 0, 0, w, h, b, 0, 0, SRCCOPY);', 'StretchBlt(a);', 'PrintWindow(game, dc, 0);', 'GetWindowDC(game);')) {
        Test-InputCase "Capture elsewhere: $capture" 'StarBridge.Flutter/windows/runner/fixture.cpp' $capture $false
    }
    Test-InputCase 'Capture in Host' 'StarBridge.HostRuntime/fixture.cs' 'graphics.CopyFromScreen(0, 0, 0, 0, size);' $false
    Test-InputCase 'Process handle in the reviewed file' 'StarBridge.HostRuntime/Presence/GameProcessSnapshot.cs' 'OpenProcess(0x1000, false, pid);' $true
    Test-InputCase 'Process handle in native runner' 'StarBridge.Flutter/windows/runner/fixture.cpp' 'OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);' $false
    Test-InputCase 'Process handle in overlay runtime' 'StarBridge.OverlayRuntime.Windows/fixture.cs' 'OpenProcess(0x1000, false, pid);' $false
    Test-InputCase 'Start read in the old client' 'StarBridge.Desktop/MainWindow.RuntimePresence.cs' 'StarCitizenProcessProbe.TryGetStart(out var started);' $true
    Test-InputCase 'Start read on a release path' 'StarBridge.Desktop/NativeInformationOverlayRuntime.cs' 'StarCitizenProcessProbe.TryGetStart(out var started);' $false
    Test-InputCase 'Capture in a native test folder' 'StarBridge.Flutter/windows/runner/tests/fixture.cpp' 'BitBlt(a, 0, 0, w, h, b, 0, 0, SRCCOPY);' $true
    Test-InputCase 'Hook in a native test folder' 'StarBridge.Flutter/windows/runner/tests/fixture.cpp' 'SetWindowsHookExW(WH_KEYBOARD_LL, proc, module, 0);' $false
    Test-InputCase 'Hook in a commercial appearance' 'StarBridge.CommercialAppearances/fixture.cs' 'SetWindowsHookEx(13, callback, module, 0);' $false
    foreach ($alias in @('auto r = RegisterHotKey; r(window, id, modifiers, key);', '(RegisterHotKey)(window, id, modifiers, key);',
        'auto r = (RegisterHotKey);', 'auto r = ::RegisterHotKey;', 'auto r{RegisterHotKey};', 'auto r = &::RegisterHotKey;')) {
        Test-InputCase "Hotkey registration alias: $alias" 'StarBridge.Flutter/windows/runner/fixture.cpp' $alias $false
    }
    Test-InputCase 'Wire field in another case' 'StarBridge.HostRuntime/fixture.cs' 'var x = new { registerHotKey = true };' $true
    Test-InputCase 'Settings copy naming the option' 'StarBridge.Flutter/lib/app/localization/overlay_workspace_en_strings.dart' "final label = 'Use system hotkey (RegisterHotKey) for all shortcuts';" $true
    Test-InputCase 'Lookup in the settings copy file' 'StarBridge.Flutter/lib/app/localization/overlay_workspace_en_strings.dart' "final f = dll.lookup('RegisterHotKey');" $false
    Test-InputCase 'Dart call with a comment' 'StarBridge.Flutter/lib/fixture.dart' 'win32.RegisterHotKey /* native */ (hwnd, id, modifiers, key);' $false
    Test-InputCase 'Dart call in parentheses' 'StarBridge.Flutter/lib/fixture.dart' '(win32.RegisterHotKey)(hwnd, id, modifiers, key);' $false
    Test-InputCase 'Managed method group' 'StarBridge.HostRuntime/fixture.cs' 'Func<nint, int, uint, uint, bool> r = Native.RegisterHotKey;' $false
    Test-InputCase 'Managed import with a comment before the parenthesis' 'StarBridge.HostRuntime/fixture.cs' 'static extern bool RegisterHotKey /* native */ (nint w, int i, uint m, uint k);' $false
    Test-InputCase 'Managed hotkey import by entry point' 'StarBridge.HostRuntime/fixture.cs' '[DllImport("user32.dll", EntryPoint = "RegisterHotKey")] static extern bool Register(nint w, int i, uint m, uint k);' $false
    foreach ($symbol in @('CreateServiceA','OpenSCManagerA','Module32FirstA')) {
        Test-InputCase "Blocked: $symbol" 'StarBridge.HostRuntime/fixture.cs' "void Run() { $symbol(); }" $false
    }
    Test-InputCase 'Capture in a product test-named folder' 'StarBridge.HostRuntime/tests/fixture.cs' 'BitBlt(a, 0, 0, w, h, b, 0, 0, SRCCOPY);' $false
    Test-InputCase 'Hook in shared source' 'shared/fixture.cs' 'SetWindowsHookEx(13, callback, module, 0);' $false
    foreach ($symbol in @('NtOpenProcess','ZwOpenProcess','NtWriteVirtualMemory','ZwWriteVirtualMemory','ZwReadVirtualMemory')) {
        Test-InputCase "Native process API: $symbol" 'StarBridge.HostRuntime/fixture.cs' "void Run() { $symbol(); }" $false
    }
    Test-InputCase 'Hook in native runner' 'StarBridge.Flutter/windows/runner/fixture.cpp' 'SetWindowsHookExW(WH_KEYBOARD_LL, proc, module, 0);' $false
    Test-InputCase 'Hook through Dart FFI' 'StarBridge.Flutter/lib/fixture.dart' "final f = dll.lookup('SetWindowsHookExW');" $false
    Test-InputCase 'Hook in overlay runtime' 'StarBridge.OverlayRuntime.Windows/fixture.cs' 'SetWindowsHookEx(13, callback, module, 0);' $false
    Test-InputCase 'Hook in update helper' 'StarBridge.UpdateHelper/fixture.cs' 'SetWindowsHookEx(13, callback, module, 0);' $false
    Test-InputCase 'Input message listener only' 'StarBridge.Core/fixture.cs' 'if (message == WM_KEYDOWN) Observe();' $true
    Test-InputCase 'Ship classification' 'StarBridge.Desktop/fixture.cs' 'var role = "interception";' $true
    Test-InputCase 'Docs excluded' 'docs/fixture.cs' 'SendInput();' $true
    Test-InputCase 'Build output excluded' 'StarBridge.Desktop/obj/fixture.cs' 'SendInput();' $true
    Test-InputCase 'Exploration excluded' 'StarBridge.Flutter/windows/design/fixture.cpp' 'SendInput();' $true
    $approved = 'SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0)'
    $approvedFile = 'StarBridge.Flutter/windows/runner/flutter_window.cpp'
    Test-InputCase 'Reviewed own-window drag' $approvedFile "$approved;" $true
    Test-InputCase 'Changed window target' $approvedFile ($approved.Replace('GetHandle()', 'other')) $false
    Test-InputCase 'Changed message in reviewed file' $approvedFile ($approved.Replace('WM_NCLBUTTONDOWN', 'WM_KEYDOWN')) $false
    Test-InputCase 'Reviewed call copied to another file' 'StarBridge.Flutter/windows/runner/fixture.cpp' $approved $false
    Test-InputCase 'Extra occurrence of reviewed call' $approvedFile "$approved; $approved;" $false
    Test-InputCase 'Forbidden API in reviewed file' $approvedFile "$approved; SendInput();" $false
    # Exported renderer aliases carry the same exact review, without broadening it.
    $exportedRuntime = 'StarBridge.OverlayRuntime.Windows/Rendering/NativeInformationOverlayRuntime.cs'
    Test-InputCase 'Exported reviewed hotkey registration' $exportedRuntime 'RegisterHotKey(window, id, modifiers, key);' $true
    Test-InputCase 'Exported safe-hotkey companion' 'StarBridge.OverlayRuntime.Windows/Rendering/NativeInformationOverlayRuntime.SafeHotkeys.cs' 'UnregisterHotKey(window, id);' $true
    Test-InputCase 'Exported unreviewed input message' $exportedRuntime 'PostMessage(other, 0x0100, 0, 0);' $false
    Test-InputCase 'Exported forbidden injection' $exportedRuntime 'RegisterHotKey(window, id, modifiers, key); SendInput();' $false
    Test-InputCase 'Exported sibling is not reviewed' 'StarBridge.OverlayRuntime.Windows/Rendering/Other.cs' 'RegisterHotKey(window, id, modifiers, key);' $false
    $exportedListener = 'StarBridge.OverlayRuntime.Windows/Rendering/GameCompatibleHotkeyListener.cs'
    $quit = 'PostThreadMessage(listenerThreadId, WmQuit, UIntPtr.Zero, IntPtr.Zero)'
    Test-InputCase 'Exported reviewed listener shutdown' $exportedListener $quit $true
    Test-InputCase 'Exported changed listener target' $exportedListener ($quit.Replace('listenerThreadId', 'other')) $false
    Test-InputCase 'Exported duplicate listener shutdown' $exportedListener "$quit; $quit;" $false
    Test-InputCase 'Exported reviewed process probe' 'StarBridge.OverlayRuntime.Windows/Rendering/StarCitizenProcessProbe.cs' 'TryGetStart(out var start);' $true
    Test-InputCase 'Exported sibling process probe denied' 'StarBridge.OverlayRuntime.Windows/Rendering/Other.cs' 'TryGetStart(out var start);' $false
    # Exercise the public script entry point too, including its nonzero exit.
    $path = Join-Path $fixture 'StarBridge.Core/entry.cs'
    foreach ($symbol in @('SendInput','keybd_event','SetWindowsHookEx','RegisterHotKey','RegisterRawInputDevices')) {
        [IO.File]::WriteAllText($path, "$symbol();", $utf8)
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test Product Input Safety.ps1') -Root $fixture 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        $expected = $symbol -eq 'RegisterRawInputDevices'
        if (($code -eq 0) -ne $expected) { $failed++; Write-Output "FAIL entry point $symbol ($code)" }
        else { $passed++; Write-Output "PASS entry point $symbol" }
    }
    foreach ($symbol in @('SendInput','keybd_event','SetWindowsHookEx')) {
        [IO.File]::WriteAllText($path, "$symbol();", $utf8)
        $ErrorActionPreference = 'Continue'
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test Repository Safety.ps1') -Root $fixture 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($code -eq 0 -or ($output -join "`n") -notmatch 'Product input safety failed:') {
            $failed++; Write-Output "FAIL repository gate $symbol"
        } else { $passed++; Write-Output "PASS repository gate $symbol" }
    }
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $base = [IO.Path]::GetFullPath($fixtureBase).TrimEnd('\') + '\'
    if (!$resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolved) -notmatch '^cx-input-safety-[a-f0-9]{32}$') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Output "Input safety regression: $passed passed, $failed failed."
if ($failed -gt 0) { throw 'Input safety regression failed.' }
