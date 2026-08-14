using System.Collections.ObjectModel;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using StarBridge.Desktop.Theming;

namespace StarBridge.Desktop;

public partial class HangarReaderWindow : Window
{
    private const int MaxHangarScanPages = 100;

    private readonly string _language;
    private readonly ObservableCollection<OwnedShipRecord> _detectedShips = [];
    private bool _isScanning;
    private bool _scanCompleted;

    private sealed record HangarPageState(
        int Page,
        int TotalPages,
        int KindCount,
        HangarShipCandidate[] Candidates);

    private sealed record HangarNavigationResult(
        bool IsSuccess,
        Microsoft.Web.WebView2.Core.CoreWebView2WebErrorStatus WebErrorStatus);

    public HangarReaderWindow(string language)
    {
        InitializeComponent();
        BridgeSceneContext.ApplyFixed(this, BridgeSceneKind.Hangar);
        _language = language;
        DetectedShipsList.ItemsSource = _detectedShips;
        Loaded += async (_, _) =>
        {
            try
            {
                await HangarWebView.EnsureCoreWebView2Async();
            }
            catch (Exception exception)
            {
                ReaderStatusText.Text = UserFacingError.Describe(exception, "机库页面未能启动，请重新打开扫描器。" );
            }
        };
    }

    public IReadOnlyList<OwnedShipRecord> ImportedShips { get; private set; } = [];

    private void GoButton_Click(object sender, RoutedEventArgs e)
    {
        if (!Uri.TryCreate(AddressBox.Text.Trim(), UriKind.Absolute, out var uri) || !IsOfficialHangarUri(uri))
        {
            ReaderStatusText.Text = "请输入 RSI 官网机库地址。";
            return;
        }

        HangarWebView.Source = uri;
    }

    private async void ScanFullHangarButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isScanning)
        {
            return;
        }

        _isScanning = true;
        _scanCompleted = false;
        ReaderLoadingIndicator.IsActive = true;
        ReaderLoadingIndicator.Visibility = Visibility.Visible;
        _detectedShips.Clear();
        ImportButton.IsEnabled = false;
        ScanFullHangarButton.IsEnabled = false;
        GoButton.IsEnabled = false;
        PageShipCountText.Text = "扫描页数：0";
        TotalShipCountText.Text = "累计：0";

        try
        {
            await HangarWebView.EnsureCoreWebView2Async();

            var firstPageUri = BuildHangarPageUri(GetConfiguredHangarUri(), 1);
            await NavigateToHangarPageAsync(firstPageUri);
            var firstPageState = await WaitForHangarPageStateAsync(1);
            var totalPages = Math.Max(1, firstPageState.TotalPages);
            if (totalPages > MaxHangarScanPages)
            {
                throw new InvalidOperationException($"官网机库分页共 {totalPages} 页，超过 {MaxHangarScanPages} 页安全上限。");
            }

            var pageCount = 0;
            var matchedCodes = 0;
            var matchedNames = 0;
            var imageCandidates = new Dictionary<string, HangarShipImageCandidate>(StringComparer.OrdinalIgnoreCase);

            for (var page = 1; page <= totalPages; page++)
            {
                var pageState = firstPageState;
                if (page > 1)
                {
                    await NavigateToHangarPageAsync(BuildHangarPageUri(firstPageUri, page));
                    pageState = await WaitForHangarPageStateAsync(page);
                }

                var result = HangarShipImporter.ImportOfficialShipCandidates(pageState.Candidates, _language);
                matchedCodes += result.MatchedCodes;
                matchedNames += result.MatchedNames;
                AddDetectedShips(result.Ships);
                foreach (var imageCandidate in result.ImageCandidates)
                {
                    imageCandidates.TryAdd(imageCandidate.Code, imageCandidate);
                }
                pageCount++;

                PageShipCountText.Text = $"扫描页数：{pageCount}/{totalPages}";
                TotalShipCountText.Text = $"累计：{_detectedShips.Count}";
                ReaderStatusText.Text = $"正在扫描：第 {pageCount}/{totalPages} 页，累计识别 {_detectedShips.Count} 艘。";
            }

            ReaderStatusText.Text = imageCandidates.Count == 0
                ? "舰船记录读取完成，当前页面没有提供可读取的舰船图片。"
                : $"舰船记录读取完成，正在读取 {imageCandidates.Count} 张舰船图片…";
            var imageSummary = await HangarImportedShipImageCache.ImportAsync(imageCandidates.Values);

            _scanCompleted = true;
            ImportButton.IsEnabled = _detectedShips.Count > 0;
            ReaderStatusText.Text = $"整库扫描完成：扫描 {pageCount} 页，页面舰船条目 {matchedCodes} 个，已识别 {matchedNames} 个，累计 {_detectedShips.Count} 艘；本地可用图片 {imageSummary.AvailableCount}/{imageSummary.CandidateCount} 张。";
        }
        catch (Exception exception)
        {
            _scanCompleted = false;
            ImportButton.IsEnabled = false;
            ReaderStatusText.Text = UserFacingError.Describe(exception, "机库扫描未完成，请确认页面已登录后重试。" );
        }
        finally
        {
            _isScanning = false;
            ReaderLoadingIndicator.IsActive = false;
            ReaderLoadingIndicator.Visibility = Visibility.Collapsed;
            ScanFullHangarButton.IsEnabled = true;
            GoButton.IsEnabled = true;
        }
    }

    private void ImportButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_scanCompleted)
        {
            ReaderStatusText.Text = "请先完成一次整库扫描，再导入舰船库。";
            return;
        }

        ImportedShips = _detectedShips.ToArray();
        DialogResult = true;
        Close();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            ToggleWindowMaximize();
            return;
        }

        DragMove();
    }

    private void MinimizeWindowButton_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState.Minimized;
    }

    private void MaximizeWindowButton_Click(object sender, RoutedEventArgs e)
    {
        ToggleWindowMaximize();
    }

    private void HangarReaderWindow_StateChanged(object? sender, EventArgs e)
    {
        UpdateMaximizeButtonState();
    }

    private void ToggleWindowMaximize()
    {
        WindowState = WindowState == WindowState.Maximized
            ? WindowState.Normal
            : WindowState.Maximized;
        UpdateMaximizeButtonState();
    }

    private void UpdateMaximizeButtonState()
    {
        if (MaximizeWindowButton is null)
        {
            return;
        }

        var isMaximized = WindowState == WindowState.Maximized;
        MaximizeWindowButton.Tag = isMaximized ? "Restore" : "Maximize";
        MaximizeWindowButton.ToolTip = isMaximized ? "还原" : "最大化";
    }

    private async Task<HangarPageState> ReadCurrentHangarPageStateAsync()
    {
        var json = await HangarWebView.ExecuteScriptAsync("""
            (() => {
              const readPageFromHref = href => {
                try {
                  const value = new URL(href, window.location.href).searchParams.get('page');
                  const page = Number.parseInt(value || '', 10);
                  return Number.isFinite(page) ? page : 0;
                } catch {
                  return 0;
                }
              };
              const urlPage = readPageFromHref(window.location.href) || 1;
              const activePage = Array.from(document.querySelectorAll('.pager a.active, .pager .active'))
                .map(element => Number.parseInt((element.textContent || '').trim(), 10))
                .find(page => Number.isFinite(page)) || 0;
              const pagerPages = Array.from(document.querySelectorAll('.pager a[href*="page="], a[href*="account/pledges"][href*="page="]'))
                .map(element => readPageFromHref(element.getAttribute('href') || ''))
                .filter(page => Number.isFinite(page) && page > 0);
              const page = activePage || urlPage || 1;
              const totalPages = Math.max(page, 1, ...pagerPages);
              const kinds = Array.from(document.querySelectorAll('.kind'));
              const ships = [];
              const normalizeImageUrl = value => {
                if (!value || value.startsWith('data:') || value.startsWith('blob:')) {
                  return '';
                }
                try {
                  const url = new URL(value, window.location.href);
                  return url.protocol === 'https:' ? url.href : '';
                } catch {
                  return '';
                }
              };
              const readLargestSrcsetUrl = value => {
                if (!value) {
                  return '';
                }
                return value
                  .split(',')
                  .map(entry => {
                    const parts = entry.trim().split(/\s+/);
                    const descriptor = parts[1] || '1x';
                    const score = descriptor.endsWith('w')
                      ? Number.parseFloat(descriptor)
                      : Number.parseFloat(descriptor) * 1000;
                    return { url: parts[0] || '', score: Number.isFinite(score) ? score : 0 };
                  })
                  .sort((left, right) => right.score - left.score)
                  .map(entry => normalizeImageUrl(entry.url))
                  .find(Boolean) || '';
              };
              const readImageUrl = root => {
                if (!root) {
                  return '';
                }
                const selectors = [
                  '.image img',
                  '.pledge-image img',
                  '.thumbnail img',
                  '.item-image img',
                  'img'
                ];
                for (const selector of selectors) {
                  for (const image of root.querySelectorAll(selector)) {
                    const values = [
                      readLargestSrcsetUrl(image.getAttribute('data-srcset')),
                      readLargestSrcsetUrl(image.getAttribute('srcset')),
                      image.getAttribute('data-original'),
                      image.getAttribute('data-large-src'),
                      image.getAttribute('data-src'),
                      image.getAttribute('data-lazy-src'),
                      image.currentSrc,
                      image.getAttribute('src')
                    ];
                    for (const value of values) {
                      const resolved = normalizeImageUrl(value || '');
                      if (resolved) {
                        return resolved;
                      }
                    }
                  }
                }
                for (const element of root.querySelectorAll('[style*="background"]')) {
                  const background = element.style.backgroundImage || getComputedStyle(element).backgroundImage || '';
                  const match = background.match(/url\(["']?([^"')]+)["']?\)/i);
                  const resolved = normalizeImageUrl(match ? match[1] : '');
                  if (resolved) {
                    return resolved;
                  }
                }
                return '';
              };
              kinds.forEach((kind, itemIndex) => {
                const kindText = (kind.textContent || '').trim().toLowerCase();
                if (kindText !== 'ship' && kindText !== '飞船') {
                  return;
                }
                const item = kind.closest('.item') || kind.parentElement;
                const title = item && item.querySelector('.title')
                  ? item.querySelector('.title').textContent.trim()
                  : '';
                const liner = item && item.querySelector('.liner')
                  ? item.querySelector('.liner').textContent.trim()
                  : '';
                const pledge = item
                  ? (item.closest('li') || item.closest('.row') || item)
                  : null;
                const pledgeNameInput = pledge ? pledge.querySelector('input.js-pledge-name') : null;
                const pledgeName = pledgeNameInput
                  ? (pledgeNameInput.getAttribute('value') || pledgeNameInput.value || '').trim()
                  : '';
                const pledgeTitle = pledge
                  ? (pledge.querySelector('.title-col h3')?.textContent || '').replace(/\s+/g, ' ').trim()
                  : '';
                const sourceTitle = pledgeName || pledgeTitle;
                const imageUrl = readImageUrl(item) || readImageUrl(pledge);
                const dateCol = pledge ? pledge.querySelector('.date-col') : null;
                const createdAtText = dateCol
                  ? (dateCol.textContent || '')
                      .replace(/\s+/g, ' ')
                      .replace(/^\s*(Created|Acquired|创建|建立|入库|获得|获取)\s*:?\s*/i, '')
                      .trim()
                  : '';
                const explicitInstanceId = [item, pledge]
                  .filter(Boolean)
                  .flatMap(element => [
                    element.getAttribute('data-pledge-id'),
                    element.getAttribute('data-item-id'),
                    element.getAttribute('data-id'),
                    element.id
                  ])
                  .find(value => value && value.trim());
                const manufacturer = liner.match(/\(([A-Z0-9]{3,5})\)/);
                if (title) {
                  ships.push({
                    Title: title,
                    ManufacturerCode: manufacturer ? manufacturer[1] : '',
                    CreatedAtText: createdAtText,
                    SourceTitle: sourceTitle,
                    InstanceId: explicitInstanceId
                      ? `rsi:${explicitInstanceId.trim()}`
                      : null,
                    ImageUrl: imageUrl
                  });
                }
              });
              return { Page: page, TotalPages: totalPages, KindCount: kinds.length, Candidates: ships };
            })();
            """);

        return JsonSerializer.Deserialize<HangarPageState>(json) ?? new HangarPageState(1, 1, 0, []);
    }

    private Uri GetConfiguredHangarUri()
    {
        if (!Uri.TryCreate(AddressBox.Text.Trim(), UriKind.Absolute, out var uri) || !IsOfficialHangarUri(uri))
        {
            throw new InvalidOperationException("请输入 RSI 官网机库地址。");
        }

        return uri;
    }

    private static bool IsOfficialHangarUri(Uri uri)
    {
        return uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) &&
               (uri.Host.Equals("robertsspaceindustries.com", StringComparison.OrdinalIgnoreCase) ||
                uri.Host.EndsWith(".robertsspaceindustries.com", StringComparison.OrdinalIgnoreCase)) &&
               uri.AbsolutePath.Contains("/account/pledges", StringComparison.OrdinalIgnoreCase);
    }

    private async Task NavigateToHangarPageAsync(Uri uri)
    {
        if (string.Equals(HangarWebView.Source?.ToString(), uri.ToString(), StringComparison.OrdinalIgnoreCase))
        {
            await WaitForDocumentReadyAsync();
            return;
        }

        var completion = new TaskCompletionSource<HangarNavigationResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        void Handler(object? sender, Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs args)
        {
            completion.TrySetResult(new HangarNavigationResult(args.IsSuccess, args.WebErrorStatus));
        }

        HangarWebView.NavigationCompleted += Handler;
        try
        {
            HangarWebView.Source = uri;
            var finished = await Task.WhenAny(completion.Task, Task.Delay(TimeSpan.FromSeconds(20)));
            if (!ReferenceEquals(finished, completion.Task))
            {
                throw new TimeoutException($"打开机库页面超时：{uri}");
            }

            var result = await completion.Task;
            if (!result.IsSuccess && !await IsCurrentHangarPageAsync())
            {
                throw new InvalidOperationException($"打开机库页面失败：{uri}（{result.WebErrorStatus}）");
            }
        }
        finally
        {
            HangarWebView.NavigationCompleted -= Handler;
        }

        await WaitForDocumentReadyAsync();
    }

    private async Task<bool> IsCurrentHangarPageAsync()
    {
        try
        {
            var hrefJson = await HangarWebView.ExecuteScriptAsync("window.location.href");
            var href = JsonSerializer.Deserialize<string>(hrefJson) ?? "";
            return href.Contains("/account/pledges", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    private async Task WaitForDocumentReadyAsync()
    {
        for (var attempt = 0; attempt < 40; attempt++)
        {
            var readyJson = await HangarWebView.ExecuteScriptAsync("document.readyState");
            var readyState = JsonSerializer.Deserialize<string>(readyJson);
            if (string.Equals(readyState, "interactive", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(readyState, "complete", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            await Task.Delay(250);
        }

        throw new TimeoutException("机库页面加载超时。");
    }

    private async Task<HangarPageState> WaitForHangarPageStateAsync(int expectedPage)
    {
        string? previousSignature = null;
        HangarPageState? previousState = null;

        for (var attempt = 0; attempt < 50; attempt++)
        {
            var state = await ReadCurrentHangarPageStateAsync();
            var signature = BuildCandidateSignature(state.Candidates);
            if (state.Page == expectedPage &&
                state.KindCount > 0 &&
                previousState?.Page == state.Page &&
                string.Equals(previousSignature, signature, StringComparison.OrdinalIgnoreCase))
            {
                return state;
            }

            previousState = state;
            previousSignature = signature;
            await Task.Delay(300);
        }

        throw new TimeoutException($"第 {expectedPage} 页内容未稳定，扫描已停止。");
    }

    private void AddDetectedShips(IEnumerable<OwnedShipRecord> ships)
    {
        foreach (var ship in ships)
        {
            if (_detectedShips.Any(existing =>
                    !string.IsNullOrWhiteSpace(ship.InstanceId) &&
                    string.Equals(existing.InstanceId, ship.InstanceId, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }

            _detectedShips.Add(ship);
        }
    }

    private static string BuildCandidateSignature(IEnumerable<HangarShipCandidate> candidates)
    {
        return string.Join(
            "|",
            candidates
                .Select(candidate => $"{candidate.InstanceId?.Trim()}::{candidate.Title.Trim()}::{candidate.ManufacturerCode.Trim()}::{candidate.CreatedAtText?.Trim()}::{candidate.SourceTitle?.Trim()}::{candidate.ImageUrl?.Trim()}")
                .OrderBy(value => value, StringComparer.OrdinalIgnoreCase));
    }

    private static Uri BuildHangarPageUri(Uri baseUri, int page)
    {
        var builder = new UriBuilder(baseUri)
        {
            Fragment = ""
        };
        var query = builder.Query.TrimStart('?');
        var parts = query.Length == 0
            ? new List<string>()
            : query.Split('&', StringSplitOptions.RemoveEmptyEntries).ToList();
        var replaced = false;

        for (var index = 0; index < parts.Count; index++)
        {
            var equalsIndex = parts[index].IndexOf('=');
            var key = equalsIndex >= 0 ? parts[index][..equalsIndex] : parts[index];
            if (!key.Equals("page", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            parts[index] = $"page={page}";
            replaced = true;
        }

        if (!replaced)
        {
            parts.Insert(0, $"page={page}");
        }

        builder.Query = string.Join("&", parts);
        return builder.Uri;
    }
}
