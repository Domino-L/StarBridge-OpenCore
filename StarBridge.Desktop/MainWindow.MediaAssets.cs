using Microsoft.Win32;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private async void ChooseAvatar_Click(object sender, RoutedEventArgs e)
    {
        var croppedPath = ChooseAndCropImage("选择个人头像", "player-avatar.png", LocalImageStorage.UserAsset);
        if (croppedPath is null)
        {
            return;
        }

        _avatarPath = croppedPath;
        _cachedAvatarImagePath = null;
        _cachedAvatarImageData = null;
        SaveCurrentConfig();
        LoadAvatarPreview();
        RenderState();
        await UpdateProfileAsync(includeAvatarImage: true);
        await PushLocalSnapshotAsync(silent: true);
        _fleetChatNeedsFullHistoryRefresh = true;
        if (IsFleetChatVisible())
        {
            await RefreshFleetChatMessagesAsync(showErrors: false, forceFullHistory: true);
        }
        AppendOutput("Profile avatar updated.");
    }

    private void OpenHangarReaderButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("读取官网机库需要先登录。"))
        {
            return;
        }

        var reader = new HangarReaderWindow(_language)
        {
            Owner = this
        };

        if (reader.ShowDialog() != true)
        {
            return;
        }

        ReplaceOwnedShipsFromImport(reader.ImportedShips);
        SaveOwnedShips();
        UpdateShipDatabaseSummary(reader.ImportedShips.Count, reader.ImportedShips.Count);
        AppendOutput($"Ship database imported from WebView2 reader. ships={_ownedShips.Count}");
    }

    private async void ClearShipDatabaseButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("清空舰船数据库需要先登录。"))
        {
            return;
        }

        if (_ownedShips.Count == 0)
        {
            return;
        }

        var confirmed = await ShowAppConfirmationAsync(
            "清空个人机库？",
            $"将移除当前读取到的 {_ownedShips.Count} 艘舰船。",
            "本地机库记录会被清空，并在下次同步时从舰队舰船库移除。之后仍可重新读取 RSI 官网机库。",
            "确认清空",
            "保留机库");
        if (!confirmed)
        {
            return;
        }

        _ownedShips.Clear();
        SaveOwnedShips();
        UpdateShipDatabaseSummary();
        AppendOutput("Ship database cleared.");
    }

    private void OpenPersonalHangarDetailsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("查看个人机库明细需要先登录。"))
        {
            return;
        }

        var window = new Window
        {
            Title = "个人机库明细",
            Owner = this,
            Width = 920,
            Height = 540,
            MinWidth = 760,
            MinHeight = 420,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = FindBrush("PanelBackgroundBrush", new SolidColorBrush(Color.FromRgb(6, 16, 26))),
            Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
            UseLayoutRounding = true,
            SnapsToDevicePixels = true
        };

        var root = new Grid
        {
            Margin = new Thickness(18)
        };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var header = new StackPanel
        {
            Margin = new Thickness(0, 0, 0, 14)
        };
        header.Children.Add(new TextBlock
        {
            Text = "个人舰船明细",
            Foreground = FindBrush("AccentBrush", Brushes.DeepSkyBlue),
            FontSize = 18,
            FontWeight = FontWeights.SemiBold
        });
        header.Children.Add(new TextBlock
        {
            Text = $"已验证舰船 {_ownedShips.Count} 艘 · 数据来源 RSI 官网机库",
            Foreground = FindBrush("MutedTextBrush", Brushes.LightSteelBlue),
            FontSize = 11,
            Margin = new Thickness(0, 5, 0, 0)
        });
        root.Children.Add(header);

        if (_ownedShips.Count == 0)
        {
            var empty = new Border
            {
                Padding = new Thickness(20),
                Background = new SolidColorBrush(Color.FromRgb(8, 23, 34)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(23, 52, 71)),
                BorderThickness = new Thickness(1),
                Child = new StackPanel
                {
                    VerticalAlignment = VerticalAlignment.Center,
                    Children =
                    {
                        new TextBlock
                        {
                            Text = "暂无机库数据",
                            Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
                            FontSize = 16,
                            FontWeight = FontWeights.SemiBold,
                            HorizontalAlignment = HorizontalAlignment.Center
                        },
                        new TextBlock
                        {
                            Text = "读取官网机库后将在此显示。",
                            Foreground = FindBrush("MutedTextBrush", Brushes.LightSteelBlue),
                            FontSize = 12,
                            Margin = new Thickness(0, 8, 0, 0),
                            HorizontalAlignment = HorizontalAlignment.Center
                        }
                    }
                }
            };
            Grid.SetRow(empty, 1);
            root.Children.Add(empty);
        }
        else
        {
            var rows = new StackPanel
            {
                Margin = new Thickness(0, 0, 8, 0)
            };
            foreach (var ship in _ownedShips)
            {
                var row = new Border
                {
                    Margin = new Thickness(0, 0, 0, 8),
                    Padding = new Thickness(12, 9, 12, 9),
                    Background = new SolidColorBrush(Color.FromRgb(10, 24, 35)),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(23, 52, 71)),
                    BorderThickness = new Thickness(1)
                };
                var rowGrid = new Grid();
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2.1, GridUnitType.Star) });
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1.5, GridUnitType.Star) });
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });

                var identity = new StackPanel();
                identity.Children.Add(new TextBlock
                {
                    Text = ship.DisplayName,
                    Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
                    FontWeight = FontWeights.SemiBold,
                    FontSize = 13,
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
                identity.Children.Add(new TextBlock
                {
                    Text = ship.Code,
                    Foreground = FindBrush("MutedTextBrush", Brushes.LightSteelBlue),
                    FontSize = 10.5,
                    Margin = new Thickness(0, 3, 0, 0),
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
                rowGrid.Children.Add(identity);

                var source = BuildHangarDetailCell("来源", ship.Source);
                Grid.SetColumn(source, 1);
                rowGrid.Children.Add(source);

                var value = BuildHangarDetailCell("价值", string.IsNullOrWhiteSpace(ship.ValueDisplay) ? "-" : ship.ValueDisplay);
                Grid.SetColumn(value, 2);
                rowGrid.Children.Add(value);

                var acquired = BuildHangarDetailCell("入库", string.IsNullOrWhiteSpace(ship.ImportedAtDisplay) ? "-" : ship.ImportedAtDisplay);
                Grid.SetColumn(acquired, 3);
                rowGrid.Children.Add(acquired);

                var synced = BuildHangarDetailCell("同步", string.IsNullOrWhiteSpace(ship.SyncedAtDisplay) ? "-" : ship.SyncedAtDisplay);
                Grid.SetColumn(synced, 4);
                rowGrid.Children.Add(synced);

                row.Child = rowGrid;
                rows.Children.Add(row);
            }

            var scroller = new ScrollViewer
            {
                Content = rows,
                Background = new SolidColorBrush(Color.FromRgb(7, 19, 29)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(23, 52, 71)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(10),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            Grid.SetRow(scroller, 1);
            root.Children.Add(scroller);
        }

        window.Content = root;
        window.ShowDialog();
    }

    private void PersonalHangarShareSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        ShowPersonalDashboardSection(PersonalDashboardSection.SyncPrivacy);
    }

    private StackPanel BuildHangarDetailCell(string label, string value)
    {
        var panel = new StackPanel
        {
            Margin = new Thickness(10, 0, 0, 0)
        };
        panel.Children.Add(new TextBlock
        {
            Text = label,
            Foreground = FindBrush("MutedTextBrush", Brushes.LightSteelBlue),
            FontSize = 10
        });
        panel.Children.Add(new TextBlock
        {
            Text = value,
            Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
            FontSize = 11.5,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 3, 0, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        return panel;
    }

    private void OpenPersonalConfigDirectoryButton_Click(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
        Process.Start(new ProcessStartInfo
        {
            FileName = DesktopAppConfig.ConfigDirectory,
            UseShellExecute = true
        });
    }

    private void ClearPersonalCacheButton_Click(object sender, RoutedEventArgs e)
    {
        var cacheDirectory = GetLocalImageCacheDirectory();
        var currentAvatarPath = !string.IsNullOrWhiteSpace(_avatarPath) && File.Exists(_avatarPath)
            ? _avatarPath
            : null;
        if (StarBridgeMessageBox.Show(
                "确认清理本地图片缓存？只会删除可重新生成的临时图片，头像、账号、舰队和机库数据不会被删除。",
                "清理图片缓存",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            if (Directory.Exists(cacheDirectory))
            {
                foreach (var file in Directory.EnumerateFiles(cacheDirectory, "*", SearchOption.AllDirectories))
                {
                    try
                    {
                        if (IsSamePath(file, currentAvatarPath))
                        {
                            continue;
                        }

                        File.Delete(file);
                    }
                    catch
                    {
                        // Keep going if a preview image is temporarily locked.
                    }
                }

                foreach (var directory in Directory.EnumerateDirectories(cacheDirectory, "*", SearchOption.AllDirectories)
                             .OrderByDescending(path => path.Length))
                {
                    try
                    {
                        if (!Directory.EnumerateFileSystemEntries(directory).Any())
                        {
                            Directory.Delete(directory);
                        }
                    }
                    catch
                    {
                        // Best-effort cleanup only.
                    }
                }
            }

            System.Windows.MessageBox.Show("本地图片缓存已清理。头像和个人数据未受影响。", "清理完成", MessageBoxButton.OK, MessageBoxImage.Information);
            AppendOutput("Personal image cache cleared.");
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show(UserFacingError.Describe(ex, "图片缓存未能清理，请关闭正在使用图片的窗口后重试。"), "清理失败", MessageBoxButton.OK, MessageBoxImage.Error);
            AppendOutput($"Personal cache cleanup failed: {ex.Message}");
        }
    }

    private async void RefreshPersonalStatusButton_Click(object sender, RoutedEventArgs e)
    {
        var button = sender as System.Windows.Controls.Button;
        if (button is not null)
        {
            button.IsEnabled = false;
        }

        var previousCursor = Mouse.OverrideCursor;
        Mouse.OverrideCursor = Cursors.Wait;

        try
        {
            var serverRefresh = await RefreshGameServerFromLogSnapshotAsync();
            RefreshHeaderStatusBar();
            RefreshPersonalIdentityConsole();
            UpdateShipDatabaseSummary();
            RefreshPersonalHangarActivity();

            if (serverRefresh.Found)
            {
                AppendOutput(serverRefresh.Message);
            }
            else if (!string.IsNullOrWhiteSpace(serverRefresh.Message))
            {
                AppendOutput($"Personal console status refreshed. {serverRefresh.Message}");
            }
            else
            {
                AppendOutput("Personal console status refreshed.");
            }
        }
        catch (Exception ex)
        {
            AppendOutput($"Personal console status refresh failed: {ex.Message}");
            StarBridgeMessageBox.Show(
                UserFacingError.Describe(ex, "应用状态暂时无法刷新，请稍后重试。"),
                "刷新失败",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
        finally
        {
            Mouse.OverrideCursor = previousCursor;
            if (button is not null)
            {
                button.IsEnabled = true;
            }
        }
    }

    private void CopyPersonalDiagnosticInfoButton_Click(object sender, RoutedEventArgs e)
    {
        var diagnosticText = string.Join(Environment.NewLine, new[]
        {
            "[身份]",
            $"显示名称：{PersonalDisplayNameText.Text}",
            $"邮箱：{PersonalMaskedEmailText.Text}",
            $"身份标识：{GameNameText.Text}",
            $"舰队：{LocalFleetText.Text}",
            "",
            "[本地日志与识别]",
            $"游戏日志路径（Game.log）：{LogPathBox.Text}",
            $"日志监听：{PersonalLogMonitorText.Text}",
            $"最后读取：{PersonalLogLastReadText.Text}",
            $"玩家识别：{GameNameText.Text}",
            $"游戏进程：{PersonalGameProcessText.Text}",
            $"服务器区域：{PersonalServerRegionText.Text}",
            $"服务器分线：{PersonalShardText.Text}",
            $"当前飞船：{PersonalCurrentShipText.Text}",
            "",
            "[健康检查与建议]",
            $"身份匹配：{PersonalIdentityHealthResultText.Text} - {PersonalIdentityHealthHintText.Text}",
            $"日志监听：{PersonalLogHealthResultText.Text} - {PersonalLogHealthHintText.Text}",
            $"游戏状态：{PersonalGameHealthResultText.Text} - {PersonalGameHealthHintText.Text}",
            $"服务器信息：{PersonalPuHealthResultText.Text} - {PersonalPuHealthHintText.Text}",
            $"同步策略：{PersonalSyncPolicyHealthResultText.Text} - {PersonalSyncPolicyHealthHintText.Text}"
        });

        try
        {
            System.Windows.Clipboard.SetText(diagnosticText);
            AppendOutput("Personal diagnostic information copied.");
        }
        catch (Exception ex)
        {
            AppendOutput($"Failed to copy personal diagnostic information: {ex.Message}");
        }
    }

    private async void ChooseFleetLogo_Click(object sender, RoutedEventArgs e)
    {
        if (!_hasFleet && !_isCreatingFleet)
        {
            AppendOutput("Open fleet creation before choosing a fleet logo.");
            return;
        }

        if (_hasFleet && !CanCurrentUserEditFleetAvatar())
        {
            AppendOutput("Current account cannot update the fleet logo.");
            return;
        }

        var croppedPath = ChooseAndCropImage(
            "选择舰队标志",
            "fleet-logo.png",
            LocalImageStorage.UserAsset);
        if (croppedPath is null)
        {
            return;
        }

        if (!ValidateRequiredFleetImagePayload("舰队标志", croppedPath, FleetSyncImageMaxBytes))
        {
            return;
        }

        if (!_hasFleet && _isCreatingFleet)
        {
            _createFleetLogoPath = croppedPath;
            LoadCreateFleetLogoPreview();
            AppendOutput("Fleet logo selected for new fleet.");
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        _fleetLogoPath = croppedPath;
        MarkLocalFleetLogoEdit();
        LoadCreateFleetLogoPreview();
        LoadFleetHeaderLogoPreview();
        RefreshManageFleetBasicProfile();
        SaveCurrentConfig();
        if (_hasFleet)
        {
            if (!await PushFleetInfoAsync(silent: false, includeImages: true, requireLogoImage: true, scope: FleetInfoUpdateScope.Logo))
            {
                RestoreFleetStateAfterFailedMutation(rollbackState, "舰队队标同步失败，已恢复本地队标状态。");
                LoadCreateFleetLogoPreview();
                LoadFleetHeaderLogoPreview();
                RefreshManageFleetBasicProfile();
                return;
            }
        }

        AppendOutput("Fleet logo updated.");
    }

    private void ChooseFleetBanner_Click(object sender, RoutedEventArgs e)
    {
        SetFleetDescriptionStatus("舰队横幅功能已停用。", ManageProfileStatusTone.Locked);
        AppendOutput("Fleet banner feature is disabled.");
    }

    private void OpenFleetBannerPickerOverlay()
    {
        _bannerPickerDropZoneDefaultBackground ??= BannerPickerDropZone.Background;
        _bannerPickerDropZoneDefaultBorder ??= BannerPickerDropZone.BorderBrush;

        ResetFleetBannerPickerUi();
        FleetBannerPickerOverlay.Visibility = Visibility.Visible;

        var canRestoreDefault = !string.IsNullOrWhiteSpace(_fleetBannerPath);
        BannerPickerRestoreDefaultButton.IsEnabled = canRestoreDefault;
        BannerPickerRestoreDefaultButton.Opacity = canRestoreDefault ? 1 : 0.58;

        var pickerSourcePath = GetFleetBannerPickerSourcePath();
        if (TryLoadBitmapImage(pickerSourcePath, out var currentBanner) && currentBanner is not null)
        {
            LoadFleetBannerPickerSource(pickerSourcePath!, currentBanner, isCurrentBanner: true);
            BannerPickerStatusText.Text = string.Equals(pickerSourcePath, _fleetBannerSourcePath, StringComparison.OrdinalIgnoreCase)
                ? "当前横幅原图已载入，可重新裁剪。"
                : "当前横幅已载入。旧版本未记录原图，只能从当前成品继续。";
            BannerPickerFileStateText.Text = string.Equals(pickerSourcePath, _fleetBannerSourcePath, StringComparison.OrdinalIgnoreCase)
                ? "这是上次使用的原图。移动或缩放裁剪框后可重新应用横幅。"
                : "未找到原图记录。重新选择图片后会保留原图用于下次裁剪。";
        }
    }

    private string? GetFleetBannerPickerSourcePath()
    {
        return !string.IsNullOrWhiteSpace(_fleetBannerSourcePath) && File.Exists(_fleetBannerSourcePath)
            ? _fleetBannerSourcePath
            : _fleetBannerPath;
    }

    private void ResetFleetBannerPickerUi()
    {
        _bannerPickerSourceImage = null;
        _bannerPickerPreviewImage = null;
        _bannerPickerSourcePath = null;
        _bannerPickerImageDisplayRect = Rect.Empty;
        _bannerPickerCropRect = Rect.Empty;
        _bannerPickerCropScale = 1.0;
        _isBannerCropDragging = false;
        _isBannerCropResizing = false;
        _bannerCropResizeHandle = "";

        BannerPickerPreviewImage.Source = null;
        BannerPickerPreviewImage.Visibility = Visibility.Collapsed;
        BannerPickerPreviewScrim.Visibility = Visibility.Collapsed;
        BannerPickerTopVisibleAreaFrame.Visibility = Visibility.Collapsed;
        BannerPickerFindFleetPreviewImage.Source = null;
        BannerPickerFindFleetPreviewImage.Visibility = Visibility.Collapsed;
        BannerPickerFindFleetPreviewScrim.Visibility = Visibility.Collapsed;
        BannerPickerFindFleetVisibleAreaFrame.Visibility = Visibility.Collapsed;
        BannerPickerProfilePreviewImage.Source = null;
        BannerPickerProfilePreviewImage.Visibility = Visibility.Collapsed;
        BannerPickerProfilePreviewScrim.Visibility = Visibility.Collapsed;
        BannerPickerProfileVisibleAreaFrame.Visibility = Visibility.Collapsed;
        BannerPickerPreviewPlaceholder.Visibility = Visibility.Visible;
        UpdateBannerPickerPreviewFrameSize();
        BannerPickerCropSourceImage.Source = null;
        BannerPickerCropSourceImage.Visibility = Visibility.Collapsed;
        BannerPickerDropPlaceholder.Visibility = Visibility.Visible;
        BannerPickerCropSelection.Visibility = Visibility.Collapsed;
        BannerPickerApplyButton.IsEnabled = false;

        var mutedBrush = FindResource("MutedTextBrush") as System.Windows.Media.Brush ?? new SolidColorBrush(Color.FromRgb(145, 165, 181));
        BannerPickerFileNameText.Text = "未选择图片";
        BannerPickerFileStateText.Foreground = mutedBrush;
        BannerPickerFileStateText.Text = "支持 PNG / JPG / BMP / WebP。";
        BannerPickerStatusText.Foreground = mutedBrush;
        BannerPickerStatusText.Text = "等待选择图片";
        BannerPickerImageSizeText.Text = "未选择";
        BannerPickerRatioText.Text = $"目标 {GetFleetBannerCropRatio():0.0}:1 / 公开舰队横幅";
        BannerPickerFitHintText.Text = "选择图片后可拖动并缩放裁剪框，最终按裁剪框保存。";
        BannerPickerCropScaleText.Text = "100%";
        UpdateBannerPickerCropWorkspaceSize();
        _isUpdatingBannerPickerScaleControl = true;
        BannerPickerCropScaleSlider.Minimum = FleetBannerPickerMinCropScale;
        BannerPickerCropScaleSlider.Maximum = 1;
        BannerPickerCropScaleSlider.Value = 1;
        _isUpdatingBannerPickerScaleControl = false;
        BannerPickerPathText.Text = "未选择图片";

        if (_bannerPickerDropZoneDefaultBackground is not null)
        {
            BannerPickerDropZone.Background = _bannerPickerDropZoneDefaultBackground;
        }

        if (_bannerPickerDropZoneDefaultBorder is not null)
        {
            BannerPickerDropZone.BorderBrush = _bannerPickerDropZoneDefaultBorder;
        }
    }

    private void CloseFleetBannerPickerOverlay()
    {
        _isBannerCropDragging = false;
        _isBannerCropResizing = false;
        _bannerCropResizeHandle = "";
        BannerPickerCropSelection.ReleaseMouseCapture();
        FleetBannerPickerOverlay.Visibility = Visibility.Collapsed;
    }

    private void FleetBannerPickerOverlay_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (ReferenceEquals(e.OriginalSource, FleetBannerPickerOverlay))
        {
            CloseFleetBannerPickerOverlay();
        }
    }

    private void FleetBannerPickerCard_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
    }

    private void BannerPickerCancelButton_Click(object sender, RoutedEventArgs e)
    {
        CloseFleetBannerPickerOverlay();
    }

    private void BannerPickerChooseImage_Click(object sender, RoutedEventArgs e)
    {
        ChooseFleetBannerPickerImage();
    }

    private void BannerPickerDropZone_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (ReferenceEquals(e.OriginalSource, BannerPickerDropZone) ||
            ReferenceEquals(e.OriginalSource, BannerPickerCropHost) ||
            ReferenceEquals(e.OriginalSource, BannerPickerCropOverlayCanvas))
        {
            ChooseFleetBannerPickerImage();
        }
    }

    private void ChooseFleetBannerPickerImage()
    {
        var dialog = new OpenFileDialog
        {
            Title = "选择舰队横幅图片",
            Filter = "图片文件|*.png;*.jpg;*.jpeg;*.bmp;*.webp|PNG|*.png|JPEG|*.jpg;*.jpeg|BMP|*.bmp|WebP|*.webp",
            CheckFileExists = true,
            Multiselect = false
        };

        if (dialog.ShowDialog(this) == true)
        {
            LoadFleetBannerPickerImage(dialog.FileName);
        }
    }

    private void BannerPickerDropZone_DragEnter(object sender, System.Windows.DragEventArgs e)
    {
        if (GetDroppedBannerImagePath(e) is null)
        {
            e.Effects = System.Windows.DragDropEffects.None;
            e.Handled = true;
            return;
        }

        e.Effects = System.Windows.DragDropEffects.Copy;
        BannerPickerDropZone.Background = new SolidColorBrush(Color.FromRgb(12, 35, 50));
        BannerPickerDropZone.BorderBrush = new SolidColorBrush(Color.FromRgb(56, 184, 242));
        e.Handled = true;
    }

    private void BannerPickerDropZone_DragLeave(object sender, System.Windows.DragEventArgs e)
    {
        if (_bannerPickerDropZoneDefaultBackground is not null)
        {
            BannerPickerDropZone.Background = _bannerPickerDropZoneDefaultBackground;
        }

        if (_bannerPickerDropZoneDefaultBorder is not null)
        {
            BannerPickerDropZone.BorderBrush = _bannerPickerDropZoneDefaultBorder;
        }
    }

    private void BannerPickerDropZone_Drop(object sender, System.Windows.DragEventArgs e)
    {
        BannerPickerDropZone_DragLeave(sender, e);
        var path = GetDroppedBannerImagePath(e);
        if (path is null)
        {
            BannerPickerFileStateText.Text = "请拖入 PNG / JPG / BMP / WebP 图片文件。";
            BannerPickerFileStateText.Foreground = new SolidColorBrush(Color.FromRgb(217, 162, 59));
            return;
        }

        LoadFleetBannerPickerImage(path);
        e.Handled = true;
    }

    private static string? GetDroppedBannerImagePath(System.Windows.DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop))
        {
            return null;
        }

        if (e.Data.GetData(System.Windows.DataFormats.FileDrop) is not string[] files ||
            files.Length == 0)
        {
            return null;
        }

        var path = files[0];
        var extension = Path.GetExtension(path).ToLowerInvariant();
        return File.Exists(path) && extension is ".png" or ".jpg" or ".jpeg" or ".bmp" or ".webp"
            ? path
            : null;
    }

    private void LoadFleetBannerPickerImage(string path)
    {
        if (!TryLoadBitmapImage(path, out var image) || image is null)
        {
            StarBridgeMessageBox.Show(
                "无法读取这张横幅图片。请使用 PNG、JPG、BMP，或确认系统支持该 WebP 文件。",
                "横幅不可用",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        LoadFleetBannerPickerSource(path, image, isCurrentBanner: false);
    }

    private void LoadFleetBannerPickerSource(string path, BitmapImage image, bool isCurrentBanner)
    {
        _bannerPickerSourcePath = path;
        _bannerPickerSourceImage = image;
        BannerPickerCropSourceImage.Source = image;
        BannerPickerCropSourceImage.Visibility = Visibility.Visible;
        BannerPickerDropPlaceholder.Visibility = Visibility.Collapsed;
        BannerPickerFileNameText.Text = Path.GetFileName(path);
        BannerPickerFileStateText.Foreground = FindResource("MutedTextBrush") as System.Windows.Media.Brush ?? new SolidColorBrush(Color.FromRgb(145, 165, 181));
        BannerPickerFileStateText.Text = isCurrentBanner
            ? "当前横幅。选择新图片后即可裁剪并保存。"
            : "图片已载入，拖动或缩放裁剪框后可应用横幅。";
        BannerPickerStatusText.Text = isCurrentBanner
            ? "当前横幅已载入。"
            : "新图片已载入，裁剪框对应最终保存区域。";
        BannerPickerImageSizeText.Text = $"{image.PixelWidth} × {image.PixelHeight}";
        var targetRatio = GetFleetBannerCropRatio();
        BannerPickerRatioText.Text = $"图片 {(image.PixelWidth / Math.Max(1d, image.PixelHeight)):0.00}:1 / 目标 {targetRatio:0.0}:1 / {FormatBannerFileSize(path)}";
        BannerPickerFitHintText.Text = image.PixelWidth >= 1600 && image.PixelHeight >= 400
            ? "图片尺寸适合作为公开舰队横幅。寻找舰队列表会优先顶满高度。"
            : "图片尺寸偏小，建议使用更高分辨率的超宽横幅图。";
        BannerPickerPathText.Text = path;
        BannerPickerApplyButton.IsEnabled = !isCurrentBanner;
        UpdateBannerPickerCropWorkspaceSize();
        UpdateBannerPickerPreviewFrameSize();

        Dispatcher.BeginInvoke(new Action(() =>
        {
            UpdateBannerPickerCropWorkspaceSize();
            InitializeBannerPickerCrop();
            BannerPickerApplyButton.IsEnabled = !isCurrentBanner && _bannerPickerPreviewImage is not null;
        }), DispatcherPriority.Loaded);
    }

    private static string FormatBannerFileSize(string path)
    {
        try
        {
            var bytes = new FileInfo(path).Length;
            if (bytes >= 1024 * 1024)
            {
                return $"{bytes / 1024d / 1024d:0.0} MB";
            }

            return $"{Math.Max(1, bytes / 1024)} KB";
        }
        catch
        {
            return "未知大小";
        }
    }

    private double GetFleetBannerCropRatio()
    {
        return FleetBannerStandardCropRatio;
    }

    private static double ClampBannerPickerValue(double value, double min, double max)
    {
        const double epsilon = 0.0001;
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            return min;
        }

        if (max < min)
        {
            return Math.Abs(max - min) <= epsilon ? min : Math.Min(min, max);
        }

        return Math.Clamp(value, min, max);
    }

    private void UpdateBannerPickerPreviewFrameSize()
    {
        if (BannerPickerPreviewFrame is null)
        {
            return;
        }

        var width = BannerPickerPreviewFrame.ActualWidth;
        if (width <= 0 && FleetBannerPickerCard is not null)
        {
            width = Math.Max(1, FleetBannerPickerCard.ActualWidth - FleetBannerPickerCard.Padding.Left - FleetBannerPickerCard.Padding.Right);
        }

        if (width <= 0)
        {
            width = 904;
        }

        var targetHeight = width / GetFleetBannerCropRatio();
        BannerPickerPreviewFrame.Height = Math.Clamp(targetHeight, 180, 236);
    }

    private void BannerPickerCropHost_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (_bannerPickerSourceImage is null)
        {
            return;
        }

        UpdateBannerPickerCropWorkspaceSize();
        InitializeBannerPickerCrop();
    }

    private void UpdateBannerPickerCropWorkspaceSize()
    {
        if (BannerPickerDropZone is null)
        {
            return;
        }

        if (_bannerPickerSourceImage is null)
        {
            BannerPickerDropZone.Height = double.NaN;
            BannerPickerDropZone.MinHeight = 260;
            BannerPickerDropZone.VerticalAlignment = VerticalAlignment.Stretch;
            return;
        }

        var imageWidth = Math.Max(1d, _bannerPickerSourceImage.PixelWidth);
        var imageHeight = Math.Max(1d, _bannerPickerSourceImage.PixelHeight);
        var imageRatio = imageWidth / imageHeight;
        var targetRatio = GetFleetBannerCropRatio();

        if (imageRatio >= targetRatio * 0.72)
        {
            var availableWidth = BannerPickerDropZone.ActualWidth;
            if (availableWidth <= 0)
            {
                availableWidth = 660;
            }

            var naturalDisplayHeight = availableWidth / imageRatio;
            BannerPickerDropZone.MinHeight = 96;
            BannerPickerDropZone.Height = Math.Clamp(naturalDisplayHeight + 42, 112, 176);
            BannerPickerDropZone.VerticalAlignment = VerticalAlignment.Top;
            return;
        }

        BannerPickerDropZone.Height = double.NaN;
        BannerPickerDropZone.MinHeight = 300;
        BannerPickerDropZone.VerticalAlignment = VerticalAlignment.Stretch;
    }

    private void InitializeBannerPickerCrop()
    {
        if (_bannerPickerSourceImage is null ||
            BannerPickerCropHost.ActualWidth <= 0 ||
            BannerPickerCropHost.ActualHeight <= 0)
        {
            return;
        }

        _bannerPickerImageDisplayRect = CalculateBannerPickerImageDisplayRect();
        if (_bannerPickerImageDisplayRect.IsEmpty ||
            _bannerPickerImageDisplayRect.Width <= 0 ||
            _bannerPickerImageDisplayRect.Height <= 0)
        {
            return;
        }

        var targetRatio = GetFleetBannerCropRatio();
        var maxCropWidth = Math.Min(_bannerPickerImageDisplayRect.Width * 0.92, _bannerPickerImageDisplayRect.Height * targetRatio);
        var maxCropHeight = maxCropWidth / targetRatio;
        if (maxCropHeight > _bannerPickerImageDisplayRect.Height * 0.88)
        {
            maxCropHeight = _bannerPickerImageDisplayRect.Height * 0.88;
            maxCropWidth = maxCropHeight * targetRatio;
        }

        var minScale = GetBannerPickerMinimumCropScale(maxCropWidth, maxCropHeight);
        _bannerPickerCropScale = Math.Clamp(_bannerPickerCropScale, minScale, 1.0);
        UpdateBannerPickerScaleControl(minScale);

        var cropWidth = maxCropWidth * _bannerPickerCropScale;
        var cropHeight = maxCropHeight * _bannerPickerCropScale;
        var centerX = _bannerPickerCropRect.IsEmpty
            ? _bannerPickerImageDisplayRect.X + _bannerPickerImageDisplayRect.Width / 2
            : _bannerPickerCropRect.X + _bannerPickerCropRect.Width / 2;
        var centerY = _bannerPickerCropRect.IsEmpty
            ? _bannerPickerImageDisplayRect.Y + _bannerPickerImageDisplayRect.Height / 2
            : _bannerPickerCropRect.Y + _bannerPickerCropRect.Height / 2;

        var cropX = ClampBannerPickerValue(
            centerX - cropWidth / 2,
            _bannerPickerImageDisplayRect.Left,
            _bannerPickerImageDisplayRect.Right - cropWidth);
        var cropY = ClampBannerPickerValue(
            centerY - cropHeight / 2,
            _bannerPickerImageDisplayRect.Top,
            _bannerPickerImageDisplayRect.Bottom - cropHeight);

        _bannerPickerCropRect = new Rect(cropX, cropY, cropWidth, cropHeight);

        UpdateBannerPickerCropSelection();
        UpdateBannerPickerPreview();
    }

    private static double GetBannerPickerMinimumCropScale(double maxCropWidth, double maxCropHeight)
    {
        if (maxCropWidth <= 0 || maxCropHeight <= 0)
        {
            return FleetBannerPickerMinCropScale;
        }

        var widthScale = Math.Min(1.0, FleetBannerPickerMinCropWidth / maxCropWidth);
        var heightScale = Math.Min(1.0, FleetBannerPickerMinCropHeight / maxCropHeight);
        return Math.Clamp(Math.Max(FleetBannerPickerMinCropScale, Math.Max(widthScale, heightScale)), 0.1, 1.0);
    }

    private void UpdateBannerPickerScaleControl(double minScale)
    {
        _isUpdatingBannerPickerScaleControl = true;
        BannerPickerCropScaleSlider.Minimum = minScale;
        BannerPickerCropScaleSlider.Maximum = 1.0;
        BannerPickerCropScaleSlider.Value = _bannerPickerCropScale;
        BannerPickerCropScaleText.Text = $"{_bannerPickerCropScale * 100:0}%";
        _isUpdatingBannerPickerScaleControl = false;
    }

    private void BannerPickerCropScaleSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isUpdatingBannerPickerScaleControl)
        {
            return;
        }

        _bannerPickerCropScale = Math.Clamp(e.NewValue, BannerPickerCropScaleSlider.Minimum, BannerPickerCropScaleSlider.Maximum);
        BannerPickerCropScaleText.Text = $"{_bannerPickerCropScale * 100:0}%";

        if (_bannerPickerSourceImage is null)
        {
            return;
        }

        InitializeBannerPickerCrop();
        MarkBannerPickerCropChanged();
    }

    private Rect CalculateBannerPickerImageDisplayRect()
    {
        if (_bannerPickerSourceImage is null)
        {
            return Rect.Empty;
        }

        var hostWidth = BannerPickerCropHost.ActualWidth;
        var hostHeight = BannerPickerCropHost.ActualHeight;
        if (hostWidth <= 0 || hostHeight <= 0)
        {
            return Rect.Empty;
        }

        var imageWidth = Math.Max(1, _bannerPickerSourceImage.PixelWidth);
        var imageHeight = Math.Max(1, _bannerPickerSourceImage.PixelHeight);
        var scale = Math.Min(hostWidth / imageWidth, hostHeight / imageHeight);
        var displayWidth = imageWidth * scale;
        var displayHeight = imageHeight * scale;
        return new Rect(
            (hostWidth - displayWidth) / 2,
            (hostHeight - displayHeight) / 2,
            displayWidth,
            displayHeight);
    }

    private void BannerPickerCropSelection_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_bannerPickerSourceImage is null || _bannerPickerCropRect.IsEmpty)
        {
            return;
        }

        _isBannerCropDragging = true;
        _isBannerCropResizing = false;
        _bannerCropResizeHandle = "";
        _bannerCropDragStart = e.GetPosition(BannerPickerCropOverlayCanvas);
        _bannerCropDragStartRect = _bannerPickerCropRect;
        BannerPickerCropSelection.CaptureMouse();
        e.Handled = true;
    }

    private void BannerPickerCropResizeHandle_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_bannerPickerSourceImage is null ||
            _bannerPickerCropRect.IsEmpty ||
            _bannerPickerImageDisplayRect.IsEmpty)
        {
            return;
        }

        _isBannerCropDragging = false;
        _isBannerCropResizing = true;
        _bannerCropResizeStart = e.GetPosition(BannerPickerCropOverlayCanvas);
        _bannerCropResizeStartRect = _bannerPickerCropRect;
        _bannerCropResizeHandle = (sender as FrameworkElement)?.Tag?.ToString() ?? "";
        BannerPickerCropSelection.CaptureMouse();
        e.Handled = true;
    }

    private void BannerPickerCropOverlayCanvas_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        try
        {
            if (_isBannerCropResizing && !_bannerPickerImageDisplayRect.IsEmpty)
            {
                ResizeBannerPickerCrop(e.GetPosition(BannerPickerCropOverlayCanvas));
                return;
            }

            if (!_isBannerCropDragging || _bannerPickerImageDisplayRect.IsEmpty)
            {
                return;
            }

            var position = e.GetPosition(BannerPickerCropOverlayCanvas);
            var nextRect = _bannerCropDragStartRect;
            nextRect.X += position.X - _bannerCropDragStart.X;
            nextRect.Y += position.Y - _bannerCropDragStart.Y;
            nextRect.X = ClampBannerPickerValue(nextRect.X, _bannerPickerImageDisplayRect.Left, _bannerPickerImageDisplayRect.Right - nextRect.Width);
            nextRect.Y = ClampBannerPickerValue(nextRect.Y, _bannerPickerImageDisplayRect.Top, _bannerPickerImageDisplayRect.Bottom - nextRect.Height);

            _bannerPickerCropRect = nextRect;
            UpdateBannerPickerCropSelection();
            UpdateBannerPickerPreview();
            MarkBannerPickerCropChanged();
        }
        catch (Exception exception)
        {
            EndBannerCropDrag();
            App.WriteCrashLog(exception);
            BannerPickerStatusText.Text = "裁剪框状态已恢复，请重新拖动裁剪区域。";
        }
    }

    private void ResizeBannerPickerCrop(System.Windows.Point position)
    {
        if (_bannerCropResizeStartRect.IsEmpty || _bannerPickerImageDisplayRect.IsEmpty)
        {
            return;
        }

        var targetRatio = GetFleetBannerCropRatio();
        var handle = _bannerCropResizeHandle;
        var nextRect = handle switch
        {
            "Left" => ResizeHorizontal(dragLeft: true),
            "Right" => ResizeHorizontal(dragLeft: false),
            "Top" => ResizeVertical(dragTop: true),
            "Bottom" => ResizeVertical(dragTop: false),
            "TopLeft" => ResizeCorner(dragLeft: true, dragTop: true),
            "TopRight" => ResizeCorner(dragLeft: false, dragTop: true),
            "BottomLeft" => ResizeCorner(dragLeft: true, dragTop: false),
            "BottomRight" => ResizeCorner(dragLeft: false, dragTop: false),
            _ => _bannerCropResizeStartRect
        };

        if (nextRect.IsEmpty || nextRect.Width <= 0 || nextRect.Height <= 0)
        {
            return;
        }

        _bannerPickerCropRect = nextRect;

        var scaleBaseWidth = Math.Min(
            _bannerPickerImageDisplayRect.Width,
            _bannerPickerImageDisplayRect.Height * targetRatio);
        if (scaleBaseWidth > 0)
        {
            _bannerPickerCropScale = Math.Clamp(nextRect.Width / scaleBaseWidth, BannerPickerCropScaleSlider.Minimum, 1.0);
            _isUpdatingBannerPickerScaleControl = true;
            BannerPickerCropScaleSlider.Value = _bannerPickerCropScale;
            BannerPickerCropScaleText.Text = $"{_bannerPickerCropScale * 100:0}%";
            _isUpdatingBannerPickerScaleControl = false;
        }

        UpdateBannerPickerCropSelection();
        UpdateBannerPickerPreview();
        MarkBannerPickerCropChanged();

        Rect ResizeHorizontal(bool dragLeft)
        {
            var imageRect = _bannerPickerImageDisplayRect;
            var startRect = _bannerCropResizeStartRect;
            var anchorX = dragLeft ? startRect.Right : startRect.Left;
            var centerY = startRect.Top + startRect.Height / 2;
            var desiredWidth = dragLeft ? anchorX - position.X : position.X - anchorX;
            var maxWidthByX = dragLeft ? anchorX - imageRect.Left : imageRect.Right - anchorX;
            var maxWidthByY = Math.Min(centerY - imageRect.Top, imageRect.Bottom - centerY) * 2 * targetRatio;
            var width = ClampBannerCropWidth(desiredWidth, Math.Min(maxWidthByX, maxWidthByY));
            var height = width / targetRatio;
            return new Rect(dragLeft ? anchorX - width : anchorX, centerY - height / 2, width, height);
        }

        Rect ResizeVertical(bool dragTop)
        {
            var imageRect = _bannerPickerImageDisplayRect;
            var startRect = _bannerCropResizeStartRect;
            var anchorY = dragTop ? startRect.Bottom : startRect.Top;
            var centerX = startRect.Left + startRect.Width / 2;
            var desiredHeight = dragTop ? anchorY - position.Y : position.Y - anchorY;
            var maxHeightByY = dragTop ? anchorY - imageRect.Top : imageRect.Bottom - anchorY;
            var maxHeightByX = Math.Min(centerX - imageRect.Left, imageRect.Right - centerX) * 2 / targetRatio;
            var maxHeight = Math.Min(maxHeightByY, maxHeightByX);
            if (maxHeight <= 0)
            {
                return startRect;
            }

            var minHeight = Math.Min(maxHeight, Math.Max(FleetBannerPickerMinCropHeight, FleetBannerPickerMinCropWidth / targetRatio));
            var height = Math.Clamp(desiredHeight, minHeight, maxHeight);
            var width = height * targetRatio;
            return new Rect(centerX - width / 2, dragTop ? anchorY - height : anchorY, width, height);
        }

        Rect ResizeCorner(bool dragLeft, bool dragTop)
        {
            var imageRect = _bannerPickerImageDisplayRect;
            var startRect = _bannerCropResizeStartRect;
            var anchorX = dragLeft ? startRect.Right : startRect.Left;
            var anchorY = dragTop ? startRect.Bottom : startRect.Top;
            var desiredWidthByX = dragLeft ? anchorX - position.X : position.X - anchorX;
            var desiredWidthByY = (dragTop ? anchorY - position.Y : position.Y - anchorY) * targetRatio;
            var desiredWidth = Math.Max(desiredWidthByX, desiredWidthByY);
            var maxWidthByX = dragLeft ? anchorX - imageRect.Left : imageRect.Right - anchorX;
            var maxWidthByY = (dragTop ? anchorY - imageRect.Top : imageRect.Bottom - anchorY) * targetRatio;
            var width = ClampBannerCropWidth(desiredWidth, Math.Min(maxWidthByX, maxWidthByY));
            var height = width / targetRatio;
            return new Rect(dragLeft ? anchorX - width : anchorX, dragTop ? anchorY - height : anchorY, width, height);
        }

        double ClampBannerCropWidth(double desiredWidth, double maxWidth)
        {
            if (maxWidth <= 0)
            {
                return Math.Max(1, _bannerCropResizeStartRect.Width);
            }

            var minWidth = Math.Min(maxWidth, Math.Max(FleetBannerPickerMinCropWidth, FleetBannerPickerMinCropHeight * targetRatio));
            return Math.Clamp(desiredWidth, minWidth, maxWidth);
        }
    }

    private void BannerPickerCropOverlayCanvas_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        EndBannerCropDrag();
    }

    private void BannerPickerCropOverlayCanvas_MouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        EndBannerCropDrag();
    }

    private void EndBannerCropDrag()
    {
        if (!_isBannerCropDragging && !_isBannerCropResizing)
        {
            return;
        }

        _isBannerCropDragging = false;
        _isBannerCropResizing = false;
        _bannerCropResizeHandle = "";
        BannerPickerCropSelection.ReleaseMouseCapture();
    }

    private void UpdateBannerPickerCropSelection()
    {
        if (_bannerPickerCropRect.IsEmpty)
        {
            BannerPickerCropSelection.Visibility = Visibility.Collapsed;
            return;
        }

        BannerPickerCropSelection.Visibility = Visibility.Visible;
        Canvas.SetLeft(BannerPickerCropSelection, _bannerPickerCropRect.X);
        Canvas.SetTop(BannerPickerCropSelection, _bannerPickerCropRect.Y);
        BannerPickerCropSelection.Width = _bannerPickerCropRect.Width;
        BannerPickerCropSelection.Height = _bannerPickerCropRect.Height;
    }

    private void UpdateBannerPickerPreview()
    {
        var cropped = CreateBannerPickerCroppedBitmap();
        if (cropped is null)
        {
            return;
        }

        _bannerPickerPreviewImage = cropped;
        BannerPickerPreviewImage.Source = cropped;
        BannerPickerPreviewImage.Visibility = Visibility.Visible;
        BannerPickerPreviewScrim.Visibility = Visibility.Visible;
        BannerPickerTopVisibleAreaFrame.Visibility = Visibility.Visible;
        BannerPickerFindFleetPreviewImage.Source = cropped;
        BannerPickerFindFleetPreviewImage.Visibility = Visibility.Visible;
        BannerPickerFindFleetPreviewScrim.Visibility = Visibility.Visible;
        BannerPickerFindFleetVisibleAreaFrame.Visibility = Visibility.Visible;
        BannerPickerProfilePreviewImage.Source = cropped;
        BannerPickerProfilePreviewImage.Visibility = Visibility.Visible;
        BannerPickerProfilePreviewScrim.Visibility = Visibility.Visible;
        BannerPickerProfileVisibleAreaFrame.Visibility = Visibility.Visible;
        BannerPickerPreviewPlaceholder.Visibility = Visibility.Collapsed;
    }

    private void MarkBannerPickerCropChanged()
    {
        if (_bannerPickerSourceImage is null || _bannerPickerPreviewImage is null)
        {
            return;
        }

        BannerPickerApplyButton.IsEnabled = true;
        BannerPickerStatusText.Foreground = FindResource("MutedTextBrush") as System.Windows.Media.Brush ?? new SolidColorBrush(Color.FromRgb(145, 165, 181));
        BannerPickerStatusText.Text = "裁剪区域已调整，可以应用横幅。";
    }

    private CroppedBitmap? CreateBannerPickerCroppedBitmap()
    {
        if (_bannerPickerSourceImage is null ||
            _bannerPickerImageDisplayRect.IsEmpty ||
            _bannerPickerCropRect.IsEmpty)
        {
            return null;
        }

        var cropPixels = GetBannerPickerCropPixelRect();
        if (cropPixels.Width <= 0 || cropPixels.Height <= 0)
        {
            return null;
        }

        try
        {
            var cropped = new CroppedBitmap(_bannerPickerSourceImage, cropPixels);
            cropped.Freeze();
            return cropped;
        }
        catch
        {
            return null;
        }
    }

    private Int32Rect GetBannerPickerCropPixelRect()
    {
        if (_bannerPickerSourceImage is null || _bannerPickerImageDisplayRect.IsEmpty)
        {
            return new Int32Rect(0, 0, 0, 0);
        }

        var scaleX = _bannerPickerSourceImage.PixelWidth / _bannerPickerImageDisplayRect.Width;
        var scaleY = _bannerPickerSourceImage.PixelHeight / _bannerPickerImageDisplayRect.Height;
        var x = (int)Math.Round((_bannerPickerCropRect.X - _bannerPickerImageDisplayRect.X) * scaleX);
        var y = (int)Math.Round((_bannerPickerCropRect.Y - _bannerPickerImageDisplayRect.Y) * scaleY);
        var width = (int)Math.Round(_bannerPickerCropRect.Width * scaleX);
        var height = (int)Math.Round(_bannerPickerCropRect.Height * scaleY);

        x = Math.Clamp(x, 0, _bannerPickerSourceImage.PixelWidth - 1);
        y = Math.Clamp(y, 0, _bannerPickerSourceImage.PixelHeight - 1);
        width = Math.Clamp(width, 1, _bannerPickerSourceImage.PixelWidth - x);
        height = Math.Clamp(height, 1, _bannerPickerSourceImage.PixelHeight - y);
        return new Int32Rect(x, y, width, height);
    }

    private void BannerPickerRestoreDefaultButton_Click(object sender, RoutedEventArgs e)
    {
        ApplyFleetBannerPath(null, null, "舰队横幅已恢复默认，公开舰队展示已恢复默认背景。");
        AppendOutput("Fleet banner restored to default locally.");
        CloseFleetBannerPickerOverlay();
    }

    private void BannerPickerApplyButton_Click(object sender, RoutedEventArgs e)
    {
        var cropped = CreateBannerPickerCroppedBitmap();
        if (cropped is null)
        {
            BannerPickerStatusText.Text = "还没有可保存的裁剪区域。请先选择图片。";
            BannerPickerStatusText.Foreground = new SolidColorBrush(Color.FromRgb(217, 162, 59));
            return;
        }

        var bannerPath = StoreFleetBannerImage(cropped);
        if (bannerPath is null)
        {
            BannerPickerStatusText.Text = "横幅保存失败：无法保存裁剪后的横幅。";
            BannerPickerStatusText.Foreground = new SolidColorBrush(Color.FromRgb(241, 91, 101));
            return;
        }

        var sourcePath = ResolveBannerPickerSourcePathForSave();
        if (sourcePath is null)
        {
            sourcePath = bannerPath;
            AppendOutput("Fleet banner source image was unavailable; using cropped banner as the next edit source.");
        }

        ApplyFleetBannerPath(bannerPath, sourcePath, "舰队横幅已更新，寻找舰队展示将使用该图片。");
        AppendOutput("Fleet banner updated locally.");
        CloseFleetBannerPickerOverlay();
    }

    private string? ResolveBannerPickerSourcePathForSave()
    {
        if (!string.IsNullOrWhiteSpace(_bannerPickerSourcePath))
        {
            if (string.Equals(_bannerPickerSourcePath, _fleetBannerSourcePath, StringComparison.OrdinalIgnoreCase) &&
                File.Exists(_bannerPickerSourcePath))
            {
                return _bannerPickerSourcePath;
            }

            var storedSourcePath = StoreFleetBannerSourceImage(_bannerPickerSourcePath);
            if (!string.IsNullOrWhiteSpace(storedSourcePath))
            {
                return storedSourcePath;
            }

            if (File.Exists(_bannerPickerSourcePath))
            {
                AppendOutput("Fleet banner source cache failed; keeping original source path for future cropping.");
                return _bannerPickerSourcePath;
            }
        }

        if (_bannerPickerSourceImage is not null)
        {
            var storedSourcePath = StoreFleetBannerSourceImage(_bannerPickerSourceImage);
            if (!string.IsNullOrWhiteSpace(storedSourcePath))
            {
                return storedSourcePath;
            }
        }

        if (!string.IsNullOrWhiteSpace(_fleetBannerSourcePath) && File.Exists(_fleetBannerSourcePath))
        {
            return _fleetBannerSourcePath;
        }

        return null;
    }

    private void RemoveFleetBanner_Click(object sender, RoutedEventArgs e)
    {
        SetFleetDescriptionStatus("舰队横幅功能已停用。", ManageProfileStatusTone.Locked);
        AppendOutput("Fleet banner feature is disabled.");
    }

    private void ApplyFleetBannerPath(string? bannerPath, string? bannerSourcePath, string statusText)
    {
        _fleetBannerPath = bannerPath;
        _fleetBannerSourcePath = bannerSourcePath;
        MarkLocalFleetBannerEdit();
        LoadCreateFleetBannerPreview();
        LoadFleetHeaderBannerPreview();
        RefreshManageFleetBasicProfile();
        ApplyFleetSearchFilter();
        SaveCurrentConfig();
        if (FleetDescriptionStatusText is not null)
        {
            SetFleetDescriptionStatus(statusText, ManageProfileStatusTone.Success);
        }

        if (_hasFleet)
        {
            MarkFleetDirectorySyncPending();
            _ = SyncFleetBannerChangeAsync();
        }
    }

    private async Task SyncFleetBannerChangeAsync()
    {
        var hasBanner = !string.IsNullOrWhiteSpace(_fleetBannerPath);
        var pushed = await PushFleetInfoAsync(
            silent: true,
            includeImages: hasBanner,
            requireBannerImage: hasBanner,
            clearBannerImage: !hasBanner,
            scope: FleetInfoUpdateScope.Banner);
        if (pushed)
        {
            await PullNetworkFleetsAsync(silent: true);
            return;
        }

        await PushFleetDirectoryAsync(silent: true);
    }

    private string? StoreFleetBannerImage(string sourcePath)
    {
        try
        {
            if (!TryLoadBitmapImage(sourcePath, out var bitmap) || bitmap is null)
            {
                StarBridgeMessageBox.Show(
                    "无法读取这张横幅图片。请使用 PNG、JPG、BMP，或确认系统支持该 WebP 文件。",
                    "横幅不可用",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                return null;
            }

            return StoreFleetBannerImage(bitmap);
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                UserFacingError.Describe(ex, "横幅图片未能保存，请重新选择图片后重试。"),
                "横幅保存失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            AppendOutput($"Fleet banner save failed: {ex.Message}");
            return null;
        }
    }

    private string? StoreFleetBannerSourceImage(string? sourcePath)
    {
        if (string.IsNullOrWhiteSpace(sourcePath))
        {
            return null;
        }

        try
        {
            if (!TryLoadBitmapImage(sourcePath, out var bitmap) || bitmap is null)
            {
                return null;
            }

            return StoreFleetBannerSourceImage(bitmap);
        }
        catch (Exception ex)
        {
            AppendOutput($"Fleet banner source save failed: {ex.Message}");
            return null;
        }
    }

    private string? StoreFleetBannerSourceImage(BitmapSource bitmap)
    {
        try
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));

            using var memoryStream = new MemoryStream();
            encoder.Save(memoryStream);
            var bytes = memoryStream.ToArray();
            var prefix = BuildLocalImagePrefix("fleet-banner-source.png");
            var hash = Convert.ToHexString(SHA256.HashData(bytes))[..12].ToLowerInvariant();
            var outputPath = BuildUserAssetImagePath(prefix, hash);
            WriteImageFileIfChanged(outputPath, bytes);
            CleanupUserAssetImageVariants(prefix, outputPath);
            return outputPath;
        }
        catch (Exception ex)
        {
            AppendOutput($"Fleet banner source save failed: {ex.Message}");
            return null;
        }
    }

    private string? StoreFleetBannerImage(BitmapSource bitmap)
    {
        try
        {
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(bitmap));

            using var memoryStream = new MemoryStream();
            encoder.Save(memoryStream);
            var bytes = memoryStream.ToArray();
            var prefix = BuildLocalImagePrefix("fleet-banner.png");
            var hash = Convert.ToHexString(SHA256.HashData(bytes))[..12].ToLowerInvariant();
            var outputPath = BuildUserAssetImagePath(prefix, hash);
            WriteImageFileIfChanged(outputPath, bytes);
            CleanupUserAssetImageVariants(prefix, outputPath);
            return outputPath;
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                UserFacingError.Describe(ex, "横幅图片未能保存，请重新选择图片后重试。"),
                "横幅保存失败",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            AppendOutput($"Fleet banner save failed: {ex.Message}");
            return null;
        }
    }

    private void FleetHeaderLogo_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_hasFleet || !CanCurrentUserManageFleetInfo())
        {
            return;
        }

        ChooseFleetLogo_Click(sender, new RoutedEventArgs());
    }

    private void FleetSquadBanner_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (FindVisualParent<System.Windows.Controls.Button>(e.OriginalSource as DependencyObject) is not null)
        {
            return;
        }

        if ((sender as FrameworkElement)?.Tag is not SquadRow squad)
        {
            return;
        }

        _selectedSquad = squad;
        SquadSelectionList.SelectedItem = squad;
        squad.IsExpanded = !squad.IsExpanded;
    }

    private void ChooseSquadEmblem_Click(object sender, RoutedEventArgs e)
    {
        var squad = (sender as FrameworkElement)?.Tag as SquadRow ?? _squads.FirstOrDefault();
        ChooseSquadEmblem(squad);
    }

    private void MySquadEmblem_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        ChooseSquadEmblem(_selectedSquad);
    }

    private void FleetSquadManageButton_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not SquadRow squad ||
            !CanCurrentUserManageSquad(squad))
        {
            return;
        }

        _selectedSquad = squad;
        SquadSelectionList.SelectedItem = squad;
        _editingFleetSquad = squad;
        _fleetSquadEditEmblemPath = squad.EmblemPath;
        FleetSquadManageTitleText.Text = $"管理小队 · {squad.Name}";
        FleetSquadManageDescriptionBox.Text = squad.Description == "No squad briefing yet."
            ? string.Empty
            : squad.Description;
        FleetSquadManageStatusText.Text = string.Empty;
        LoadFleetSquadManageEmblem(squad);
        FleetSquadManageOverlay.Visibility = Visibility.Visible;
        FleetSquadManageDescriptionBox.Focus();
    }

    private void FleetSquadManageCancelButton_Click(object sender, RoutedEventArgs e)
    {
        FleetSquadManageOverlay.Visibility = Visibility.Collapsed;
        _editingFleetSquad = null;
        _fleetSquadEditEmblemPath = null;
    }

    private void FleetSquadManageChooseEmblemButton_Click(object sender, RoutedEventArgs e)
    {
        if (_editingFleetSquad is null)
        {
            return;
        }

        var safeName = string.Concat(_editingFleetSquad.Name.Select(character =>
            Path.GetInvalidFileNameChars().Contains(character) ? '_' : character));
        var croppedPath = ChooseAndCropImage("选择小队徽标", $"squad-{safeName}-emblem.png");
        if (croppedPath is null)
        {
            return;
        }

        _fleetSquadEditEmblemPath = croppedPath;
        LoadFleetSquadManageEmblem(_editingFleetSquad, croppedPath);
    }

    private async void FleetSquadManageSaveButton_Click(object sender, RoutedEventArgs e)
    {
        var squad = _editingFleetSquad;
        if (squad is null || !CanCurrentUserManageSquad(squad))
        {
            FleetSquadManageStatusText.Text = "当前账号无法管理这个小队。";
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        FleetSquadManageSaveButton.IsEnabled = false;
        FleetSquadManageStatusText.Foreground = FindResource("MutedTextBrush") as System.Windows.Media.Brush ?? Brushes.Gray;
        FleetSquadManageStatusText.Text = "正在保存小队资料…";
        try
        {
            squad.Description = string.IsNullOrWhiteSpace(FleetSquadManageDescriptionBox.Text)
                ? "暂无小队介绍"
                : FleetSquadManageDescriptionBox.Text.Trim();
            squad.EmblemPath = _fleetSquadEditEmblemPath;
            MarkLocalSquadEdit(squad);
            squad.RefreshComputed();
            RenderSquads();
            RenderMySquad();
            RefreshPlayerSquadEmblems();
            RefreshOverlayWindow();
            SaveCurrentConfig();

            if (!await PushFleetSquadsAsync(silent: false))
            {
                RestoreFleetStateAfterFailedMutation(rollbackState, "小队资料同步失败，已恢复原有状态。");
                _editingFleetSquad = _squads.FirstOrDefault(item =>
                    item.Name.Equals(squad.Name, StringComparison.OrdinalIgnoreCase));
                if (_editingFleetSquad is not null)
                {
                    _fleetSquadEditEmblemPath = _editingFleetSquad.EmblemPath;
                    FleetSquadManageDescriptionBox.Text = _editingFleetSquad.Description;
                    LoadFleetSquadManageEmblem(_editingFleetSquad);
                }
                FleetSquadManageStatusText.Foreground = FindResource("StatusDangerBrush") as System.Windows.Media.Brush ?? Brushes.IndianRed;
                FleetSquadManageStatusText.Text = "保存失败，已恢复原有小队资料。请稍后重试。";
                return;
            }

            AddFleetLog("小队", "更新小队资料", $"{GetLocalFleetActorDisplayName()} 更新了 {squad.Name}");
            FleetSquadManageOverlay.Visibility = Visibility.Collapsed;
            _editingFleetSquad = null;
            _fleetSquadEditEmblemPath = null;
        }
        finally
        {
            FleetSquadManageSaveButton.IsEnabled = true;
        }
    }

    private void LoadFleetSquadManageEmblem(SquadRow squad, string? emblemPath = null)
    {
        var path = emblemPath ?? squad.EmblemPath;
        FleetSquadManageEmblemText.Text = squad.Icon;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            FleetSquadManageEmblemImage.Source = null;
            FleetSquadManageEmblemText.Visibility = Visibility.Visible;
            return;
        }

        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.UriSource = new Uri(path);
            image.EndInit();
            image.Freeze();
            FleetSquadManageEmblemImage.Source = image;
            FleetSquadManageEmblemText.Visibility = Visibility.Collapsed;
        }
        catch
        {
            FleetSquadManageEmblemImage.Source = null;
            FleetSquadManageEmblemText.Visibility = Visibility.Visible;
        }
    }

    private async void ChooseSquadEmblem(SquadRow? squad)
    {
        if (squad is null)
        {
            return;
        }

        var safeName = string.Concat(squad.Name.Select(character =>
            Path.GetInvalidFileNameChars().Contains(character) ? '_' : character));
        var croppedPath = ChooseAndCropImage("选择小队徽标", $"squad-{safeName}-emblem.png");
        if (croppedPath is null)
        {
            return;
        }

        var rollbackState = CaptureFleetStateForRollback();
        squad.EmblemPath = croppedPath;
        MarkLocalSquadEdit(squad);
        squad.RefreshComputed();
        RenderSquads();
        RenderMySquad();
        RefreshPlayerSquadEmblems();
        RefreshOverlayWindow();
        SaveCurrentConfig();
        if (!await PushFleetSquadsAsync(silent: false))
        {
            RestoreFleetStateAfterFailedMutation(rollbackState, "小队徽章同步失败，已恢复本地小队状态。");
            return;
        }

        AppendOutput($"Squad emblem updated: {squad.Name}");
    }

    private string? ChooseAndCropImage(string title, string fileName, LocalImageStorage storage = LocalImageStorage.Cache)
    {
        var dialog = new OpenFileDialog
        {
            Title = title,
            Filter = "图片文件 (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp|所有文件 (*.*)|*.*",
            CheckFileExists = true
        };

        if (dialog.ShowDialog(this) != true)
        {
            return null;
        }

        var cropWindow = new SquadEmblemCropWindow(dialog.FileName)
        {
            Owner = this
        };

        if (cropWindow.ShowDialog() != true || cropWindow.CroppedImage is null)
        {
            return null;
        }

        byte[] bytes;
        try
        {
            bytes = FleetProfilePayloadBuilder.EncodeSquarePngForSync(
                cropWindow.CroppedImage,
                FleetSyncImageMaxBytes,
                512);
        }
        catch (InvalidOperationException ex)
        {
            StarBridgeMessageBox.Show(
                this,
                UserFacingError.Describe(ex, "图片未能保存，请重新选择后重试。"),
                "图片无法使用",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return null;
        }
        var prefix = BuildLocalImagePrefix(fileName);
        var hash = Convert.ToHexString(SHA256.HashData(bytes))[..12].ToLowerInvariant();
        var outputPath = storage == LocalImageStorage.UserAsset
            ? BuildUserAssetImagePath(prefix, hash)
            : BuildImagePath(prefix, hash);
        WriteImageFileIfChanged(outputPath, bytes);
        if (storage == LocalImageStorage.UserAsset)
        {
            CleanupUserAssetImageVariants(prefix, outputPath);
        }
        else
        {
            CleanupImageVariants(prefix, outputPath);
        }

        return outputPath;
    }

    private void EnsureAvatarStoredAsUserAsset()
    {
        if (string.IsNullOrWhiteSpace(_avatarPath) ||
            IsImageDataValue(_avatarPath) ||
            !File.Exists(_avatarPath) ||
            !IsPathInsideDirectory(_avatarPath, GetLocalImageCacheDirectory()))
        {
            return;
        }

        try
        {
            var bytes = File.ReadAllBytes(_avatarPath);
            if (bytes.Length == 0)
            {
                return;
            }

            var prefix = BuildLocalImagePrefix("player-avatar.png");
            var hash = Convert.ToHexString(SHA256.HashData(bytes))[..12].ToLowerInvariant();
            var outputPath = BuildUserAssetImagePath(prefix, hash);
            WriteImageFileIfChanged(outputPath, bytes);
            CleanupUserAssetImageVariants(prefix, outputPath);
            _avatarPath = outputPath;
            _cachedAvatarImagePath = null;
            _cachedAvatarImageData = null;
            SaveCurrentConfig();
        }
        catch
        {
            // Keep the existing avatar path if migration fails; cache cleanup still protects the current file.
        }
    }

    private static string BuildLocalImagePrefix(string fileName)
    {
        var name = Path.GetFileNameWithoutExtension(fileName);
        var safeName = new string((name ?? "image").Where(character =>
            char.IsLetterOrDigit(character) || character is '-' or '_').ToArray());
        return string.IsNullOrWhiteSpace(safeName) ? "image" : safeName;
    }

    private static T? FindVisualParent<T>(DependencyObject? source)
        where T : DependencyObject
    {
        while (source is not null)
        {
            if (source is T target)
            {
                return target;
            }

            source = VisualTreeHelper.GetParent(source);
        }

        return null;
    }
}
