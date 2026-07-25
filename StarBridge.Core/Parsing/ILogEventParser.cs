using StarBridge.Core.Events;

namespace StarBridge.Core.Parsing;

public interface ILogEventParser
{
    FleetEvent? TryParse(string line);
}
