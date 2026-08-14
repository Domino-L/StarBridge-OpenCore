using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using Button = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void InitializeFleetProfileAcceptanceScenarios()
    {
        if (!AcceptanceControlPolicy.IsVisible)
        {
            return;
        }

#if DEBUG
        if (_fleetProfileAcceptanceScenarioButton is not null || ManageProfileHeaderGrid is null)
        {
            return;
        }

        ManageProfileHeaderGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
        ManageProfileHeaderGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });

        _fleetProfileAcceptanceScenarioButton = new Button
        {
            Content = "验收场景",
            Height = 32,
            MinWidth = 110,
            ToolTip = "切换旧版联系方式迁移的本地验收状态",
            Style = (Style)FindResource("SecondaryButton")
        };
        AutomationProperties.SetName(_fleetProfileAcceptanceScenarioButton, "旧版联系方式迁移验收场景");
        _fleetProfileAcceptanceScenarioButton.Click += FleetProfileAcceptanceScenarioButton_Click;
        Grid.SetColumn(_fleetProfileAcceptanceScenarioButton, 7);
        ManageProfileHeaderGrid.Children.Add(_fleetProfileAcceptanceScenarioButton);

        _fleetProfileAcceptanceScenarioPopup = new Popup
        {
            Placement = PlacementMode.Bottom,
            PlacementTarget = _fleetProfileAcceptanceScenarioButton,
            StaysOpen = false,
            AllowsTransparency = true,
            Child = BuildFleetProfileAcceptanceScenarioPanel()
        };
        ManageProfileHeaderGrid.Children.Add(_fleetProfileAcceptanceScenarioPopup);
#endif
    }

#if DEBUG
    private Button? _fleetProfileAcceptanceScenarioButton;
    private Popup? _fleetProfileAcceptanceScenarioPopup;
    private string? _fleetProfileAcceptanceLiveStateJson;
    private bool _fleetProfileAcceptanceLiveEditMode;

    private bool IsFleetProfileAcceptanceMode =>
        !string.IsNullOrWhiteSpace(_fleetProfileAcceptanceLiveStateJson);

    private Border BuildFleetProfileAcceptanceScenarioPanel()
    {
        var panel = new StackPanel();
        var title = new TextBlock
        {
            Text = "旧联系方式迁移",
            FontWeight = FontWeights.SemiBold
        };
        title.SetResourceReference(TextBlock.ForegroundProperty, "BridgeInk");
        title.SetResourceReference(TextBlock.FontFamilyProperty, "BridgeCjkFont");
        title.SetResourceReference(TextBlock.FontSizeProperty, "BridgeFontBody");
        panel.Children.Add(title);

        var description = new TextBlock
        {
            Text = "驱动真实迁移状态与确认按钮；保存只显示结果，不写入本地或服务器。",
            Margin = new Thickness(0, 3, 0, 10),
            TextWrapping = TextWrapping.Wrap
        };
        description.SetResourceReference(TextBlock.ForegroundProperty, "BridgeInk3");
        description.SetResourceReference(TextBlock.FontFamilyProperty, "BridgeCjkFont");
        description.SetResourceReference(TextBlock.FontSizeProperty, "BridgeFontAux");
        panel.Children.Add(description);

        panel.Children.Add(CreateFleetProfileAcceptanceScenarioButton("live", "返回实际数据", true));
        panel.Children.Add(CreateFleetProfileAcceptanceScenarioButton("empty", "Empty · 无联系方式"));
        panel.Children.Add(CreateFleetProfileAcceptanceScenarioButton("public", "Public · 已公开"));
        panel.Children.Add(CreateFleetProfileAcceptanceScenarioButton(
            "legacy-private",
            "LegacyPrivate · 等待确认",
            bottomMargin: 0));

        var border = new Border
        {
            Width = 270,
            Margin = new Thickness(0, 6, 0, 0),
            Padding = new Thickness(12),
            BorderThickness = new Thickness(1),
            Child = panel
        };
        border.SetResourceReference(Border.BackgroundProperty, "BridgePanelRaised");
        border.SetResourceReference(Border.BorderBrushProperty, "BridgeHairline");
        return border;
    }

    private Button CreateFleetProfileAcceptanceScenarioButton(
        string scenario,
        string label,
        bool primary = false,
        double bottomMargin = 4)
    {
        var button = new Button
        {
            Tag = scenario,
            Content = label,
            Height = 30,
            Margin = new Thickness(0, 0, 0, bottomMargin),
            Style = (Style)FindResource(primary ? "PrimaryButton" : "SecondaryButton")
        };
        button.Click += FleetProfileAcceptanceScenarioMenuItem_Click;
        return button;
    }

    private void FleetProfileAcceptanceScenarioButton_Click(object sender, RoutedEventArgs e)
    {
        if (_fleetProfileAcceptanceScenarioPopup is not null)
        {
            _fleetProfileAcceptanceScenarioPopup.IsOpen = !_fleetProfileAcceptanceScenarioPopup.IsOpen;
        }
    }

    private void FleetProfileAcceptanceScenarioMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string scenario })
        {
            return;
        }

        if (_fleetProfileAcceptanceScenarioPopup is not null)
        {
            _fleetProfileAcceptanceScenarioPopup.IsOpen = false;
        }

        ApplyFleetProfileAcceptanceScenario(scenario);
    }

    private void ApplyFleetProfileAcceptanceScenario(string scenario)
    {
        if (scenario == "live")
        {
            RestoreFleetProfileAcceptanceLiveData();
            return;
        }

        if (!IsFleetProfileAcceptanceMode)
        {
            if (_isManageProfileDirty)
            {
                SetFleetDescriptionStatus(
                    "请先保存或放弃当前真实修改，再进入验收场景。",
                    ManageProfileStatusTone.Warning);
                return;
            }

            _fleetProfileAcceptanceLiveStateJson = SerializeFleetState();
            _fleetProfileAcceptanceLiveEditMode = _isManageProfileEditMode;
        }

        _fleetExternalContacts.Clear();
        var isCurrentlyPublished = false;
        if (scenario is "public" or "legacy-private")
        {
            _fleetExternalContacts.Add(new FleetExternalContactRow("QQ", "123456789"));
            isCurrentlyPublished = scenario == "public";
        }

        ApplyLoadedExternalContactPublicationState(isCurrentlyPublished);
        SetManageProfileEditMode(true);
        SetManageProfileDirty(true);
        SetManageProfileSaveBarMessage("验收场景未写入：可直接保存查看决策结果，或返回实际数据。", false);
        SetFleetDescriptionStatus(
            "当前为 Debug 验收场景；所有保存均被本地拦截。",
            ManageProfileStatusTone.Info);
        SetFleetProfileAcceptanceButtonLabel(GetFleetProfileAcceptanceScenarioLabel(scenario));

        if (scenario == "legacy-private")
        {
            ConfirmLegacyPrivateExternalContactsButton?.BringIntoView();
        }
    }

    private bool TryHandleFleetProfileAcceptanceSave()
    {
        if (!IsFleetProfileAcceptanceMode)
        {
            return false;
        }

        NormalizeFleetExternalContactsFromRows();
        var wouldPublish = FleetExternalContactPublication.ResolveOnSave(
            _fleetExternalContactPublicationMode,
            _legacyExternalContactPublicationConfirmed,
            _fleetExternalContacts);
        var result = wouldPublish
            ? "验收结果：保存后会公开这些联系方式；本次未写入本地或服务器。"
            : "验收结果：保存后不会公开这些联系方式；本次未写入本地或服务器。";

        _fleetPublicShowExternalContacts = wouldPublish;
        ApplyLoadedExternalContactPublicationState(wouldPublish);
        SetManageProfileDirty(true);
        SetManageProfileSaveBarMessage(result, false);
        SetFleetDescriptionStatus(result, wouldPublish
            ? ManageProfileStatusTone.Warning
            : ManageProfileStatusTone.Success);
        return true;
    }

    private bool TryHandleFleetProfileAcceptanceReset()
    {
        if (!IsFleetProfileAcceptanceMode)
        {
            return false;
        }

        RestoreFleetProfileAcceptanceLiveData();
        return true;
    }

    private bool TryGetFleetProfileAcceptancePersistenceState(out string state)
    {
        state = _fleetProfileAcceptanceLiveStateJson ?? "";
        return IsFleetProfileAcceptanceMode;
    }

    private bool ShouldSuppressFleetProfileAcceptanceNetworkWrites() =>
        IsFleetProfileAcceptanceMode;

    private void RestoreFleetProfileAcceptanceLiveData()
    {
        if (!IsFleetProfileAcceptanceMode)
        {
            SetFleetProfileAcceptanceButtonLabel(null);
            return;
        }

        var liveState = _fleetProfileAcceptanceLiveStateJson;
        var liveEditMode = _fleetProfileAcceptanceLiveEditMode;
        _fleetProfileAcceptanceLiveStateJson = null;
        ClearManageProfileDraftBaseline();

        LoadFleetState(liveState);
        RefreshFleetViewsAfterRestore();
        ForceRefreshFleetEditorControlsAfterRestore();
        SetManageProfileDirty(false);
        SetManageProfileEditMode(liveEditMode && CanCurrentUserManageFleetInfo());
        SetFleetDescriptionStatus("已返回实际数据；验收场景未写入任何设置。", ManageProfileStatusTone.Success);
        SetFleetProfileAcceptanceButtonLabel(null);
    }

    private void SetFleetProfileAcceptanceButtonLabel(string? label)
    {
        if (_fleetProfileAcceptanceScenarioButton is null)
        {
            return;
        }

        _fleetProfileAcceptanceScenarioButton.Content = string.IsNullOrWhiteSpace(label)
            ? "验收场景"
            : $"场景 · {label}";
    }

    private static string GetFleetProfileAcceptanceScenarioLabel(string scenario) => scenario switch
    {
        "empty" => "Empty",
        "public" => "Public",
        "legacy-private" => "LegacyPrivate",
        _ => "验收"
    };
#endif
}
