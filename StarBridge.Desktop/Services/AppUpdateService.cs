using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using WpfApplication = System.Windows.Application;

namespace StarBridge.Desktop;

internal sealed class AppUpdateService
{
    private readonly HttpClient _httpClient;
    private readonly Func<string, Uri> _buildUri;
    private readonly Window _owner;
    private readonly Action<string> _setStatus;
    private readonly Action<bool> _setCheckButtonEnabled;
    private readonly IAppUpdateUi? _updateUi;

    public AppUpdateService(
        HttpClient httpClient,
        Func<string, Uri> buildUri,
        Window owner,
        Action<string> setStatus,
        Action<bool> setCheckButtonEnabled,
        IAppUpdateUi? updateUi = null)
    {
        _httpClient = httpClient;
        _buildUri = buildUri;
        _owner = owner;
        _setStatus = setStatus;
        _setCheckButtonEnabled = setCheckButtonEnabled;
        _updateUi = updateUi;
    }

    public async Task CheckForInstallerUpdateAsync(bool silent, string currentVersion)
    {
        if (!AppUpdateExecutionPolicy.IsCurrentBuildAllowed)
        {
            if (!silent)
            {
                _setStatus(AppUpdateExecutionPolicy.DeveloperBuildMessage);
            }

            return;
        }

        try
        {
            ReportLastPortableUpdateResult(silent);
            if (await CloseIfPortableUpdateIsInProgressAsync())
            {
                return;
            }

            if (!silent)
            {
                _setStatus($"正在检查更新... 当前版本 V{currentVersion}");
            }

            var manifest = await _httpClient.GetFromJsonAsync<UpdateManifest>(_buildUri("api/updates/latest"));
            if (manifest is null || string.IsNullOrWhiteSpace(manifest.Version))
            {
                if (!silent)
                {
                    _setStatus($"服务器没有返回更新信息。当前版本 V{currentVersion}");
                }

                return;
            }

            UpdateManifestSecurity.ValidateAndVerify(manifest);

            if (!IsNewerVersion(manifest.Version, currentVersion))
            {
                if (!silent)
                {
                    _setStatus($"当前已是最新版本 V{currentVersion}。");
                }

                return;
            }

            var notes = string.IsNullOrWhiteSpace(manifest.Notes) ? "无版本说明。" : manifest.Notes.Trim();
            _setStatus($"发现新版本 V{manifest.Version}。{notes}");
            if (string.IsNullOrWhiteSpace(manifest.PackageUrl) && string.IsNullOrWhiteSpace(manifest.DownloadUrl))
            {
                _setStatus($"发现新版本 V{manifest.Version}，但服务器尚未配置下载地址。");
                return;
            }

            var updateMode = string.IsNullOrWhiteSpace(manifest.PackageUrl)
                ? "完整安装包更新"
                : "应用内覆盖更新";
            var shouldUpdate = _updateUi is not null
                ? await _updateUi.ConfirmUpdateAsync(manifest, currentVersion, updateMode)
                : StarBridgeMessageBox.Show(
                    _owner,
                    $"发现新版本 V{manifest.Version}。\n\n{notes}\n\n更新方式：{updateMode}\n更新期间应用会暂时锁定，完成后可能会自动关闭并重启。\n是否现在更新？",
                    "星海舰桥更新",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Information) == MessageBoxResult.Yes;

            if (!shouldUpdate)
            {
                _setStatus($"已暂缓更新。当前版本 V{currentVersion}。");
                return;
            }

            if (!string.IsNullOrWhiteSpace(manifest.PackageUrl))
            {
                await DownloadAndApplyPackageUpdateAsync(manifest);
            }
            else
            {
                await DownloadAndRunInstallerUpdateAsync(manifest);
            }
        }
        catch (Exception ex)
        {
            if (!silent)
            {
                var message = UserFacingError.Describe(ex, "暂时无法检查更新，应用稍后会自动重试。");
                _setStatus(message);
                _updateUi?.ReportFailed(message);
            }
        }
    }

    private async Task DownloadAndApplyPackageUpdateAsync(UpdateManifest manifest)
    {
        if (!Uri.TryCreate(manifest.PackageUrl, UriKind.Absolute, out var packageUri))
        {
            const string message = "更新失败：服务器返回的覆盖更新包地址无效。";
            _setStatus(message);
            _updateUi?.ReportFailed(message);
            return;
        }

        _setCheckButtonEnabled(false);
        _updateUi?.ReportProgress("正在准备应用内覆盖更新...", 0);
        try
        {
            var updateRoot = GetUpdateRoot();
            Directory.CreateDirectory(updateRoot);
            var logPath = GetPortableUpdateLogPath(updateRoot);
            var resultPath = GetPortableUpdateResultPath(updateRoot);
            var inProgressPath = GetPortableUpdateInProgressPath(updateRoot);
            TryDeleteFile(logPath);
            TryDeleteFile(resultPath);
            TryDeleteFile(inProgressPath);

            var safeVersion = string.Join("_", manifest.Version.Split(Path.GetInvalidFileNameChars(), StringSplitOptions.RemoveEmptyEntries));
            var packagePath = Path.Combine(updateRoot, $"StarBridge-{safeVersion}-win-x64-update.zip");
            await DownloadUpdateFileAsync(packageUri, packagePath, manifest.Version, manifest.PackageSha256);

            _setStatus("下载完成，正在预解压并校验更新文件...");
            _updateUi?.ReportProgress("正在预解压并校验更新文件...", null);
            var stagingDirectory = Path.Combine(updateRoot, $"staged-{safeVersion}");
            var stagingTimer = Stopwatch.StartNew();
            var sourceDirectory = await PortableUpdateStager.PrepareAsync(packagePath, stagingDirectory);
            stagingTimer.Stop();
            AppendPortableUpdateLog(logPath, $"Package staged and validated in {stagingTimer.ElapsedMilliseconds} ms.");

            const string status = "更新文件已准备完成，重启后将直接替换并启动新版本。";
            _setStatus(status);
            _updateUi?.ReportCompleted(status);
            var appDir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            var exePath = Environment.ProcessPath ?? Path.Combine(appDir, "Star Bridge.exe");
            var readyMarkerPath = Path.Combine(updateRoot, "updated-app-ready.marker");
            var scriptPath = CreatePortableUpdateScript(
                updateRoot,
                packagePath,
                sourceDirectory,
                stagingDirectory,
                appDir,
                exePath,
                resultPath,
                logPath,
                inProgressPath,
                readyMarkerPath);

            if (!await ConfirmRestartBeforeShutdownAsync())
            {
                _setStatus("更新已下载，已暂缓重启。稍后可重新检查更新继续安装。");
                _setCheckButtonEnabled(true);
                return;
            }

            WritePortableUpdateInProgress(inProgressPath);
            Process.Start(new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" -TargetProcessId {Environment.ProcessId}"
            });

            ShutdownApplication(forUpdateRestart: true);
        }
        catch (Exception ex)
        {
            var message = UserFacingError.Describe(ex, "更新未完成，请稍后重试。");
            _setStatus(message);
            _updateUi?.ReportFailed(message);
            _setCheckButtonEnabled(true);
        }
    }

    private async Task DownloadAndRunInstallerUpdateAsync(UpdateManifest manifest)
    {
        if (!Uri.TryCreate(manifest.DownloadUrl, UriKind.Absolute, out var downloadUri))
        {
            const string message = "更新失败：服务器返回的安装包地址无效。";
            _setStatus(message);
            _updateUi?.ReportFailed(message);
            return;
        }

        _setCheckButtonEnabled(false);
        _updateUi?.ReportProgress("正在准备安装包更新...", 0);
        try
        {
            var updateRoot = GetUpdateRoot();
            Directory.CreateDirectory(updateRoot);

            var safeVersion = string.Join("_", manifest.Version.Split(Path.GetInvalidFileNameChars(), StringSplitOptions.RemoveEmptyEntries));
            var installerPath = Path.Combine(updateRoot, $"StarBridge-{safeVersion}-win-x64-setup.exe");

            await DownloadUpdateFileAsync(downloadUri, installerPath, manifest.Version, manifest.DownloadSha256);

            const string status = "下载完成，正在启动安装器。应用将自动关闭，并由安装器完成更新。";
            _setStatus(status);
            _updateUi?.ReportCompleted(status);
            if (!await ConfirmRestartBeforeShutdownAsync())
            {
                _setStatus("更新已下载，已暂缓重启。稍后可重新检查更新继续安装。");
                _setCheckButtonEnabled(true);
                return;
            }

            Process.Start(new ProcessStartInfo(installerPath)
            {
                UseShellExecute = true,
                Arguments = "/CLOSEAPPLICATIONS /NORESTART /SP-"
            });

            ShutdownApplication(forUpdateRestart: false);
        }
        catch (Exception ex)
        {
            var message = UserFacingError.Describe(ex, "更新未完成，请稍后重试。");
            _setStatus(message);
            _updateUi?.ReportFailed(message);
            _setCheckButtonEnabled(true);
        }
    }

    private async Task DownloadUpdateFileAsync(Uri downloadUri, string destinationPath, string version, string? expectedSha256)
    {
        if (!downloadUri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("更新包下载地址不是安全的 HTTPS 地址，已停止更新。");
        }

        var normalizedSha256 = UpdateManifestSecurity.NormalizeSha256(expectedSha256);
        if (normalizedSha256.Length != 64 || normalizedSha256.Any(character => !Uri.IsHexDigit(character)))
        {
            throw new InvalidOperationException("更新包缺少有效的 SHA-256，已停止更新。");
        }

        try
        {
            await DownloadUpdateFileWithHttpClientAsync(downloadUri, destinationPath, version, normalizedSha256);
        }
        catch (Exception httpException) when (CanUseCurlFallback(downloadUri))
        {
            var builtInError = GetUpdateErrorMessage(httpException);
            _setStatus($"内置下载器连接失败，正在切换备用下载方式... {builtInError}");
            _updateUi?.ReportProgress("内置下载器连接失败，正在切换备用下载方式...", null);
            try
            {
                await DownloadUpdateFileWithCurlAsync(downloadUri, destinationPath, version, normalizedSha256);
            }
            catch (Exception curlException)
            {
                throw new InvalidOperationException(
                    $"内置下载器失败：{builtInError}；备用下载器失败：{GetUpdateErrorMessage(curlException)}",
                    curlException);
            }
        }
    }

    private async Task<bool> ConfirmRestartBeforeShutdownAsync()
    {
        const string restartStatus = "应用将会重启以完成更新。";
        _setStatus(restartStatus);
        if (_updateUi is not null)
        {
            return await _updateUi.ConfirmRestartAsync(restartStatus);
        }

        return StarBridgeMessageBox.Show(
            _owner,
            restartStatus,
            "星海舰桥更新",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Information) == MessageBoxResult.OK;
    }

    private async Task DownloadUpdateFileWithHttpClientAsync(Uri downloadUri, string destinationPath, string version, string? expectedSha256)
    {
        _setStatus($"正在下载 V{version} 更新...");
        _updateUi?.ReportProgress($"正在下载 V{version} 更新...", 0);
        using var updateClient = new HttpClient { Timeout = TimeSpan.FromMinutes(15) };
        using var response = await updateClient.GetAsync(downloadUri, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        var totalBytes = response.Content.Headers.ContentLength;
        await using var source = await response.Content.ReadAsStreamAsync();
        await using var destination = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None);
        using var hasher = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);

        var buffer = new byte[128 * 1024];
        long receivedBytes = 0;
        while (true)
        {
            var read = await source.ReadAsync(buffer);
            if (read <= 0)
            {
                break;
            }

            await destination.WriteAsync(buffer.AsMemory(0, read));
            hasher.AppendData(buffer.AsSpan(0, read));
            receivedBytes += read;
            if (totalBytes is > 0)
            {
                var percent = Math.Clamp(receivedBytes * 100 / totalBytes.Value, 0, 100);
                _setStatus($"正在下载 V{version} 更新... {percent}%");
                _updateUi?.ReportProgress($"正在下载 V{version} 更新...", percent);
            }
            else
            {
                _updateUi?.ReportProgress($"正在下载 V{version} 更新...", null);
            }
        }

        if (!string.IsNullOrWhiteSpace(expectedSha256))
        {
            var actualSha256 = Convert.ToHexString(hasher.GetHashAndReset());
            var expected = UpdateManifestSecurity.NormalizeSha256(expectedSha256);
            if (!actualSha256.Equals(expected, StringComparison.OrdinalIgnoreCase))
            {
                TryDeleteFile(destinationPath);
                throw new InvalidOperationException("更新包校验失败：下载内容与服务器公布的 SHA-256 不一致，请重新检查更新。");
            }
        }
    }

    private async Task DownloadUpdateFileWithCurlAsync(Uri downloadUri, string destinationPath, string version, string? expectedSha256)
    {
        TryDeleteFile(destinationPath);
        var tempPath = destinationPath + ".download";
        TryDeleteFile(tempPath);

        var startInfo = new ProcessStartInfo(FindCurlExecutable())
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true
        };
        startInfo.ArgumentList.Add("-L");
        startInfo.ArgumentList.Add("--fail");
        startInfo.ArgumentList.Add("--show-error");
        startInfo.ArgumentList.Add("--silent");
        startInfo.ArgumentList.Add("--connect-timeout");
        startInfo.ArgumentList.Add("30");
        startInfo.ArgumentList.Add("--retry");
        startInfo.ArgumentList.Add("3");
        startInfo.ArgumentList.Add("--retry-delay");
        startInfo.ArgumentList.Add("2");
        startInfo.ArgumentList.Add("--output");
        startInfo.ArgumentList.Add(tempPath);
        startInfo.ArgumentList.Add(downloadUri.AbsoluteUri);

        _setStatus($"正在使用备用下载器下载 V{version} 更新...");
        _updateUi?.ReportProgress($"正在使用备用下载器下载 V{version} 更新...", null);

        using var process = Process.Start(startInfo) ??
                            throw new InvalidOperationException("无法启动备用下载器。");
        var stderrTask = process.StandardError.ReadToEndAsync();
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();
        var stderr = (await stderrTask).Trim();
        var stdout = (await stdoutTask).Trim();
        if (process.ExitCode != 0)
        {
            TryDeleteFile(tempPath);
            var detail = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(detail)
                ? $"备用下载器退出码：{process.ExitCode}"
                : detail);
        }

        if (!File.Exists(tempPath) || new FileInfo(tempPath).Length == 0)
        {
            TryDeleteFile(tempPath);
            throw new InvalidOperationException("备用下载器没有生成更新文件。");
        }

        if (!string.IsNullOrWhiteSpace(expectedSha256))
        {
            var expected = UpdateManifestSecurity.NormalizeSha256(expectedSha256);
            var actual = ComputeFileSha256(tempPath);
            if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
            {
                TryDeleteFile(tempPath);
                throw new InvalidOperationException("更新包校验失败：下载内容与服务器公布的 SHA-256 不一致，请重新检查更新。");
            }
        }

        if (File.Exists(destinationPath))
        {
            File.Delete(destinationPath);
        }

        File.Move(tempPath, destinationPath);
    }

    private static bool CanUseCurlFallback(Uri downloadUri)
    {
        return downloadUri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
               downloadUri.Scheme.Equals(Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase);
    }

    private static string FindCurlExecutable()
    {
        var systemCurl = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "curl.exe");
        return File.Exists(systemCurl) ? systemCurl : "curl.exe";
    }

    private static string ComputeFileSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static string GetUpdateErrorMessage(Exception exception) =>
        UserFacingError.Describe(exception, "更新未完成，请稍后重试。");

    private static string CreatePortableUpdateScript(
        string updateRoot,
        string packagePath,
        string sourceDirectory,
        string stagingDirectory,
        string appDir,
        string exePath,
        string resultPath,
        string logPath,
        string inProgressPath,
        string readyMarkerPath)
    {
        var scriptPath = Path.Combine(updateRoot, "apply-starbridge-update.ps1");
        var escapedPackage = EscapePowerShellSingleQuoted(packagePath);
        var escapedSource = EscapePowerShellSingleQuoted(sourceDirectory);
        var escapedStaging = EscapePowerShellSingleQuoted(stagingDirectory);
        var escapedAppDir = EscapePowerShellSingleQuoted(appDir);
        var escapedExe = EscapePowerShellSingleQuoted(exePath);
        var escapedResult = EscapePowerShellSingleQuoted(resultPath);
        var escapedLog = EscapePowerShellSingleQuoted(logPath);
        var escapedInProgress = EscapePowerShellSingleQuoted(inProgressPath);
        var escapedReadyMarker = EscapePowerShellSingleQuoted(readyMarkerPath);

        var script = $$"""
param([int]$TargetProcessId)
$ErrorActionPreference = 'Stop'
$packagePath = '{{escapedPackage}}'
$sourceDir = '{{escapedSource}}'
$stagingDir = '{{escapedStaging}}'
$appDir = '{{escapedAppDir}}'
$exePath = '{{escapedExe}}'
$resultPath = '{{escapedResult}}'
$logPath = '{{escapedLog}}'
$inProgressPath = '{{escapedInProgress}}'
$readyMarkerPath = '{{escapedReadyMarker}}'

function Write-UpdateLog([string]$Message) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logPath -Value "[$stamp] $Message" -Encoding UTF8
}

function Set-UpdateResult([string]$State, [string]$Message) {
    Set-Content -LiteralPath $resultPath -Value "$State $Message" -Encoding UTF8
    try {
        if (Test-Path -LiteralPath $inProgressPath) {
            Remove-Item -LiteralPath $inProgressPath -Force
        }
    } catch {}
}

function Invoke-WithRetry([scriptblock]$Action, [string]$Name, [int]$Attempts = 30) {
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            & $Action
            return
        } catch {
            if ($i -eq $Attempts) {
                throw "$Name failed after $Attempts attempts. $($_.Exception.Message)"
            }

            Write-UpdateLog "$Name failed on attempt $i. Retrying..."
            Start-Sleep -Milliseconds 500
        }
    }
}

function Get-StarBridgeProcess {
    Get-Process -Name 'Star Bridge' -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Id -ne $PID -and $_.Path -eq $exePath
        } catch {
            $false
        }
    }
}

function Wait-StarBridgeExit {
    for ($i = 0; $i -lt 120; $i++) {
        $target = Get-Process -Id $TargetProcessId -ErrorAction SilentlyContinue
        $sameApp = @(Get-StarBridgeProcess)
        if (-not $target -and $sameApp.Count -eq 0) {
            return
        }

        Start-Sleep -Milliseconds 250
    }

    throw 'Star Bridge did not exit in time.'
}

function Wait-StarBridgeReady([System.Diagnostics.Process]$Process) {
    for ($i = 0; $i -lt 180; $i++) {
        if (Test-Path -LiteralPath $readyMarkerPath) {
            return $true
        }

        try {
            $Process.Refresh()
            if ($Process.HasExited) {
                return $false
            }
        } catch {
            return $false
        }

        Start-Sleep -Milliseconds 250
    }

    return $false
}

try {
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UpdateLog 'Portable update started.'
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir 'Star Bridge.exe'))) {
        throw 'Prepared update does not contain Star Bridge.exe.'
    }

    if (Test-Path -LiteralPath $readyMarkerPath) {
        Remove-Item -LiteralPath $readyMarkerPath -Force
    }

    Wait-StarBridgeExit
    Write-UpdateLog "Application exited after $($timer.ElapsedMilliseconds) ms."

    Get-ChildItem -LiteralPath $sourceDir -Force | ForEach-Object {
        $itemPath = $_.FullName
        $itemName = $_.Name
        Invoke-WithRetry -Name "copy $itemName" -Action {
            Copy-Item -LiteralPath $itemPath -Destination $appDir -Recurse -Force -ErrorAction Stop
        }
    }

    if (-not (Test-Path -LiteralPath $exePath)) {
        throw 'Updated Star Bridge.exe was not found after copy.'
    }

    Write-UpdateLog "Files replaced after $($timer.ElapsedMilliseconds) ms."
    Set-UpdateResult 'OK' 'Portable update applied.'
    $env:STARBRIDGE_UPDATE_READY_MARKER = $readyMarkerPath
    $updatedProcess = Start-Process -FilePath $exePath -WorkingDirectory $appDir -PassThru
    Write-UpdateLog "Updated process launched after $($timer.ElapsedMilliseconds) ms."

    if (Wait-StarBridgeReady -Process $updatedProcess) {
        Write-UpdateLog "Updated window became ready after $($timer.ElapsedMilliseconds) ms."
        Start-Sleep -Seconds 15
        try {
            Invoke-WithRetry -Name 'remove staged update' -Attempts 6 -Action {
                if (Test-Path -LiteralPath $stagingDir) {
                    Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction Stop
                }
            }
            if (Test-Path -LiteralPath $packagePath) {
                Remove-Item -LiteralPath $packagePath -Force
            }
            if (Test-Path -LiteralPath $readyMarkerPath) {
                Remove-Item -LiteralPath $readyMarkerPath -Force
            }
            Write-UpdateLog 'Deferred update cleanup completed.'
        } catch {
            Write-UpdateLog "Deferred cleanup skipped: $($_.Exception.Message)"
        }
    } else {
        Write-UpdateLog 'Updated process did not report a ready window within 45 seconds; recovery files were retained.'
    }
} catch {
    Write-UpdateLog "FAILED: $($_.Exception.Message)"
    Set-UpdateResult 'FAILED' $_.Exception.Message
    try {
        if (Test-Path -LiteralPath $exePath) {
            Start-Process -FilePath $exePath -WorkingDirectory $appDir
        }
    } catch {}
}
""";

        File.WriteAllText(scriptPath, script, new UTF8Encoding(false));
        return scriptPath;
    }

    private static string EscapePowerShellSingleQuoted(string value)
    {
        return value.Replace("'", "''");
    }

    private void ReportLastPortableUpdateResult(bool silent)
    {
        try
        {
            var updateRoot = GetUpdateRoot();
            var resultPath = GetPortableUpdateResultPath(updateRoot);
            if (!File.Exists(resultPath))
            {
                return;
            }

            var result = File.ReadAllText(resultPath, Encoding.UTF8).Trim();
            if (string.IsNullOrWhiteSpace(result))
            {
                return;
            }

            if (result.StartsWith("OK", StringComparison.OrdinalIgnoreCase))
            {
                _setStatus("上次应用内覆盖更新已完成。");
                TryDeleteFile(resultPath);
                TryDeleteFile(GetPortableUpdateInProgressPath(updateRoot));
                return;
            }

            if (result.StartsWith("FAILED", StringComparison.OrdinalIgnoreCase))
            {
                var message = $"上次应用内覆盖更新失败。日志：{GetPortableUpdateLogPath(updateRoot)}";
                _setStatus(message);
                if (!silent)
                {
                    _updateUi?.ReportFailed(message);
                }
                TryDeleteFile(GetPortableUpdateInProgressPath(updateRoot));
            }
        }
        catch
        {
        }
    }

    private async Task<bool> CloseIfPortableUpdateIsInProgressAsync()
    {
        var updateRoot = GetUpdateRoot();
        var inProgressPath = GetPortableUpdateInProgressPath(updateRoot);
        if (!File.Exists(inProgressPath))
        {
            return false;
        }

        var age = DateTimeOffset.UtcNow - File.GetLastWriteTimeUtc(inProgressPath);
        if (age > TimeSpan.FromMinutes(10))
        {
            TryDeleteFile(inProgressPath);
            return false;
        }

        const string message = "更新正在完成，请稍候。应用将关闭以避免阻塞更新。";
        _setStatus(message);
        _updateUi?.ReportProgress(message, 0);
        await Task.Delay(1800);
        ShutdownApplication(forUpdateRestart: true);
        return true;
    }

    private static void ShutdownApplication(bool forUpdateRestart)
    {
        if (WpfApplication.Current is App app)
        {
            if (forUpdateRestart)
            {
                app.RequestExitForUpdate();
            }
            else
            {
                app.RequestExit();
            }
            return;
        }

        WpfApplication.Current.Shutdown();
    }

    private static void WritePortableUpdateInProgress(string inProgressPath)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(inProgressPath) ?? GetUpdateRoot());
        File.WriteAllText(
            inProgressPath,
            DateTimeOffset.UtcNow.ToString("O"),
            new UTF8Encoding(false));
    }

    private static void AppendPortableUpdateLog(string logPath, string message)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(logPath) ?? GetUpdateRoot());
            File.AppendAllText(
                logPath,
                $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}",
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
        catch
        {
            // Update diagnostics must not block an otherwise valid update.
        }
    }

    private static string GetUpdateRoot()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "StarBridge",
            "Updates");
    }

    private static string GetPortableUpdateResultPath(string updateRoot)
    {
        return Path.Combine(updateRoot, "last-update-result.txt");
    }

    private static string GetPortableUpdateLogPath(string updateRoot)
    {
        return Path.Combine(updateRoot, "update.log");
    }

    private static string GetPortableUpdateInProgressPath(string updateRoot)
    {
        return Path.Combine(updateRoot, "update-in-progress.lock");
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    private static bool IsNewerVersion(string remoteVersion, string currentVersion)
    {
        return Version.TryParse(NormalizeVersionForCompare(remoteVersion), out var remote) &&
               Version.TryParse(NormalizeVersionForCompare(currentVersion), out var current) &&
               remote > current;
    }

    private static string NormalizeVersionForCompare(string value)
    {
        var version = value.Trim().TrimStart('v', 'V');
        var parts = version.Split('.', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length switch
        {
            1 => $"{parts[0]}.0.0",
            2 => $"{parts[0]}.{parts[1]}.0",
            _ => version
        };
    }
}

internal interface IAppUpdateUi
{
    Task<bool> ConfirmUpdateAsync(UpdateManifest manifest, string currentVersion, string updateMode);

    void ReportProgress(string status, long? percent);

    void ReportCompleted(string status);

    Task<bool> ConfirmRestartAsync(string status);

    void ReportFailed(string status);
}
