using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;

// Explicit manual read-only diagnostic, never part of the automatic test suite.
// Uses only the selected active credential; never a migration file or WPF config.
internal static class WpfCommunityContractProbe
{
    internal static async Task<int> Run()
    {
        try
        {
            var origin = new Uri("https://api.scstarbridge.com/");
            var suffix = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(origin.AbsoluteUri)))[..16];
            var store = new WindowsLegacyMigrationCredentialStore(Path.Combine(HostDataRoot.CurrentRoot,
                "legacy-migration-credential.development.dat.active-" + suffix + ".dat"));
            var credential = store.Load();
            if (credential is null) { Console.WriteLine("FAIL|active-legacy-credential-absent"); return 1; }
            using var http = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(15) };
            foreach (var path in new[] { "api/auth/session", "api/fleets/membership", "api/fleets/applications/mine", "api/fleets" })
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(origin, path));
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
                using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
                Console.WriteLine($"HTTP|{path}|{(int)response.StatusCode}");
                if (!response.IsSuccessStatusCode) return 1;
                using var stream = await response.Content.ReadAsStreamAsync();
                using var buffer = new MemoryStream();
                var chunk = new byte[8192];
                int count;
                while ((count = await stream.ReadAsync(chunk)) > 0)
                {
                    if (buffer.Length + count > 8 * 1024 * 1024) throw new InvalidDataException();
                    buffer.Write(chunk, 0, count);
                }
                using var json = JsonDocument.Parse(buffer.ToArray());
                var root = json.RootElement;
                if (path == "api/auth/session")
                {
                    if (root.GetProperty("accountId").GetString() != credential.AccountId) throw new InvalidDataException();
                    Console.WriteLine("PASS|session-owner-matches");
                    Console.WriteLine($"SHAPE|avatar-present={root.TryGetProperty("avatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(avatar.GetString())}");
                    Console.WriteLine($"SHAPE|avatar-supported={avatar.ValueKind == JsonValueKind.String && StarBridge.HostRuntime.PartyRooms.RoomAvatarProjection.Normalize(avatar.GetString(), 512 * 1024) is not null}");
                    if (avatar.ValueKind == JsonValueKind.String)
                    {
                        var raw = avatar.GetString()!.Trim();
                        var comma = raw.IndexOf(',');
                        var bytes = Convert.FromBase64String(comma < 0 ? raw : raw[(comma + 1)..]);
                        var format = bytes.AsSpan().StartsWith(new byte[] {137,80,78,71}) ? "png" :
                            bytes.AsSpan().StartsWith(new byte[] {255,216}) ? "jpeg" :
                            bytes.AsSpan().StartsWith("GIF8"u8) ? "gif" : "other";
                        Console.WriteLine($"SHAPE|avatar|format={format}|bytes={bytes.Length}");
                        if (format == "png" && bytes.Length >= 24)
                            Console.WriteLine($"SHAPE|avatar|width={System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(16,4))}|height={System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(20,4))}");
                    }
                }
                else if (path.EndsWith("membership"))
                    Console.WriteLine($"SHAPE|membership|single={root.TryGetProperty("fleetCode", out _)}|multi={root.TryGetProperty("fleetCodes", out _)}");
                else
                {
                    if (root.ValueKind != JsonValueKind.Array) throw new InvalidDataException();
                    Console.WriteLine($"SHAPE|{path}|array-count={root.GetArrayLength()}");
                    if (path == "api/fleets" && root.GetArrayLength() > 0)
                    {
                        // Fixed known keys and value kinds only, never user-controlled field names/content.
                        foreach (var key in new[] { "name", "code", "members", "memberPermissions", "roleGroups", "ships", "ownerAccount", "profileRevision" })
                            Console.WriteLine($"FIELD|{key}|{(root[0].TryGetProperty(key, out var value) ? value.ValueKind : JsonValueKind.Undefined)}");
                    }
                }
            }
            // Capability read only; never probe a write or fall back to /api/players.
            using (var sharingRequest = new HttpRequestMessage(HttpMethod.Get, new Uri(origin, "api/fleets/hangar-sharing")))
            {
                sharingRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential.AuthToken);
                using var sharingResponse = await http.SendAsync(sharingRequest, HttpCompletionOption.ResponseHeadersRead);
                Console.WriteLine($"HTTP|api/fleets/hangar-sharing|{(int)sharingResponse.StatusCode}");
            }
            // Exercise the actual client adapter with the same restored owner.
            // Fixed counters only: no names, source IDs, media, or raw responses.
            using var communities = new StarBridge.HostRuntime.Communities.CommunityClient(origin);
            var mine = await communities.ReadWpfS2Async(credential.AuthToken, new("mine", "", null, null),
                "explicit-read-probe", credential.AccountId, default);
            Console.WriteLine($"PASS|s2-adapter-membership|count={mine.Items.Length}");
            var recommended = await communities.ReadWpfS2Async(credential.AuthToken, new("discover", "", null, null),
                "explicit-read-probe", credential.AccountId, default);
            if (recommended.Items.Length != Math.Min(20, recommended.TotalCount ?? 0) || recommended.Items.Any(x => x.LogoImageData is not null))
                throw new InvalidDataException();
            var verifiedLogos = 0;
            foreach (var card in recommended.Items.Where(x => x.LogoDeferred))
            {
                using var image = new MemoryStream();
                string? version = null;
                var offset = 0;
                while (true)
                {
                    var body = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = card.TargetRef, kind = "logo", offset, version });
                    var media = JsonSerializer.SerializeToElement(await communities.ReadMediaAsync(credential.AuthToken, body, "explicit-read-probe", default));
                    version ??= media.GetProperty("version").GetString();
                    if (version != media.GetProperty("version").GetString()) throw new InvalidDataException();
                    image.Write(Convert.FromBase64String(media.GetProperty("data").GetString()!));
                    if (media.GetProperty("next").ValueKind == JsonValueKind.Null) break;
                    offset = media.GetProperty("next").GetInt32();
                }
                if (image.Length > 512 * 1024 || Convert.ToHexString(SHA256.HashData(image.ToArray())).ToLowerInvariant() != version)
                    throw new InvalidDataException();
                verifiedLogos++;
            }
            Console.WriteLine($"PASS|recommended-page-and-original-logos|total={recommended.TotalCount}|page={recommended.Items.Length}|verifiedLogos={verifiedLogos}|hasNext={recommended.Next is not null}");
            var directory = await communities.ReadWpfS2Async(credential.AuthToken, new("discover", "", null, null, "{\"sort\":\"name\"}"),
                "explicit-read-probe", credential.AccountId, default);
            Console.WriteLine($"PASS|s2-adapter-discovery|total={directory.TotalCount}|page={directory.Items.Length}|content-suppressed");
            var seenOrganizations = directory.Items.Select(x => x.OrganizationRef).ToHashSet();
            var pages = 1;
            while (directory.Next is { } after)
            {
                if (++pages > 100) throw new InvalidDataException();
                directory = await communities.ReadWpfS2Async(credential.AuthToken, new("discover", "", after, null, "{\"sort\":\"name\"}"),
                    "explicit-read-probe", credential.AccountId, default);
                foreach (var item in directory.Items) if (!seenOrganizations.Add(item.OrganizationRef)) throw new InvalidDataException();
            }
            if (seenOrganizations.Count != directory.TotalCount) throw new InvalidDataException();
            Console.WriteLine($"PASS|s2-adapter-discovery-pagination|pages={pages}|total={seenOrganizations.Count}|content-suppressed");
            var filtered = await communities.ReadWpfS2Async(credential.AuthToken, new("discover", "", null, null, "{\"status\":[\"pending\"]}"),
                "explicit-read-probe", credential.AccountId, default);
            Console.WriteLine($"PASS|s2-adapter-discovery-filter|count={filtered.TotalCount}|content-suppressed");
            foreach (var organization in mine.Items)
            {
                var shipOffset = 0;
                string? shipRevision = null;
                var shipCount = 0;
                do
                {
                    var shipQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef,
                        offset = shipOffset, revision = shipRevision, query = new { text = "", filter = "all", sort = "spec", descending = true, culture = "zh-CN" } });
                    var ships = JsonSerializer.SerializeToElement(await communities.ReadShipsAsync(credential.AuthToken,
                        shipQuery, "explicit-read-probe", () => { }, default));
                    shipRevision ??= ships.GetProperty("revision").GetString();
                    shipCount += ships.GetProperty("ships").GetArrayLength();
                    if (ships.GetProperty("next").ValueKind == JsonValueKind.Null)
                    {
                        if (shipCount != ships.GetProperty("totalCount").GetInt32()) throw new InvalidDataException();
                        break;
                    }
                    shipOffset = ships.GetProperty("next").GetInt32();
                    if (shipOffset > 10000) throw new InvalidDataException();
                } while (true);
                Console.WriteLine($"PASS|s2-adapter-ships|count={shipCount}|content-suppressed");
                var chatQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef, after = 0, before = 0 });
                var chat = JsonSerializer.SerializeToElement(await communities.ReadChatAsync(credential.AuthToken, chatQuery, "explicit-read-probe", () => { }, default));
                Console.WriteLine($"PASS|s2-adapter-chat|page={chat.GetProperty("messages").GetArrayLength()}|hasOlder={chat.GetProperty("hasOlder").GetBoolean()}|content-suppressed");
                var message = chat.GetProperty("messages").EnumerateArray().FirstOrDefault(x => x.GetProperty("hasAvatar").GetBoolean() || x.GetProperty("hasAttachment").GetBoolean());
                if (message.ValueKind != JsonValueKind.Undefined)
                {
                    var detailQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef,
                        messageRef = message.GetProperty("messageRef").GetString(), offset = 0 });
                    await communities.ReadChatDetailAsync(credential.AuthToken, detailQuery, "explicit-read-probe", () => { }, default);
                    Console.WriteLine("PASS|s2-adapter-chat-detail|content-suppressed");
                }
                var announcementQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef, offset = 0 });
                var announcements = JsonSerializer.SerializeToElement(await communities.ReadAnnouncementsAsync(credential.AuthToken, announcementQuery, "explicit-read-probe", () => { }, default));
                Console.WriteLine($"PASS|s2-adapter-announcements|history={announcements.GetProperty("totalHistoryCount").GetInt32()}|hasCurrent={announcements.GetProperty("current").ValueKind != JsonValueKind.Null}|content-suppressed");
                if (announcements.GetProperty("current").ValueKind != JsonValueKind.Null)
                {
                    var detailQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef,
                        announcementRef = announcements.GetProperty("current").GetProperty("announcementRef").GetString(), offset = 0 });
                    await communities.ReadAnnouncementDetailAsync(credential.AuthToken, detailQuery, "explicit-read-probe", () => { }, default);
                    Console.WriteLine("PASS|s2-adapter-announcement-detail|content-suppressed");
                }
                var query = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef, query = "", offset = 0 });
                var workspace = JsonSerializer.SerializeToElement(await communities.ReadWorkspaceAsync(credential.AuthToken, query, "explicit-read-probe", default));
                Console.WriteLine($"PASS|s2-adapter-workspace|total={workspace.GetProperty("totalCount").GetInt32()}|page={workspace.GetProperty("members").GetArrayLength()}");
                var access = workspace.GetProperty("access");
                if (access.GetProperty("canEditProfile").GetBoolean())
                {
                    var roles = JsonSerializer.SerializeToElement(await communities.ReadWpfS2GovernanceAsync(credential.AuthToken,
                        JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef }),
                        "explicit-read-probe", "roles", () => { }, default));
                    Console.WriteLine($"PASS|s2-adapter-roles|count={roles.GetProperty("roles").GetArrayLength()}|content-suppressed");
                }
                if (access.GetProperty("isOwner").GetBoolean())
                {
                    await communities.ReadWpfS2GovernanceAsync(credential.AuthToken,
                        JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef }),
                        "explicit-read-probe", "disband", () => { }, default);
                    Console.WriteLine("PASS|s2-adapter-disband-preview|no-write");
                    var candidate = workspace.GetProperty("members").EnumerateArray().FirstOrDefault(row =>
                        !row.GetProperty("isSelf").GetBoolean() && !row.GetProperty("isOwner").GetBoolean());
                    if (candidate.ValueKind != JsonValueKind.Undefined)
                    {
                        foreach (var kind in new[] { "role", "remove", "transfer", "exit" })
                        {
                            await communities.ReadWpfS2GovernanceAsync(credential.AuthToken,
                                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef,
                                    memberRef = candidate.GetProperty("memberRef").GetString() }),
                                "explicit-read-probe", kind, () => { }, default);
                            Console.WriteLine($"PASS|s2-adapter-{kind}-preview|no-write");
                        }
                    }
                }
                if (access.GetProperty("canViewLogs").GetBoolean())
                {
                    await communities.ReadWpfS2LogsAsync(credential.AuthToken,
                        JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef, type = "All", query = "", offset = 0 }),
                        "explicit-read-probe", () => { }, default);
                    Console.WriteLine("PASS|s2-adapter-logs|content-suppressed");
                }
                foreach (var section in new[] { "applications", "invites" })
                {
                    if (!access.GetProperty(section == "applications" ? "canReviewApplications" : "canCreateInvite").GetBoolean()) continue;
                    await communities.ReadAdmissionsAsync(credential.AuthToken,
                        JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef, section, offset = 0 }),
                        "explicit-read-probe", () => { }, default, wpfS2: true);
                    Console.WriteLine($"PASS|s2-adapter-{section}|content-suppressed");
                }
                if (workspace.GetProperty("hasLogo").GetBoolean())
                {
                    var media = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = organization.TargetRef, kind = "logo", offset = 0 });
                    await communities.ReadMediaAsync(credential.AuthToken, media, "explicit-read-probe", default);
                    Console.WriteLine("PASS|s2-adapter-logo|content-suppressed");
                }
            }
            return 0;
        }
        catch (Exception e)
        {
            // Runtime exception type only; no message, stack, request, credential or user content.
            Console.WriteLine($"FAIL|read-probe|type={e.GetType().Name}|details-suppressed");
            return 1;
        }
    }
}
