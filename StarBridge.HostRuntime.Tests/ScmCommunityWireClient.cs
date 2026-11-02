using System.Text.Json;
using StarBridge.HostRuntime.Communities;

internal static class ScmCommunityWireClient
{
    internal static async Task Run(string address)
    {
        var uri = new Uri(address);
        if (uri.Scheme != "http" || uri.Host != "127.0.0.1" || uri.Port <= 0 || uri.AbsolutePath != "/" ||
            uri.UserInfo.Length != 0 || uri.Query.Length != 0 || uri.Fragment.Length != 0)
            throw new InvalidOperationException("Only the explicit ephemeral loopback fixture is allowed.");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var syntheticImage = await Console.In.ReadLineAsync(deadline.Token)
            ?? throw new InvalidOperationException("Synthetic image input required.");
        var syntheticRoom = await Console.In.ReadLineAsync(deadline.Token)
            ?? throw new InvalidOperationException("Synthetic room input required.");
        using var journalFolder = new SyntheticJournalFolder();
        using var client = new CommunityClient(uri, invitationJournal: new InvitationOutboxJournal(journalFolder.Path));
        const string scope = "synthetic-wire:1", bearer = "invitee";
        var page = await client.ReadAsync(bearer, new("mine", "", null, null), scope, deadline.Token);
        var target = page.Items.Single(x => x.Name == "SCM wire fixture").TargetRef;
        JsonElement Body(object body) => JsonSerializer.SerializeToElement(body);
        var profileTarget = page.Items.Single(x => x.Name == "SCM profile wire fixture").TargetRef;
        var profileWorkspace = Body(await client.ReadWorkspaceAsync(bearer, Body(new { schemaVersion = 1, targetRef = profileTarget,
            query = "", offset = 0 }), scope, deadline.Token));
        if (!profileWorkspace.GetProperty("access").GetProperty("canEditProfile").GetBoolean())
            throw new InvalidOperationException("Actual Host workspace hides authorized profile entry.");
        var profile = Body(await client.ReadProfileAsync(bearer, Body(new { schemaVersion = 1, targetRef = profileTarget }), scope, deadline.Token));
        var profileSave = await client.SaveProfileAsync(bearer, Body(new { schemaVersion = 1, requestId = new string('8', 32),
            editRef = profile.GetProperty("editRef").GetString(), changes = new { name = "SCM renamed wire fixture" } }), scope, () => { }, deadline.Token);
        if (profileSave.Status != "accepted") throw new InvalidOperationException("Actual Host profile save failed: " + profileSave.Error);
        var profileReload = Body(await client.ReadProfileAsync(bearer, Body(new { schemaVersion = 1, targetRef = profileTarget }), scope, deadline.Token));
        if (profileReload.GetProperty("name").GetString() != "SCM renamed wire fixture" || profileReload.GetProperty("profileRevision").GetInt64() != 1)
            throw new InvalidOperationException("Actual Host profile readback did not match saved rename.");
        var detailsSave = await client.SaveProfileAsync(bearer, Body(new { schemaVersion = 1, requestId = new string('6', 32),
            editRef = profileReload.GetProperty("editRef").GetString(), changes = new { description = "Updated synthetic description", language = "en" } }),
            scope, () => { }, deadline.Token);
        if (detailsSave.Status != "accepted") throw new InvalidOperationException("Actual Host profile details save failed: " + detailsSave.Error);
        var detailsRead = Body(await client.ReadProfileAsync(bearer, Body(new { schemaVersion = 1, targetRef = profileTarget }), scope, deadline.Token));
        if (detailsRead.GetProperty("profile").GetProperty("description").GetString() != "Updated synthetic description" ||
            detailsRead.GetProperty("profile").GetProperty("language").GetString() != "en" || detailsRead.GetProperty("profileRevision").GetInt64() != 2)
            throw new InvalidOperationException("Actual Host profile details readback mismatch.");
        Console.WriteLine("PASS actual SCM Host organization profile read, rename receipt and authorized readback");
        var logoSave = await client.SaveProfileAsync(bearer, Body(new { schemaVersion = 1, requestId = new string('b', 32),
            editRef = detailsRead.GetProperty("editRef").GetString(), changes = new { logoImageData = "data:image/png;base64," + syntheticImage } }),
            scope, () => { }, deadline.Token);
        if (logoSave.Status != "accepted") throw new InvalidOperationException("Actual Host organization logo save failed: " + logoSave.Error);
        var logoHead = Body(await client.ReadMediaAsync(bearer, Body(new { schemaVersion = 1, targetRef = profileTarget, kind = "logo", offset = 0 }), scope, deadline.Token));
        var logoTail = Body(await client.ReadMediaAsync(bearer, Body(new { schemaVersion = 1, targetRef = profileTarget, kind = "logo",
            offset = logoHead.GetProperty("next").GetInt32(), version = logoHead.GetProperty("version").GetString() }), scope, deadline.Token));
        var logoBytes = Convert.FromBase64String(logoHead.GetProperty("data").GetString()!).Concat(Convert.FromBase64String(logoTail.GetProperty("data").GetString()!)).ToArray();
        if (!logoBytes.SequenceEqual(Convert.FromBase64String(syntheticImage))) throw new InvalidOperationException("Host organization logo readback differs from saved image.");
        Console.WriteLine("PASS actual SCM Host organization logo save and full chunk readback");
        var invitation = Body(await client.PreviewInviteAsync(bearer, Body(new { schemaVersion = 1, inviteCode = "SCMWIREINVITE" }),
            scope, () => { }, deadline.Token));
        if (invitation.GetProperty("AlreadyMember").GetBoolean()) throw new InvalidOperationException("Invite preview incorrectly joined the account.");
        var acceptBody = Body(new { schemaVersion = 1, requestId = new string('9', 32), previewRef = invitation.GetProperty("PreviewRef").GetString() });
        var accepted = await client.AcceptInviteAsync(bearer, acceptBody, scope, () => { }, deadline.Token);
        var repeated = await client.AcceptInviteAsync(bearer, acceptBody, scope, () => { }, deadline.Token);
        if (accepted.Status != "accepted" || repeated.Status != "accepted")
            throw new InvalidOperationException("Actual Host invitation admission failed: " + accepted.Error);
        Console.WriteLine("PASS actual SCM Host invitation preview, acceptance, membership readback and retry");
        var joinedDirectory = await client.ReadAsync(bearer, new("mine", "", null, null), scope, deadline.Token);
        var invitedTarget = joinedDirectory.Items.Single(row => row.Name == "SCM invitation wire fixture").TargetRef;
        var generation = Body(new { schemaVersion = 1, targetRef = invitedTarget, requestId = new string('7', 32),
            action = "generateInvite", expiresInDays = 7, maxUses = 1 });
        var generatedInvite = await client.ManageAdmissionsAsync(bearer, generation, scope, () => { }, deadline.Token);
        if (generatedInvite.Status != "accepted") throw new InvalidOperationException("Host invitation generation receipt failed: " + generatedInvite.Error);
        Console.WriteLine("PASS actual SCM Host invitation generation receipt");
        var invitationList = Body(await client.ReadAdmissionsAsync(bearer, Body(new { schemaVersion = 1,
            targetRef = invitedTarget, section = "invites", offset = 0 }), scope, () => { }, deadline.Token));
        var ownInvite = invitationList.GetProperty("currentInvite");
        if (!ownInvite.GetProperty("canRevoke").GetBoolean()) throw new InvalidOperationException("Host own invitation revocation not advertised.");
        var revocation = await client.ManageAdmissionsAsync(bearer, Body(new { schemaVersion = 1, targetRef = invitedTarget,
            requestId = new string('8', 32), action = "revokeInvite", entryRef = ownInvite.GetProperty("entryRef").GetString() }), scope, () => { }, deadline.Token);
        if (revocation.Status != "accepted") throw new InvalidOperationException("Host invitation revocation failed: " + revocation.Error);
        Console.WriteLine("PASS actual SCM Host invitation list and explicit revocation");
        var cardGeneration = await client.GenerateInvitationCardAsync(bearer,
            new(invitedTarget, new string('6', 32), DateTimeOffset.UtcNow, 2), scope, () => { }, deadline.Token);
        if (cardGeneration.Status != "accepted" || cardGeneration.Code is null)
            throw new InvalidOperationException("Host card generation failed: " + cardGeneration.Error);
        var card = new StarBridge.Core.Chat.ChatAttachmentContract(StarBridge.Core.Chat.ChatAttachmentKinds.FleetInvitation,
            "Synthetic organization", "Invitation", FleetInviteCode: cardGeneration.Code, ExpiresAt: cardGeneration.ExpiresAt);
        foreach (var channel in new[] { "private", "room" })
        {
            var destination = new InvitationDeliveryTarget(channel, channel == "private" ? "scm-v1:" + new string('f', 64) : syntheticRoom, scope, uri);
            var intent = new InvitationDeliveryIntent(new string(channel == "private" ? '4' : '5', 32), DateTimeOffset.UtcNow, card);
            var unknown = await client.DeliverInvitationCardAsync(bearer, invitedTarget, destination, intent, true, scope, () => { }, deadline.Token);
            if (unknown.Status != "unknown") throw new InvalidOperationException("Unsent Host card should remain unknown.");
            var cardSent = await client.DeliverInvitationCardAsync(bearer, invitedTarget, destination, intent, false, scope, () => { }, deadline.Token);
            var confirmed = await client.DeliverInvitationCardAsync(bearer, invitedTarget, destination, intent, true, scope, () => { }, deadline.Token);
            if (cardSent.Status != "sent" || confirmed.Status != "sent" || cardSent.MessageId != confirmed.MessageId || cardSent.Sequence != confirmed.Sequence)
                throw new InvalidOperationException("Host " + channel + " card receipt failed: " + cardSent.Error + "/" + confirmed.Error);
            Console.WriteLine("PASS actual SCM Host " + channel + " invitation card generation/delivery/confirmation");
        }
        var announcements = Body(await client.ReadAnnouncementsAsync(bearer,
            Body(new { schemaVersion = 1, targetRef = target, offset = 0 }), scope, () => { }, deadline.Token));
        var current = announcements.GetProperty("current");
        if (current.GetProperty("title").GetString() != "Notice 23" || announcements.GetProperty("history").GetArrayLength() != 20 ||
            current.GetProperty("author").GetProperty("memberRef").ValueKind != JsonValueKind.Null)
            throw new InvalidOperationException("Actual server announcement projection did not reach Host correctly.");
        await client.ReadAnnouncementDetailAsync(bearer, Body(new { schemaVersion = 1, targetRef = target,
            announcementRef = current.GetProperty("announcementRef").GetString(), offset = 0 }), scope, () => { }, deadline.Token);
        var chat = Body(await client.ReadChatAsync(bearer, Body(new { schemaVersion = 1, targetRef = target,
            after = 0L, before = 0L }), scope, () => { }, deadline.Token));
        var message = chat.GetProperty("messages").EnumerateArray().Single();
        if (message.GetProperty("text").GetString() != "Synthetic wire message" || !message.GetProperty("isSelf").GetBoolean() ||
            message.GetProperty("senderGameId").GetString() != "" || message.GetProperty("hasAvatar").GetBoolean())
            throw new InvalidOperationException("Actual server chat projection did not reach Host correctly.");
        await client.ReadChatDetailAsync(bearer, Body(new { schemaVersion = 1, targetRef = target,
            messageRef = message.GetProperty("messageRef").GetString(), offset = 0 }), scope, () => { }, deadline.Token);
        var requestId = new string('a', 32);
        var send = Body(new { schemaVersion = 1, targetRef = target, requestId, text = "Synthetic Host send" });
        var receipt = Body(await client.SendChatAsync(bearer, send, scope, () => { }, deadline.Token));
        var duplicate = Body(await client.SendChatAsync(bearer, send, scope, () => { }, deadline.Token));
        if (receipt.GetProperty("status").GetString() != "accepted" || duplicate.GetRawText() != receipt.GetRawText())
            throw new InvalidOperationException("Actual service send receipt or duplicate-intent handling failed: " +
                receipt.GetProperty("status").GetString() + "/" + receipt.GetProperty("error").GetString() + "; duplicate=" +
                duplicate.GetProperty("status").GetString() + "/" + duplicate.GetProperty("error").GetString());
        // A new Host client has no cached receipt: this also exercises server-side
        // idempotency, not just suppression of a repeated click in one process.
        using var replayClient = new CommunityClient(uri);
        var replayPage = await replayClient.ReadAsync(bearer, new("mine", "", null, null), scope, deadline.Token);
        var replayTarget = replayPage.Items.Single(x => x.Name == "SCM wire fixture").TargetRef;
        var replay = Body(await replayClient.SendChatAsync(bearer,
            Body(new { schemaVersion = 1, targetRef = replayTarget, requestId, text = "Synthetic Host send" }),
            scope, () => { }, deadline.Token));
        if (replay.GetProperty("status").GetString() != "accepted" ||
            replay.GetProperty("sequence").GetInt64() != receipt.GetProperty("sequence").GetInt64())
            throw new InvalidOperationException("Actual service did not preserve the receipt across Host clients.");
        var refreshed = Body(await client.ReadChatAsync(bearer, Body(new { schemaVersion = 1, targetRef = target,
            after = 0L, before = 0L }), scope, () => { }, deadline.Token));
        var sent = refreshed.GetProperty("messages").EnumerateArray().Single(x => x.GetProperty("text").GetString() == "Synthetic Host send");
        if (refreshed.GetProperty("messages").GetArrayLength() != 2 || !sent.GetProperty("isSelf").GetBoolean() ||
            sent.GetProperty("localRequestId").GetString() != requestId ||
            sent.GetProperty("sequence").GetInt64() != receipt.GetProperty("sequence").GetInt64())
            throw new InvalidOperationException("Actual send did not reconcile to one self-authored history entry.");
        var readReceipt = Body(await client.MarkChatReadAsync(bearer, Body(new { schemaVersion = 1, targetRef = target,
            messageRef = sent.GetProperty("messageRef").GetString() }), scope, () => { }, deadline.Token));
        if (readReceipt.GetProperty("status").GetString() != "accepted")
            throw new InvalidOperationException("Actual service read-cursor receipt failed.");
        using var ownerClient = new CommunityClient(uri);
        const string ownerScope = "synthetic-owner:1";
        var ownerPage = await ownerClient.ReadAsync("inviter", new("mine", "", null, null), ownerScope, deadline.Token);
        var ownerTarget = ownerPage.Items.Single(x => x.Name == "SCM wire fixture").TargetRef;
        async Task<JsonElement> NoticePage() => Body(await ownerClient.ReadAnnouncementsAsync("inviter",
            Body(new { schemaVersion = 1, targetRef = ownerTarget, offset = 0 }), ownerScope, () => { }, deadline.Token));
        var noticePage = await NoticePage();
        if (!noticePage.GetProperty("canManage").GetBoolean()) throw new InvalidOperationException("Owner announcement controls not enabled.");
        foreach (var action in new[] { "publish", "edit", "withdraw" })
        {
            var announcementRef = action == "publish" ? null : noticePage.GetProperty("current").GetProperty("announcementRef").GetString();
            var body = Body(new { schemaVersion = 1, targetRef = ownerTarget, requestId = new string(action switch { "publish" => 'a', "edit" => 'b', _ => 'c' }, 32),
                action, announcementRef, title = action == "withdraw" ? null : "Host " + action,
                content = action == "withdraw" ? null : "Synthetic Host notice" });
            var write = Body(await ownerClient.ManageAnnouncementsAsync("inviter", body, ownerScope, () => { }, deadline.Token));
            if (write.GetProperty("status").GetString() != "accepted")
                throw new InvalidOperationException("Actual Host announcement " + action + " failed: " + write.GetProperty("error").GetString());
            noticePage = await NoticePage();
            if (action == "withdraw" ? noticePage.GetProperty("current").ValueKind != JsonValueKind.Null
                : noticePage.GetProperty("current").GetProperty("title").GetString() != "Host " + action)
                throw new InvalidOperationException("Actual Host announcement readback did not confirm " + action);
        }
        using var mediaClient = new StarBridge.HostRuntime.Hangar.HangarMediaClient(uri);
        var actor = "scm-v1:" + new string('2', 64);
        var uploaded = await mediaClient.UploadAsync(bearer, actor, new(new string('f', 32), "ANVL_Arrow",
            "Synthetic Arrow", syntheticImage, new string('e', 32)), () => { }, deadline.Token);
        var catalog = await mediaClient.ReadAsync(bearer, actor, () => { }, deadline.Token);
        if (!catalog.Any(x => x.MediaId == uploaded.MediaId)) throw new InvalidOperationException("Host uploaded image missing from own catalog.");
        var sharing = Body(await client.ReadHangarSharingAsync(bearer, Body(new { schemaVersion = 1 }), scope, () => { }, deadline.Token));
        var selection = sharing.GetProperty("options").EnumerateArray().Single(x => x.GetProperty("name").GetString() == "SCM wire fixture").GetProperty("targetRef").GetString();
        var published = await client.SaveHangarSharingAsync(bearer, Body(new { schemaVersion = 1,
            editRef = sharing.GetProperty("editRef").GetString(), selectedRefs = new[] { selection }, inventoryMode = "local", includeImages = true }),
            scope, () => { }, deadline.Token,
            () => [new StarBridge.HostRuntime.Hangar.CommunityPublishedShip(new string('f', 32), "ANVL_Arrow", "Synthetic Arrow", DateTimeOffset.UtcNow.AddDays(-1))],
            (inventory, _) => Task.FromResult(inventory.Select(ship => ship with {
                ImageMediaId = uploaded.MediaId }).ToArray()));
        if (published.Status != "accepted") throw new InvalidOperationException("Actual Host inventory publication failed: " + published.Error);
        var ships = Body(await client.ReadShipsAsync(bearer, Body(new { schemaVersion = 1, targetRef = selection, offset = 0 }), scope, () => { }, deadline.Token));
        if (ships.GetProperty("totalCount").GetInt32() != 1 || !ships.GetProperty("ships")[0].GetProperty("ownerIsSelf").GetBoolean())
            throw new InvalidOperationException("Actual Host shared ship listing failed.");
        if (!ships.GetProperty("ships")[0].GetProperty("hasCustomImage").GetBoolean()) throw new InvalidOperationException("Published image not advertised.");
        var imageRef = ships.GetProperty("ships")[0].GetProperty("shipRef").GetString();
        var imageHead = Body(await client.ReadShipImageAsync(bearer, Body(new { schemaVersion = 1, targetRef = selection, shipRef = imageRef, offset = 0 }), scope, () => { }, deadline.Token));
        var imageTail = Body(await client.ReadShipImageAsync(bearer, Body(new { schemaVersion = 1, targetRef = selection, shipRef = imageRef,
            offset = imageHead.GetProperty("next").GetInt32(), version = imageHead.GetProperty("version").GetString() }), scope, () => { }, deadline.Token));
        var imageBytes = Convert.FromBase64String(imageHead.GetProperty("data").GetString()!).Concat(
            Convert.FromBase64String(imageTail.GetProperty("data").GetString()!)).ToArray();
        if (imageTail.GetProperty("next").ValueKind != JsonValueKind.Null || imageBytes.Length != imageHead.GetProperty("totalBytes").GetInt32() ||
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(imageBytes)).ToLowerInvariant() != imageHead.GetProperty("contentHash").GetString())
            throw new InvalidOperationException("Actual Host image chunks failed checksum.");
        Console.WriteLine("PASS actual SCM Host shared image chunks and checksum");
        var filtered = Body(await client.ReadShipsAsync(bearer, Body(new { schemaVersion = 1, targetRef = selection, offset = 0,
            query = new { text = "", filter = "all", sort = "name", descending = false, culture = "en-US" } }), scope, () => { }, deadline.Token));
        if (filtered.GetProperty("matchedCount").GetInt32() != 1) throw new InvalidOperationException("Actual Host ship query failed.");
        sharing = Body(await client.ReadHangarSharingAsync(bearer, Body(new { schemaVersion = 1 }), scope, () => { }, deadline.Token));
        if (!sharing.GetProperty("options").EnumerateArray().Single(x => x.GetProperty("name").GetString() == "SCM wire fixture").GetProperty("selected").GetBoolean())
            throw new InvalidOperationException("Actual Host publication audience readback failed.");
        var cleared = await client.SaveHangarSharingAsync(bearer, Body(new { schemaVersion = 1,
            editRef = sharing.GetProperty("editRef").GetString(), selectedRefs = Array.Empty<string>(), inventoryMode = "saved" }),
            scope, () => { }, deadline.Token);
        if (cleared.Status != "accepted") throw new InvalidOperationException("Actual Host hangar consent clear failed: " + cleared.Error);
        ships = Body(await client.ReadShipsAsync(bearer, Body(new { schemaVersion = 1, targetRef = selection, offset = 0 }), scope, () => { }, deadline.Token));
        if (ships.GetProperty("totalCount").GetInt32() != 0) throw new InvalidOperationException("Cleared inventory remains visible through Host.");
        await mediaClient.DeleteAsync(bearer, uploaded.MediaId, () => { }, deadline.Token);
        catalog = await mediaClient.ReadAsync(bearer, actor, () => { }, deadline.Token);
        if (catalog.Any(x => x.MediaId == uploaded.MediaId)) throw new InvalidOperationException("Host deleted image remains in own catalog.");
        Console.WriteLine("PASS actual SCM Host media upload, own catalog and deletion");
        Console.WriteLine("PASS actual SCM Host scoped ship listing, query and withdrawal");
        Console.WriteLine("PASS actual SCM Host hangar consent read and explicit clear receipt");
        Console.WriteLine("PASS actual SCM Host inventory publication receipt and audience readback");
        Console.WriteLine("PASS actual SCM C# HTTP -> Host announcement and chat list/detail contract");
        Console.WriteLine("PASS actual SCM Host send -> durable C# history -> Host confirmation and read cursor");
        Console.WriteLine("PASS actual SCM Host announcement publish/edit/withdraw receipts and readback");
        // Respect the real destination rate limits rather than disabling them for the fixture.
        await Task.Delay(850, deadline.Token);
        const string partition = "synthetic-wire-account";
        foreach (var channel in new[] { "private", "room" })
        {
            var operation = new string(channel == "private" ? '1' : '2', 32);
            var destination = new InvitationDeliveryTarget(channel, channel == "private" ? "scm-v1:" + new string('f', 64) : syntheticRoom,
                scope, uri, "Synthetic destination");
            var progress = await client.AdvanceInvitationSendAsync(bearer, partition, operation, invitedTarget, destination,
                1, "advance", scope, () => { }, deadline.Token);
            if (progress.Status != "sent") throw new InvalidOperationException("Host journal workflow failed: " + channel + "/" + progress.Error);
            using var recoveredClient = new CommunityClient(uri, invitationJournal: new InvitationOutboxJournal(journalFolder.Path));
            var saved = await recoveredClient.FindInvitationOperationAsync(partition, operation)
                ?? throw new InvalidOperationException("Host journal did not persist operation.");
            if (saved.Phase != "sent" || saved.Delivery?.Status != "sent") throw new InvalidOperationException("Host durable receipt missing.");
            var rebound = await recoveredClient.RebindInvitationSourceAsync(bearer, saved, scope, () => { }, deadline.Token);
            var recovered = await recoveredClient.AdvanceInvitationSendAsync(bearer, partition, operation, rebound, destination,
                1, "check", scope, () => { }, deadline.Token);
            if (recovered.Status != "sent") throw new InvalidOperationException("Host journal recovery failed.");
            if (await recoveredClient.FindInvitationOperationAsync("different-synthetic-account", operation) is not null)
                throw new InvalidOperationException("Host outbox leaked across account partitions.");
            Console.WriteLine("PASS actual SCM Host " + channel + " full journal workflow, reload and account partition");
        }
    }

    private sealed class SyntheticJournalFolder : IDisposable
    {
        internal string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "starbridge-wire-journal-" + Guid.NewGuid().ToString("N"));
        public void Dispose() { if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true); }
    }
}
