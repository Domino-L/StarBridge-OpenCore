param(
    [string]$Root = '',
    [switch]$Audit,
    [switch]$LibraryOnly
)

$ErrorActionPreference = 'Stop'

function Get-InputSafetyFiles([string]$Directory) {
    # Do not descend into outputs, exploration, links, or configuration stores.
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.PSIsContainer -and $item.Name -match '^(?i:bin|obj|build|dist|out|target|node_modules|\.dart_tool|\.git|\.vs|ephemeral|\.plugin_symlinks|docs|prototypes|design|_cxbuild|\.artifacts|\.codex-build|\.altobj|\.altbin|CMakeFiles)$') { continue }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Input safety cannot inspect a linked product path: $($item.FullName)"
        }
        if ($item.PSIsContainer) {
            Get-InputSafetyFiles $item.FullName
        } else {
            if ($item.Name -match '(?i)secret|credential|^\.env|^application-.*\.ya?ml$|^relay\.env$') { continue }
            if ($item.Extension -match '^(?i:\.cs|\.xaml|\.razor|\.cshtml|\.dart|\.cpp|\.cc|\.cxx|\.c|\.h|\.hpp|\.hxx|\.inl|\.vb|\.fs|\.rs|\.java|\.kt|\.swift|\.m|\.mm|\.py|\.lua|\.js|\.mjs|\.cjs|\.ts|\.ps1|\.psm1|\.cmd|\.bat|\.vbs|\.sh|\.ahk|\.au3|\.csproj|\.props|\.targets|\.cmake)$' -or
                $item.Name -match '^(?i:pubspec\.(yaml|lock)|package(-lock)?\.json|requirements.*\.txt|CMakeLists\.txt|Cargo\.(toml|lock)|packages\.config)$') {
                $item
            }
        }
    }
}

function Get-WindowMessageReferences([string]$Text) {
    # Inspect every occurrence, including nested calls, declarations and FFI
    # lookup strings. Unreviewed numeric/aliased messages fail closed too.
    $pattern = '\b(?:PostMessage|SendMessage|PostThreadMessage|SendMessageTimeout|SendNotifyMessage|SendMessageCallback)(?:A|W)?\b'
    foreach ($match in [regex]::Matches($Text, $pattern)) {
        $start = $match.Index
        $end = $match.Index + $match.Length
        while ($end -lt $Text.Length -and [char]::IsWhiteSpace($Text[$end])) { $end++ }
        if ($end -lt $Text.Length -and $Text[$end] -eq '(') {
            $depth = 0
            do {
                if ($Text[$end] -eq '(') { $depth++ }
                if ($Text[$end] -eq ')') { $depth-- }
                $end++
            } while ($end -lt $Text.Length -and $depth -gt 0)
            if ($depth -ne 0) { throw "Unbalanced window-message reference: $($match.Value)" }
        } else {
            # Bind bare symbols/FFI lookups/chat enums to their full source
            # line, so an allowed import string cannot become an arbitrary alias.
            $start = $Text.LastIndexOf("`n", $match.Index) + 1
            $end = $Text.IndexOf("`n", $match.Index)
            if ($end -lt 0) { $end = $Text.Length }
        }
        [pscustomobject]@{
            Symbol = $match.Value
            Reference = [regex]::Replace($Text.Substring($start, $end - $start).Trim(), '\s+', ' ')
            Line = 1 + [regex]::Matches($Text.Substring(0, $match.Index), "`n").Count
        }
    }
}

function Invoke-ProductInputSafety([string]$ScanRoot, [switch]$ShowAudit) {
    $ScanRoot = [IO.Path]::GetFullPath($ScanRoot).TrimEnd('\', '/')
    if (!(Test-Path -LiteralPath $ScanRoot -PathType Container)) { throw 'Input safety root does not exist.' }
    $roots = @('StarBridge.Core', 'StarBridge.Desktop', 'StarBridge.Server',
        'StarBridge.HostRuntime', 'StarBridge.NativeHost', 'StarBridge.NativeBridge',
        'StarBridge.OverlayRuntime.Windows', 'StarBridge.UpdateHelper', 'StarBridge.CommercialAppearances', 'shared',
        'StarBridge.Flutter/lib', 'StarBridge.Flutter/windows', 'StarBridge.Flutter/packages')
    $policy = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'Product Input Safety Allowlist.psd1')
    $remaining = @{}
    foreach ($entry in $policy.Entries) {
        if (!$entry.File -or !$entry.Symbol -or !$entry.Reason -or !$entry.Reference -or $entry.Count -lt 1) { throw 'Invalid input safety allowance.' }
        $key = $entry.File + '|' + $entry.Symbol + '|' + $entry.Reference
        if ($remaining.ContainsKey($key)) { throw 'Duplicate input safety allowance.' }
        $remaining[$key] = [int]$entry.Count
    }
    $rules = [ordered]@{
        'simulated input / injection' = '(?i)\b(?:SendInput|keybd_event|mouse_event|SendKeys|InputSimulator|NtUserSendInput|INPUT_KEYBOARD|INPUT_MOUSE|SetCursorPos|CreateRemoteThread|WriteProcessMemory|LLKHF_INJECTED)\b'
        'low-level input hook' = '(?i)\b(?:SetWindowsHookEx(?:A|W)?|UnhookWindowsHookEx|CallNextHookEx|WH_KEYBOARD(?:_LL)?|WH_MOUSE_LL|LowLevelKeyboard\w*|LowLevelMouse\w*)\b'
        'input blocking or queue attachment' = '(?i)\b(?:AttachThreadInput|AttachThread|BlockInput|ClipCursor|RIDEV_NOLEGACY|RIDEV_NOHOTKEYS|RIDEV_CAPTUREMOUSE|RidevNoLegacy|RidevNoHotKeys|RidevCaptureMouse)\b'
        'process or driver access' = '(?i)\b(?:ReadProcessMemory|NtReadVirtualMemory|ZwReadVirtualMemory|NtWriteVirtualMemory|ZwWriteVirtualMemory|NtOpenProcess|ZwOpenProcess|VirtualAllocEx|VirtualProtectEx|SetThreadContext|QueueUserAPC|NtCreateThreadEx|DebugActiveProcess|EnumProcessModules(?:Ex)?|K32EnumProcessModules(?:Ex)?|Module32(?:First|Next)[AW]?|MiniDumpWriteDump|NtLoadDriver|OpenSCManager[AW]?|CreateService[AW]?|MinHook|DetourAttach|IDXGIOutputDuplication|DuplicateOutput\d*)\b'
        'macro dependency' = '(?i)\b(?:AutoHotkey\w*|AutoIt\w*|pyautogui|InterceptionDriver|InputInterceptor)\b|\binterception(?:[_./-](?:\w+))|\b(?:import|from|using)\s+interception\b'
        'input recording / playback' = '(?i)\b(?:record(?:ed|ing)?|replay|playback|macro)[_ -]*(?:inputs?|keyboard|mouse|keystrokes?|keys)\b|\b(?:inputs?|keyboard|mouse|keystrokes?|keys)[_ -]*(?:record(?:er|ing)?|replay|playback|macro)\b|\brecord\s+(?:and\s+)?replay\s+(?:inputs?|keys|mouse)\b|\b(?:class|struct)\s+\w*Macro\w*\b|\b(?:run|execute|play|record)[_ -]*macro\b'
    }
    $findings = [Collections.Generic.List[string]]::new()
    $fileCount = 0
    $reviewedCount = 0
    foreach ($relativeRoot in $roots) {
        $directory = Join-Path $ScanRoot $relativeRoot
        if (!(Test-Path -LiteralPath $directory -PathType Container)) { continue }
        if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked product root: $relativeRoot" }
        foreach ($file in Get-InputSafetyFiles $directory) {
            $fileCount++
            $relative = $file.FullName.Substring($ScanRoot.Length + 1).Replace('\', '/')
            $reviewPath = $relative
            if ($policy.ExportedFiles.ContainsKey($relative)) { $reviewPath = $policy.ExportedFiles[$relative] }
            $text = [IO.File]::ReadAllText($file.FullName)
            if (($file.Extension -in @('.csproj', '.props', '.targets', '.cmake') -or
                $file.Name -match '^(?i:pubspec\.(yaml|lock)|package(-lock)?\.json|requirements.*\.txt|CMakeLists\.txt|Cargo\.(toml|lock)|packages\.config)$') -and
                $text -match '(?i)\binterception\b') { $findings.Add("$relative [interception driver dependency]") }
            # Blank out the reviewed whole lines; anything else that names the call still hits the rule.
            $ruleText = $text
            foreach ($reference in @($policy.QueueAttachmentReferences[$reviewPath])) {
                if (!$reference -or $text -notmatch '\bAttachThreadInput\b') { continue }
                $pattern = '(?m)^' + [regex]::Escape($reference) + '(?=\r?$)'
                if ([regex]::Matches($text, $pattern).Count -ne 1) { $findings.Add("$relative [reviewed queue attachment changed: $reference]") }
                $ruleText = [regex]::Replace($ruleText, $pattern, ' ' * $reference.Length)
            }
            if ($reviewPath -eq $policy.QueueAttachmentHelperFile -and $text -match '\bAttachThreadInput\b') {
                # The helper is built in one place only and the file resolves no function by name.
                if ([regex]::Matches($text, '(?<!~)(?<!class )\bScopedMenuThreadInput\b(?!\(DWORD)').Count -ne 1) { $findings.Add("$relative [queue attachment helper not used exactly once]") }
                if ($text -match '\b(?:GetProcAddress|LoadLibrary\w*)\b') { $findings.Add("$relative [function lookup beside the queue attachment]") }
            }
            foreach ($rule in $rules.GetEnumerator()) {
                foreach ($hit in [regex]::Matches($ruleText, $rule.Value)) {
                    $line = 1 + [regex]::Matches($ruleText.Substring(0, $hit.Index), "`n").Count
                    $findings.Add("${relative}:${line} [$($rule.Key): $($hit.Value)]")
                }
            }
            if ($file.Extension -in @('.ahk', '.au3')) { $findings.Add("$relative [macro script]") }
            # Fixtures in native test folders may touch these to set up a scene; they do not ship.
            $isTest = $relative -like 'StarBridge.Flutter/windows/runner/tests/*'
            if (!$isTest -and $reviewPath -ne $policy.OpenProcessFile) {
                foreach ($hit in [regex]::Matches($text, '\bOpenProcess\b')) {
                    $line = 1 + [regex]::Matches($text.Substring(0, $hit.Index), "`n").Count
                    $findings.Add("${relative}:${line} [process handle outside the reviewed file: $($hit.Value)]")
                }
            }
            if (!$isTest -and $reviewPath -notin $policy.TryGetStartFiles) {
                foreach ($hit in [regex]::Matches($text, '\bTryGetStart\b')) {
                    $line = 1 + [regex]::Matches($text.Substring(0, $hit.Index), "`n").Count
                    $findings.Add("${relative}:${line} [game start read through a handle outside the old client: $($hit.Value)]")
                }
            }
            if (!$isTest -and $reviewPath -notin $policy.ScreenCaptureFiles) {
                foreach ($hit in [regex]::Matches($text, '\b(?:BitBlt|StretchBlt|PrintWindow|CopyFromScreen|GetWindowDC)\b')) {
                    $line = 1 + [regex]::Matches($text.Substring(0, $hit.Index), "`n").Count
                    $findings.Add("${relative}:${line} [screen capture outside the reviewed files: $($hit.Value)]")
                }
            }
            if (!$isTest -and $reviewPath -notin $policy.RegisterHotKeyFiles) {
                # The settings copy names the option; anywhere else any reference counts.
                $hotkeyPattern = if ($reviewPath -notin $policy.RegisterHotKeyCopyFiles) { '\b(?:Un)?RegisterHotKey(?:A|W)?\b' }
                    else { '\b(?:Un)?RegisterHotKey(?:A|W)?\s*\(|[''"](?:Un)?RegisterHotKey(?:A|W)?\b' }
                foreach ($hit in [regex]::Matches($text, $hotkeyPattern)) {
                    $line = 1 + [regex]::Matches($text.Substring(0, $hit.Index), "`n").Count
                    $findings.Add("${relative}:${line} [hotkey registration outside the reviewed files: $($hit.Value)]")
                }
            }
            foreach ($reference in Get-WindowMessageReferences $text) {
                $key = $reviewPath + '|' + $reference.Symbol + '|' + $reference.Reference
                if ($remaining.ContainsKey($key) -and $remaining[$key] -gt 0) {
                    $remaining[$key]--
                    $reviewedCount++
                    if ($ShowAudit) { Write-Host "${relative}:$($reference.Line) [reviewed: $($reference.Reference)]" }
                } else {
                    $findings.Add("${relative}:$($reference.Line) [unreviewed window-message reference: $($reference.Symbol)]")
                }
            }
            if ($ShowAudit) {
                foreach ($hit in [regex]::Matches($text, '\b(?:RegisterHotKey|RegisterRawInputDevices)\b')) {
                    $line = 1 + [regex]::Matches($text.Substring(0, $hit.Index), "`n").Count
                    Write-Host "${relative}:${line} [listener: $($hit.Value)]"
                }
            }
        }
    }
    if ($findings.Count -gt 0) {
        $findings | Sort-Object -Unique | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        throw "Product input safety failed: $($findings.Count) finding(s)."
    }
    Write-Host "Product input safety passed: $fileCount files, $reviewedCount reviewed window-message references." -ForegroundColor Green
}

if (!$LibraryOnly) {
    if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
    Invoke-ProductInputSafety $Root -ShowAudit:$Audit
}
