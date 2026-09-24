namespace StarBridge.Core.Fleets;

/// <summary>WPF creation validation, shared without a UI or a second membership authority.</summary>
public static class LegacyFleetCreationRules
{
    public static string NormalizeCode(string? value) => (value ?? "").Trim().ToUpperInvariant();

    // Empty values are valid while editing; ValidateForm enforces required fields on submission.
    public static bool IsNameText(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return true;
        value = value.Trim();
        return value.Length is >= 4 and <= 32 && value.All(character =>
            character is >= 'A' and <= 'Z' or >= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '_' or ' ');
    }

    public static bool IsCodeText(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return true;
        value = NormalizeCode(value);
        return value.Length is >= 3 and <= 10 && value.All(character => character is >= 'A' and <= 'Z' or >= '0' and <= '9');
    }

    public static bool IsTime24(string value) => value.Length == 5 && value[2] == ':' &&
        int.TryParse(value[..2], out var hour) && int.TryParse(value[3..], out var minute) &&
        hour is >= 0 and <= 23 && minute is >= 0 and <= 59;

    public static FleetCreationValidation ValidateForm(string? name, string? code, string? from, string? to,
        int tagCount, int systemCount, bool showRequiredErrors = true)
    {
        name = (name ?? "").Trim();
        code = NormalizeCode(code);
        var nameValid = IsNameText(name);
        var codeValid = IsCodeText(code);
        var timeValid = IsTime24((from ?? "").Trim()) && IsTime24((to ?? "").Trim());
        var error = showRequiredErrors && name.Length == 0 ? FleetCreationError.NameRequired :
            showRequiredErrors && code.Length == 0 ? FleetCreationError.CodeRequired :
            name.Length != 0 && !nameValid ? FleetCreationError.NameInvalid :
            code.Length != 0 && !codeValid ? FleetCreationError.CodeInvalid :
            !timeValid ? FleetCreationError.TimeInvalid :
            tagCount > LegacyFleetTagCatalog.MaxSelection ? FleetCreationError.TooManyTags :
            systemCount == 0 ? FleetCreationError.SystemRequired : FleetCreationError.None;
        return new(error == FleetCreationError.None && name.Length != 0 && code.Length != 0 &&
            nameValid && codeValid && timeValid && tagCount <= LegacyFleetTagCatalog.MaxSelection && systemCount > 0, error);
    }
}

public enum FleetCreationError { None, NameRequired, CodeRequired, NameInvalid, CodeInvalid, TimeInvalid, TooManyTags, SystemRequired }
public sealed record FleetCreationValidation(bool IsValid, FleetCreationError Error);
