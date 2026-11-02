using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

// Live WS events only. REST pages, unread counts and resyncs never enter this source.
// No member/transaction numbers, contact details or raw bodies are retained in the observer.
internal sealed record TradeNotificationEvent(string Key, bool Chat, string? Reference,
    int SubType, string Title, string Item, string Peer, string Text, bool ReceiptReminder = false,
    int Quantity = 0, string Amount = "")
{
    internal static string KeyFor(string source, long id) => source + ":" +
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(id.ToString(System.Globalization.CultureInfo.InvariantCulture))));

    internal static string TextField(JsonElement row, string key) => row.ValueKind == JsonValueKind.Object &&
        row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";

    private static readonly TimeSpan RedactionTimeout = TimeSpan.FromMilliseconds(50);
    private const RegexOptions RedactionOptions = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
    // Chinese labels need no context. Literal uppercase QQ is also a Chinese label;
    // lowercase qq follows the bounded English rule. Other Latin text in Chinese labels
    // is case-insensitive. English labels require both word boundaries and a value cue.
    private static readonly Regex SensitiveChineseLabel = new(
        @"单号|订单号|交易号|交易编号|编号|订单|会员号|会员编号|用户编号|用户ID|联系方式|联系|加我|微信|V信|(?-i:QQ)|Q群|电话|手机|号码|账号|ID\s*号",
        RedactionOptions | RegexOptions.NonBacktracking, RedactionTimeout);
    // A displayed space may come from a tab/newline within a label (e.g. dis cord).
    // Allow it inside labels, retaining word boundaries and the existing value cue;
    // never strip whitespace from the entire English detection text.
    private static readonly Regex SensitiveEnglishLabel = new(
        @"\b(?:" + string.Join("|", new[] { "wechat", "weixin", "wx", "vx", "qq", "telegram", "tg", "discord", "dc",
            "phone", "telephone", "mobile", "contact", "order", "transaction", "line", "whatsapp", "kakao", "skype" }
            .Select(label => string.Join(@"\s*", label.Select(c => c.ToString())))) +
        @")\b(?:\s+[A-Za-z]+\b\.?){0,2}\s*(?:[:：#=]|\d|@)",
        RedactionOptions | RegexOptions.NonBacktracking, RedactionTimeout);
    private static readonly Regex[] SensitiveText = [
        new(@"(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[\p{L}]{2,}|[\p{L}\d.-]+\.(?:com|cn|net|org|xyz|top)\b\S*", RedactionOptions | RegexOptions.NonBacktracking, RedactionTimeout),
        new(@"\d{5,}|(?:\+?\d[\d\s().-]{4,}\d)", RedactionOptions | RegexOptions.NonBacktracking, RedactionTimeout),
    ];
    // A prefix alone is ordinary prose. Require one optional separator and an
    // identifier of at least three characters, including a digit. Internal hyphens
    // are allowed, but both ends must be alphanumeric.
    private static readonly Regex SensitivePrefix = new(
        @"\b(?:TXN|ORD|MEMBER)[-_#: ]?(?<id>[A-Za-z0-9][A-Za-z0-9-]+[A-Za-z0-9])\b",
        RedactionOptions | RegexOptions.NonBacktracking, RedactionTimeout);

    internal static string SafeText(string text, int limit = 200)
    {
        // Empty is the existing request for a localized generic chat body, or omission
        // of a station display field. Never copy a station's raw body to the desktop.
        if (text.Length > 4096 || limit <= 0) return "";
        try {
            // Reordering controls are unsafe even without a recognizable sensitive label.
            if (text.Any(c => c is >= '\u202a' and <= '\u202e' or >= '\u2066' and <= '\u2069')) return "";
            var display = new StringBuilder();
            for (var index = 0; index < text.Length; index++) {
                var c = text[index];
                // Validate the entire source, including characters beyond the display limit.
                // EnumerateRunes alone would silently replace unpaired surrogates.
                if (char.IsHighSurrogate(c)) {
                    if (index + 1 == text.Length || !char.IsLowSurrogate(text[index + 1])) return "";
                    display.Append(c).Append(text[++index]);
                }
                else if (char.IsLowSurrogate(c)) return "";
                else if (char.IsControl(c)) {
                    if (char.IsWhiteSpace(c)) display.Append(' ');
                }
                else display.Append(c);
            }
            var displayText = display.ToString().Trim();
            // Detect on the complete display text, then cut: a value split by the limit
            // (for example a phone number) must not leak its first part.
            if (Sensitive(displayText)) return "";
            if (displayText.Length > limit) {
                // .NET 8 text elements include surrogate pairs, ZWJ sequences and skin tones.
                // Count UTF-16 units, keeping only complete elements within the existing cap.
                var elements = StringInfo.GetTextElementEnumerator(displayText);
                var end = 0;
                while (elements.MoveNext()) {
                    var next = elements.ElementIndex + elements.GetTextElement().Length;
                    if (next > limit) break;
                    end = next;
                }
                displayText = displayText[..end];
                // The cut can create a word boundary the full text lacked ("ORD-1ab中"),
                // so the exact shown text is checked again.
                if (Sensitive(displayText)) return "";
            }
            // Return the exact inspected display text, preserving its emoji and marks.
            if (!displayText.Any(c => !char.IsWhiteSpace(c) && !char.IsPunctuation(c) && c is not ('*' or '…'))) return "";
            return displayText;
        }
        catch (RegexMatchTimeoutException) {
            // Fail closed; never log the exception (it can carry the original input).
            return "";
        }
        catch (ArgumentException) {
            // Invalid UTF-16 cannot be normalized safely. Fail closed without diagnostics.
            return "";
        }
    }

    static bool Sensitive(string displayText)
    {
        var normalized = new StringBuilder();
        foreach (var rune in displayText.Normalize(NormalizationForm.FormKD).EnumerateRunes()) {
            var category = Rune.GetUnicodeCategory(rune);
            // Detection only: strip marks and invisible fillers after decomposition,
            // including supplementary variation selectors, then recompose for all rules.
            if (category is UnicodeCategory.Format or UnicodeCategory.NonSpacingMark or UnicodeCategory.EnclosingMark ||
                rune.Value is 0x034f or 0x115f or 0x1160 or 0x3164 or 0xffa0) continue;
            normalized.Append(rune.ToString());
        }
        var detectionText = normalized.ToString().Normalize(NormalizationForm.FormKC);
        var compactChineseText = new string(detectionText.Where(c => !char.IsWhiteSpace(c)).ToArray());
        return SensitiveChineseLabel.IsMatch(detectionText) || SensitiveChineseLabel.IsMatch(compactChineseText) ||
            SensitiveEnglishLabel.IsMatch(detectionText) ||
            SensitiveText.Any(rule => rule.IsMatch(detectionText)) || SensitivePrefix.Matches(detectionText).Cast<Match>()
                .Any(match => match.Groups["id"].Value.Any(char.IsAsciiDigit));
    }

    internal static TradeNotificationEvent? ChatPush(JsonElement push)
    {
        if (TextField(push, "kind") != "message" || !push.TryGetProperty("message", out var message) ||
            !message.TryGetProperty("mine", out var mine) || mine.ValueKind != JsonValueKind.False ||
            MarketplaceChat.Id(message, "id") is not (> 0) ||
            TextField(push, "ref") is not { Length: 32 } reference || reference.Any(c => !char.IsAsciiHexDigit(c))) return null;
        if (message.TryGetProperty("read", out var read) && read.ValueKind == JsonValueKind.True) return null;
        return new(KeyFor("chat", MarketplaceChat.Id(message, "id")), true, reference, 0, "", "",
            // The trade chat name is the member's verified game handle; show it in full when it is one.
            ChatHandle(TextField(push, "name")),
            SafeText(TextField(message, "content")));
    }

    // AppMessageRespVO.transactionId is a transactionNumber string, never a numeric database id.
    // Validate each candidate before falling back; missing/null/non-string fields are absent.
    internal static string StationTransactionNumber(JsonElement row, JsonElement order, string templateNumber)
    {
        foreach (var number in new[] { TextField(row, "transactionId"), TextField(order, "transactionId"), templateNumber })
            if (number.Length is > 0 and <= 100 && number.All(c => char.IsAsciiLetterOrDigit(c) || c == '-'))
                return number;
        return "";
    }

    // Compatibility with Java OrderTransactionListener templates when transaction fields are
    // absent. Older VOs omit the top-level field; extraData may contain only item quality (or null).
    // Capture named display segments, never copy the body, ratings or contact tail to the desktop.
    internal static (string Item, string Peer, string Number) JavaStationText(JsonElement row, int subType, bool reminder)
    {
        var body = TextField(row, "content");
        if (body.Length > 4096) return ("", "", "");
        var pattern = reminder ? @"^您的订单(?<item>.{1,200}?)已发货超过1小时，" : subType switch {
            1 => @"^用户 (?<peer>.{1,100}?) 申请(?:购买您的|向您出售)(?<item>.{1,200}?)，数量：",
            2 => @"^收购者 (?<peer>.{1,100}?) 已同意您的交易申请(?<item>.{1,200}?)，数量：",
            3 or 10 => @"^订单(?<item>.{1,200}?)已被取消，数量：",
            4 => @"^卖家 (?<peer>.{1,100}?) 已发货(?<item>.{1,200}?)，数量：",
            5 or 9 => @"^(?:买家 (?<peer>.{1,100}?) 已确认收货|您已确认收货)(?<item>.{1,200}?)，数量：",
            6 => @"^用户 (?<peer>.{1,100}?) 对您的订单(?<item>.{1,200})$",
            7 => @"^订单(?<item>.{1,200}?)因(?:买家|卖家) (?<peer>.{1,100}?) 超时未(?:收货|发货)已被系统自动取消，数量：",
            8 => @"^用户 (?<peer>.{1,100}?) 申请与您交换物品：(?<item>.{1,200}?)，交易编号：",
            _ => "(?!)",
        };
        try {
            var match = Regex.Match(body, pattern, RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(50));
            if (!match.Success) return ("", "", "");
            // Only REQUEST/BARTER_REQUEST currently include an explicit number in the Java text.
            // Missing numbers stay missing; do not infer them from order IDs, time or another push.
            var number = subType is 1 or 8 && !reminder
                ? Regex.Match(body, @"，交易编号：(?<number>[A-Za-z0-9-]{1,100})，联系方式：", RegexOptions.CultureInvariant,
                    TimeSpan.FromMilliseconds(50)).Groups["number"].Value : "";
            return (match.Groups["item"].Value, match.Groups["peer"].Value, number);
        }
        catch (RegexMatchTimeoutException) { return ("", "", ""); }
    }

    // Closed set for the native card; unknown subtypes stay a generic update.
    internal string Kind => Chat ? "message" : ReceiptReminder ? "receipt" : SubType switch {
        1 or 8 => "request", 2 => "approved", 4 => "shipped", 5 or 9 => "completed",
        3 or 7 or 10 => "cancelled", 6 => "review", _ => "update",
    };

    // Quantity and total amount only when the whole body is exactly one Java template with the
    // figures in their fixed places. Any second "数量"/"金额" anywhere (item name, contact tail, other
    // punctuation) makes the body ambiguous and no figure is shown. Figures that equal a known
    // identifier as a number are dropped too. Never guessed from free text.
    private const string QuantityPattern = "(?<q>[1-9][0-9]{0,5})";
    private const string AmountPattern = @"(?<a>(?:0|[1-9][0-9]{0,11})(?:\.[0-9]{1,2})?)";
    private const string ContactPattern = @"[^\r\n]{0,200}";
    private static string? FigureTemplate(int subType) => subType switch {
        // Whole body, start to end (\A..\z, single line); the contact text is the only free part.
        1 => @"\A用户 [^，]{1,100}? 申请(?:购买您的|向您出售)[^，]{1,200}?，数量：" + QuantityPattern + "，金额：" + AmountPattern +
            @"，交易编号：[A-Za-z0-9-]{1,100}，联系方式：" + ContactPattern + @"，请及时处理。\z",
        2 => @"\A收购者 [^，]{1,100}? 已同意您的交易申请[^，]{1,200}?，数量：" + QuantityPattern + "，联系方式：" + ContactPattern + @"，请及时发货。\z",
        3 or 10 => @"\A订单[^，]{1,200}?已被取消，数量：" + QuantityPattern + @"。\z",
        4 => @"\A卖家 [^，]{1,100}? 已发货[^，]{1,200}?，数量：" + QuantityPattern + "，联系方式：" + ContactPattern + @"，请注意查收并确认收货。\z",
        5 or 9 => @"\A(?:买家 [^，]{1,100}? 已确认收货|您已确认收货)[^，]{1,200}?，数量：" + QuantityPattern + @"，交易已完成！\z",
        7 => @"\A订单[^，]{1,200}?因(?:买家|卖家) [^，]{1,100}? 超时未(?:收货|发货)已被系统自动取消，数量：" + QuantityPattern + @"，库存已恢复。\z",
        _ => null,
    };

    internal static (int Quantity, string Amount) StationFigures(JsonElement row, int subType, bool reminder,
        IEnumerable<string> knownIdentifiers)
    {
        var body = TextField(row, "content");
        if (reminder || FigureTemplate(subType) is not {} template || body.Length > 4096) return (0, "");
        // Any control, format (zero-width, bidi), line/paragraph separator or surrogate makes the body
        // ambiguous: such text is not a server template and no figure is shown.
        if (body.Any(c => char.GetUnicodeCategory(c) is UnicodeCategory.Control or UnicodeCategory.Format or
            UnicodeCategory.LineSeparator or UnicodeCategory.ParagraphSeparator or UnicodeCategory.Surrogate or
            UnicodeCategory.PrivateUse or UnicodeCategory.OtherNotAssigned)) return (0, "");
        static int Count(string text, string label) => (text.Length - text.Replace(label, "").Length) / label.Length;
        if (Count(body, "数量") != 1 || Count(body, "金额") != (subType == 1 ? 1 : 0)) return (0, "");
        try {
            var match = Regex.Match(body, template, RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(50));
            if (!match.Success) return (0, "");
            // Compare canonical digit strings (leading zeros dropped, any length) so 424242.00, 000007
            // or a very long zero-padded identifier cannot slip past a known identifier.
            static string Canonical(string digits) => digits.TrimStart('0') is { Length: > 0 } d ? d : "0";
            var known = knownIdentifiers.Select(id => new string(id.Where(char.IsAsciiDigit).ToArray()))
                .Where(digits => digits.Length > 0).Select(Canonical).ToHashSet(StringComparer.Ordinal);
            var q = int.Parse(match.Groups["q"].Value, NumberStyles.None, CultureInfo.InvariantCulture);
            var a = match.Groups["a"].Success
                ? decimal.Parse(match.Groups["a"].Value, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture) : 0m;
            var amountKey = a.ToString("0.##", CultureInfo.InvariantCulture);
            return (known.Contains(q.ToString(CultureInfo.InvariantCulture)) ? 0 : q,
                a > 0 && !known.Contains(amountKey) ? a.ToString("#,0.##", CultureInfo.InvariantCulture) : "");
        }
        catch (RegexMatchTimeoutException) { return (0, ""); }
    }

    // A verified RSI handle (user, 10-29): shown in full only when it is handle-shaped — ASCII letters,
    // digits, '_' and '-', 2-60 long, starting with a letter or digit and containing a letter. It is
    // checked on the raw value (no dots, '@', ':' or spaces can pass), not through the free-text
    // contact rules, so ordinary handles such as Pilot12345 are not blanked. Anything else stays masked.
    internal static string ChatHandle(string name)
    {
        var raw = name.Trim();
        try {
            if (Regex.IsMatch(raw, "^(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9][A-Za-z0-9_-]{1,59}$", RegexOptions.CultureInvariant,
                TimeSpan.FromMilliseconds(50))) return raw;
        }
        catch (RegexMatchTimeoutException) { }
        return MarketplaceRecords.Mask(SafeText(name, 100)) ?? "";
    }

    internal string LocalTitle(bool english) => Title.Length != 0 ? Title : ReceiptReminder
        ? english ? "Confirm receipt" : "收货提醒"
        : SubType switch {
            1 => english ? "New purchase request" : "新的购买申请",
            2 => english ? "Trade approved" : "交易申请已同意",
            3 => english ? "Trade cancelled" : "交易已取消",
            4 => english ? "Item shipped" : "对方已发货",
            5 => english ? "Receipt confirmed" : "对方已确认收货",
            6 => english ? "New trade review" : "收到交易评价",
            7 => english ? "Trade timed out" : "交易已超时",
            8 => english ? "New barter request" : "新的物品交换申请",
            9 => english ? "Barter completed" : "物品交换已完成",
            10 => english ? "Barter cancelled" : "物品交换已取消",
            _ => english ? "Trade update" : "交易提醒",
        };
}

internal sealed class TradeNotificationObserver(TimeProvider? time = null)
{
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private BridgeAccountContext? _owner;
    private long _generation, _epoch;
    private readonly HashSet<string> _seen = new(StringComparer.Ordinal);
    internal void Reset() { _owner = null; _seen.Clear(); _epoch++; }

    internal Func<bool>? Observe(BridgeAccountContext owner, long generation, TradeNotificationEvent notice)
    {
        if (_owner != owner || _generation != generation) {
            Reset(); _owner = owner; _generation = generation;
        }
        // Fail closed when the bounded session journal is full. Do not evict keys and replay them.
        if (_seen.Count >= 4096 || !_seen.Add(notice.Key)) return null;
        var epoch = _epoch;
        var started = _time.GetTimestamp();
        return () => epoch == _epoch && _owner == owner && _generation == generation &&
            _time.GetElapsedTime(started) < TimeSpan.FromSeconds(30);
    }
}
