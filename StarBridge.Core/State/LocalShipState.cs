namespace StarBridge.Core.State;

public sealed class LocalShipState
{
    public string CurrentShipName { get; set; } = "Unknown";

    public string CurrentDrivingShipName { get; set; } = "None";

    public string LastDrivenShipName { get; set; } = "Unknown";

    public string CurrentControlShipName { get; set; } = "None";

    public string ControlSignalStatus { get; set; } = "None";

    public string ControlStationType { get; set; } = "Unknown";

    public DateTimeOffset? LastControlSignalAt { get; set; }

    public string ReportedShipName { get; set; } = "Unknown";

    public string ReportedStationType { get; set; } = "Unknown";

    public string ReportVerification { get; set; } = "Not Reported";

    public bool InShip { get; set; }

    public bool Driving { get; set; }
}
