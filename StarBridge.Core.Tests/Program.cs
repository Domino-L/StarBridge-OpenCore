using StarBridge.Core.Events;
using StarBridge.Core.Chat;
using StarBridge.Core.Fleets;
using StarBridge.Core.Identity;
using StarBridge.Core.Parsing;
using StarBridge.Core.Presence;
using StarBridge.Core.State;

var tests = new (string Name, Action Test)[]
{
    ("Weak old ship signal does not replace a newer ship channel join", WeakOldShipSignalDoesNotReplaceNewerShipChannelJoin),
    ("Stale exit for previous ship does not clear current ship", StaleExitForPreviousShipDoesNotClearCurrentShip),
    ("Exit for current ship clears current ship", ExitForCurrentShipClearsCurrentShip),
    ("Confirmed immediate-exit vehicles clear ship on control release", ConfirmedImmediateExitVehiclesClearShip),
    ("Unconfirmed vehicles keep ship on control release", UnconfirmedVehiclesKeepShipOnControlRelease),
    ("Medical response notification parses player downed", MedicalResponseNotificationParsesPlayerDowned),
    ("Incapacitated evidence stays internal until death is confirmed", IncapacitatedEvidenceStaysInternalUntilDeathIsConfirmed),
    ("Safe-zone and incapacitated notices emit one downed event", DuplicateDownedNotificationsEmitOnce),
    ("Downed slice does not emit death or respawn", DownedSliceDoesNotEmitDeathOrRespawn),
    ("RemoveIgnore confirms immediate death", RemoveIgnoreConfirmsImmediateDeath),
    ("Local inventory termination confirms death before entity unbind", InventoryTerminationConfirmsDeathBeforeUnbind),
    ("Natural downed notification removal waits for entity unbind", DownedNotificationRemovalWaitsForEntityUnbind),
    ("Non-safe-zone corpse sequence parses death and respawn", NonSafeZoneCorpseSequenceParsesDeathAndRespawn),
    ("Second non-safe-zone corpse sequence parses death and respawn", SecondNonSafeZoneCorpseSequenceParsesDeathAndRespawn),
    ("Recovered hand activity parses player revived", RecoveredHandActivityParsesPlayerRevived),
    ("Unbind without downed context does not parse death", UnbindWithoutDownedContextDoesNotParseDeath),
    ("Respawn sequence parses only after rebind and medical bed", RespawnSequenceParsesOnlyAfterRebindAndMedicalBed),
    ("Respawn completes on client spawn without medical bed notice", RespawnCompletesOnClientSpawnWithoutMedicalBedNotice),
    ("Client spawn alone does not parse respawn", ClientSpawnAloneDoesNotParseRespawn),
    ("Medical bed alone does not parse respawn", MedicalBedAloneDoesNotParseRespawn),
    ("Two sample death cycles parse two deaths and two respawns", TwoSampleDeathCyclesParseTwoDeathsAndTwoRespawns),
    ("Presence becomes away after fifteen inactive minutes", PresenceBecomesAwayAfterFifteenInactiveMinutes),
    ("Running game overrides inactive app presence", RunningGameOverridesInactiveAppPresence),
    ("Presence wire values normalize old and new clients", PresenceWireValuesNormalizeOldAndNewClients),
    ("Invisible presence receives but never publishes realtime state", InvisiblePresenceReceivesWithoutPublishing),
    ("Offline presence disables realtime state in both directions", OfflinePresenceDisablesRealtimeState),
    ("Unconfirmed game identity requires binding", UnconfirmedGameIdentityRequiresBinding),
    ("Confirmed matching game identity allows synchronization", ConfirmedMatchingGameIdentityAllowsSynchronization),
    ("Confirmed mismatched game identity blocks synchronization", ConfirmedMismatchedGameIdentityBlocksSynchronization),
    ("Quantum arrival uses recovered navigation target", QuantumArrivalUsesRecoveredNavigationTarget),
    ("Quantum context follows local player identity change", QuantumContextFollowsLocalPlayerIdentityChange),
    ("Quantum arrival parser retains ship identity", QuantumArrivalParserRetainsShipIdentity),
    ("Quantum arrival and confirmed location preserve current ship", QuantumArrivalAndConfirmedLocationPreserveCurrentShip),
    ("Location inventory outside quantum arrival clears current ship", LocationInventoryOutsideQuantumArrivalClearsCurrentShip),
    ("Quantum arrival ship retention expires before later location inventory", QuantumArrivalShipRetentionExpiresBeforeLaterLocationInventory),
    ("Navigation target never establishes current location", NavigationTargetNeverEstablishesCurrentLocation),
    ("Recent confirmed region wins over quantum arrival", RecentConfirmedRegionWinsOverQuantumArrival),
    ("Recent journey origin yields to beacon arrival", RecentJourneyOriginYieldsToBeaconArrival),
    ("Post-target region confirmation wins over beacon arrival", PostTargetRegionConfirmationWinsOverBeaconArrival),
    ("Old confirmed region yields to quantum arrival", OldConfirmedRegionYieldsToQuantumArrival),
    ("Chat history pager loads newest then older pages without overlap", ChatHistoryPagerLoadsNewestThenOlderPages),
    ("Chat history pager separates live messages from older history", ChatHistoryPagerSeparatesLiveMessagesFromOlderHistory),
    ("Legacy fleet profile managers retain announcement permission once", LegacyFleetProfileManagersRetainAnnouncementPermissionOnce),
    ("Fleet invitation policies default to every member and respect restrictions", FleetInvitationPoliciesRespectRestrictions)
};

var failures = new List<string>();
foreach (var (name, test) in tests)
{
    try
    {
        test();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception ex)
    {
        failures.Add($"{name}: {ex.Message}");
        Console.WriteLine($"FAIL {name}: {ex.Message}");
    }
}

if (failures.Count > 0)
{
    Console.WriteLine();
    Console.WriteLine("Failures:");
    foreach (var failure in failures)
    {
        Console.WriteLine(failure);
    }

    Environment.Exit(1);
}

static void LegacyFleetProfileManagersRetainAnnouncementPermissionOnce()
{
    var legacy = new[] { FleetPermissionPolicy.EditFleetProfile, "members.invite" };
    AssertEqual(
        false,
        FleetPermissionPolicy.UsesAnnouncementPermissionSchema([legacy]),
        "legacy role has no announcement schema marker");

    var migrated = FleetPermissionPolicy.NormalizeRolePermissions(legacy, migrateLegacyProfileManagers: true);
    AssertEqual(true, migrated.Contains(FleetPermissionPolicy.ManageAnnouncements), "legacy manager keeps announcement access");
    AssertEqual(true, migrated.Contains(FleetPermissionPolicy.AnnouncementPermissionSchemaMarker), "migration is marked");
    AssertEqual(false, migrated.Contains(FleetPermissionPolicy.RetiredInviteMembers), "retired invite permission is removed");

    var explicitlyRemoved = FleetPermissionPolicy.NormalizeRolePermissions(
        migrated.Where(id => !id.Equals(FleetPermissionPolicy.ManageAnnouncements, StringComparison.OrdinalIgnoreCase)),
        migrateLegacyProfileManagers: false);
    AssertEqual(false, explicitlyRemoved.Contains(FleetPermissionPolicy.ManageAnnouncements), "explicit removal remains removed");
    AssertEqual(
        true,
        FleetPermissionPolicy.UsesAnnouncementPermissionSchema([explicitlyRemoved]),
        "explicit removal is not mistaken for legacy data");
}

static void FleetInvitationPoliciesRespectRestrictions()
{
    AssertEqual(FleetInvitationAccessPolicy.AllMembers, FleetInvitationAccessPolicy.Normalize(null), "missing policy defaults to every member");
    AssertEqual(true, FleetInvitationAccessPolicy.Allows(null, true, false, false), "ordinary member may invite by default");
    AssertEqual(false, FleetInvitationAccessPolicy.Allows(null, false, false, false), "non-member may not invite");
    AssertEqual(false, FleetInvitationAccessPolicy.Allows(FleetInvitationAccessPolicy.Management, true, false, false), "ordinary member is blocked by management policy");
    AssertEqual(true, FleetInvitationAccessPolicy.Allows(FleetInvitationAccessPolicy.Management, true, false, true), "manager passes management policy");
    AssertEqual(false, FleetInvitationAccessPolicy.Allows(FleetInvitationAccessPolicy.Commander, true, false, true), "manager does not pass commander policy");
    AssertEqual(true, FleetInvitationAccessPolicy.Allows(FleetInvitationAccessPolicy.Commander, true, true, false), "commander passes commander policy");
}

static void QuantumArrivalUsesRecoveredNavigationTarget()
{
    var state = new FleetState();
    var time = DateTimeOffset.Parse("2026-07-19T04:46:19Z");

    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Arrived - awaiting location confirmation",
        Timestamp: time,
        NavigationTarget: "rs_ext_pyro-nyx_jp",
        LocationEvidenceScore: 45,
        LocationEvidence: "Quantum arrival"));

    var player = SinglePlayer(state);
    AssertEqual("rs_ext_pyro-nyx_jp", player.Location, "resolved arrival location");
    AssertEqual("Medium", player.LocationConfidence, "arrival location confidence");
    AssertEqual("Quantum arrival target (unconfirmed)", player.LocationEvidence, "arrival remains provisional without region confirmation");
}

static void QuantumContextFollowsLocalPlayerIdentityChange()
{
    var tracker = new QuantumTravelContextTracker();
    var selectedAt = DateTimeOffset.Parse("2026-07-19T04:42:12Z");
    tracker.Resolve(new FleetEvent(
        FleetEventType.PlayerNavigationTargetChanged,
        "LocalPlayer",
        Ship: "AEGS_Idris_P",
        Timestamp: selectedAt,
        ShipInstanceId: "723200934234",
        NavigationTarget: "rs_ext_pyro-nyx_jp"));

    var arrival = tracker.Resolve(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "pilot_alpha",
        Ship: "AEGS_Idris_P",
        Location: "Arrived - awaiting location confirmation",
        Timestamp: selectedAt.AddMinutes(4),
        ShipInstanceId: "723200934234"));
    AssertEqual("rs_ext_pyro-nyx_jp", arrival.NavigationTarget, "recovered target across player alias");

    var duplicateArrival = tracker.Resolve(arrival with { NavigationTarget = null, Timestamp = selectedAt.AddMinutes(5) });
    AssertEqual<string?>(null, duplicateArrival.NavigationTarget, "arrival consumes the active target");
}

static void QuantumArrivalParserRetainsShipIdentity()
{
    var parser = new RegexLogEventParser();
    var parsed = parser.TryParse("<2026-07-19T04:46:19.586Z> [Notice] <Quantum Drive Arrived - Arrived at Final Destination> [ItemNavigation][CL][6472] | NOT AUTH | AEGS_Idris_P_723200934234[723200934234]|CSCItemNavigation::OnQuantumDriveArrived|Quantum Drive has arrived at final destination [Team_CGP4][QuantumTravel]");

    AssertEqual(FleetEventType.PlayerLocationChanged, parsed?.Type, "arrival event type");
    AssertEqual("AEGS_Idris_P", parsed?.Ship, "arrival ship");
    AssertEqual("723200934234", parsed?.ShipInstanceId, "arrival ship instance");

    var legacyShape = parser.TryParse("<2026-07-19T04:46:19.586Z> <Quantum Drive Arrived - Arrived at Final Destination> CSCItemNavigation::OnQuantumDriveArrived");
    AssertEqual(FleetEventType.PlayerLocationChanged, legacyShape?.Type, "arrival fallback event type");
}

static void QuantumArrivalAndConfirmedLocationPreserveCurrentShip()
{
    var parser = NewParserWithLocalPlayer();
    var state = new FleetState();
    var enteredAt = DateTimeOffset.Parse("2026-07-24T00:40:00Z");
    state.Apply(new FleetEvent(
        FleetEventType.PlayerEnteredShip,
        "pilot_alpha",
        Ship: "ANVL_Arrow",
        Timestamp: enteredAt));

    var quantumArrivalEvent = parser.TryParse(
        "<2026-07-24T00:40:05.000Z> [Notice] <Quantum Drive Arrived - Arrived at Final Destination> [ItemNavigation][CL][6472] | NOT AUTH | ANVL_Arrow_723200934234[723200934234]|CSCItemNavigation::OnQuantumDriveArrived|Quantum Drive has arrived at final destination [Team_CGP4][QuantumTravel]");
    if (quantumArrivalEvent is null)
    {
        throw new InvalidOperationException("Quantum arrival event was not parsed.");
    }

    AssertEqual("LocalPlayer", quantumArrivalEvent.Player, "quantum arrival uses the local-player alias");
    state.Apply(quantumArrivalEvent with { Player = "pilot_alpha" });
    AssertEqual("ANVL_Arrow", SinglePlayer(state).Ship, "current ship survives quantum arrival");

    var locationEvent = parser.TryParse(
        "<2026-07-24T00:40:06.000Z> [Notice] <RequestLocationInventory> Player[pilot_alpha] requested inventory for Location[Stanton4_NewBabbage]");
    if (locationEvent is null)
    {
        throw new InvalidOperationException("Confirmed location event was not parsed.");
    }

    state.Apply(locationEvent);

    var player = SinglePlayer(state);
    AssertEqual("Stanton4_NewBabbage", player.Location, "confirmed location");
    AssertEqual("ANVL_Arrow", player.Ship, "current ship survives location arrival");
    AssertEqual("High", player.ShipConfidence, "ship confidence survives location arrival");
}

static void LocationInventoryOutsideQuantumArrivalClearsCurrentShip()
{
    var parser = new RegexLogEventParser();
    var state = new FleetState();
    var enteredAt = DateTimeOffset.Parse("2026-07-24T00:50:00Z");
    state.Apply(new FleetEvent(
        FleetEventType.PlayerEnteredShip,
        "Pilot",
        Ship: "ANVL_Arrow",
        Timestamp: enteredAt));

    var locationEvent = parser.TryParse(
        "<2026-07-24T00:55:00.000Z> [Notice] <RequestLocationInventory> Player[Pilot] requested inventory for Location[Stanton4_NewBabbage]");
    if (locationEvent is null)
    {
        throw new InvalidOperationException("Location inventory event was not parsed.");
    }

    state.Apply(locationEvent);

    var player = SinglePlayer(state);
    AssertEqual("Stanton4_NewBabbage", player.Location, "location inventory updates location");
    AssertEqual("Unknown", player.Ship, "location inventory clears current ship");
    AssertEqual("None", player.ShipConfidence, "location inventory clears ship confidence");
}

static void QuantumArrivalShipRetentionExpiresBeforeLaterLocationInventory()
{
    var state = new FleetState();
    var enteredAt = DateTimeOffset.Parse("2026-07-24T01:00:00Z");
    state.Apply(new FleetEvent(
        FleetEventType.PlayerEnteredShip,
        "Pilot",
        Ship: "ANVL_Arrow",
        Timestamp: enteredAt));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Arrived - awaiting location confirmation",
        Timestamp: enteredAt.AddSeconds(5),
        LocationEvidenceScore: 45,
        LocationEvidence: "Quantum arrival"));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Stanton4_NewBabbage",
        Timestamp: enteredAt.AddSeconds(21),
        LocationEvidenceScore: 95,
        LocationEvidence: "Location inventory context"));

    var player = SinglePlayer(state);
    AssertEqual("Unknown", player.Ship, "later location inventory clears ship after quantum grace period");
    AssertEqual("Stanton4_NewBabbage", player.Location, "later location inventory still updates location");
}

static void NavigationTargetNeverEstablishesCurrentLocation()
{
    var state = new FleetState();
    var time = DateTimeOffset.Parse("2026-07-19T05:00:00Z");

    state.Apply(new FleetEvent(
        FleetEventType.PlayerNavigationTargetChanged,
        "Pilot",
        Location: "Checkmate",
        Timestamp: time,
        NavigationTarget: "rs_ext_pyro-nyx_jp",
        LocationEvidenceScore: 45,
        LocationEvidence: "Quantum route start location"));

    var player = SinglePlayer(state);
    AssertEqual("Unknown", player.Location, "navigation does not establish current location");
    AssertEqual("rs_ext_pyro-nyx_jp", player.NavigationTarget, "navigation target is retained");
}

static void RecentConfirmedRegionWinsOverQuantumArrival()
{
    var state = new FleetState();
    var confirmedAt = DateTimeOffset.Parse("2026-07-19T05:10:00Z");
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "RR_P2_L4",
        Timestamp: confirmedAt,
        LocationEvidenceScore: 95,
        LocationEvidence: "Location inventory context"));

    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Arrived - awaiting location confirmation",
        Timestamp: confirmedAt.AddSeconds(5),
        NavigationTarget: "rs_ext_pyro2_l4",
        LocationEvidenceScore: 45,
        LocationEvidence: "Quantum arrival"));

    var player = SinglePlayer(state);
    AssertEqual("RR_P2_L4", player.Location, "recent confirmed region");
    AssertEqual("Location inventory context", player.LocationEvidence, "confirmed evidence remains authoritative");
}

static void OldConfirmedRegionYieldsToQuantumArrival()
{
    var state = new FleetState();
    var confirmedAt = DateTimeOffset.Parse("2026-07-19T05:10:00Z");
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "RR_P2_L4",
        Timestamp: confirmedAt,
        LocationEvidenceScore: 95,
        LocationEvidence: "Location inventory context"));

    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Arrived - awaiting location confirmation",
        Timestamp: confirmedAt.AddSeconds(16),
        NavigationTarget: "rs_ext_pyro2_l4",
        LocationEvidenceScore: 45,
        LocationEvidence: "Quantum arrival"));

    var player = SinglePlayer(state);
    AssertEqual("rs_ext_pyro2_l4", player.Location, "quantum target after protection window");
    AssertEqual("Medium", player.LocationConfidence, "unconfirmed quantum target confidence");
    AssertEqual("Quantum arrival target (unconfirmed)", player.LocationEvidence, "quantum evidence replaces stale confirmation provisionally");
}

static void RecentJourneyOriginYieldsToBeaconArrival()
{
    var state = new FleetState();
    var confirmedAt = DateTimeOffset.Parse("2026-07-19T05:10:00Z");
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "RR_P2_L4",
        Timestamp: confirmedAt,
        LocationEvidenceScore: 95,
        LocationEvidence: "Location inventory context"));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerNavigationTargetChanged,
        "Pilot",
        Timestamp: confirmedAt.AddSeconds(1),
        NavigationTarget: "MISSION_QT_BEACON_720566824111"));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "RR_P2_L4",
        Timestamp: confirmedAt.AddSeconds(2),
        LocationEvidenceScore: 95,
        LocationEvidence: "Location inventory context"));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Arrived - awaiting location confirmation",
        Timestamp: confirmedAt.AddSeconds(5),
        LocationEvidenceScore: 45,
        LocationEvidence: "Quantum arrival"));

    var player = SinglePlayer(state);
    AssertEqual("MISSION_QT_BEACON_720566824111", player.Location, "beacon arrival replaces the journey origin provisionally");
    AssertEqual("Medium", player.LocationConfidence, "beacon arrival remains provisional");
}

static void PostTargetRegionConfirmationWinsOverBeaconArrival()
{
    var state = new FleetState();
    var confirmedAt = DateTimeOffset.Parse("2026-07-19T05:10:00Z");
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "RR_P2_L4",
        Timestamp: confirmedAt,
        LocationEvidenceScore: 95,
        LocationEvidence: "Location inventory context"));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerNavigationTargetChanged,
        "Pilot",
        Timestamp: confirmedAt.AddSeconds(1),
        NavigationTarget: "MISSION_QT_BEACON_720566824111"));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Stanton4_NewBabbage",
        Timestamp: confirmedAt.AddSeconds(4),
        LocationEvidenceScore: 95,
        LocationEvidence: "Location inventory context"));
    state.Apply(new FleetEvent(
        FleetEventType.PlayerLocationChanged,
        "Pilot",
        Location: "Arrived - awaiting location confirmation",
        Timestamp: confirmedAt.AddSeconds(5),
        LocationEvidenceScore: 45,
        LocationEvidence: "Quantum arrival"));

    var player = SinglePlayer(state);
    AssertEqual("Stanton4_NewBabbage", player.Location, "post-target region confirmation remains authoritative");
    AssertEqual("High", player.LocationConfidence, "confirmed region confidence");
}

static void WeakOldShipSignalDoesNotReplaceNewerShipChannelJoin()
{
    var state = new FleetState();
    var time = DateTimeOffset.Parse("2026-07-07T20:00:00Z");

    state.Apply(new FleetEvent(FleetEventType.PlayerEnteredShip, "Pilot", Ship: "AEGS_Sabre", Timestamp: time));
    state.Apply(new FleetEvent(FleetEventType.PlayerEnteredShip, "Pilot", Ship: "ANVL_Arrow", Timestamp: time.AddSeconds(10)));
    state.Apply(new FleetEvent(FleetEventType.PlayerShipControlSignal, "Pilot", Ship: "AEGS_Sabre", Timestamp: time.AddSeconds(20)));

    var player = SinglePlayer(state);
    AssertEqual("ANVL_Arrow", player.Ship, "current ship");
    AssertEqual("High", player.ShipConfidence, "ship confidence");
}

static void StaleExitForPreviousShipDoesNotClearCurrentShip()
{
    var state = new FleetState();
    var time = DateTimeOffset.Parse("2026-07-07T20:00:00Z");

    state.Apply(new FleetEvent(FleetEventType.PlayerEnteredShip, "Pilot", Ship: "AEGS_Sabre", Timestamp: time));
    state.Apply(new FleetEvent(FleetEventType.PlayerEnteredShip, "Pilot", Ship: "ANVL_Arrow", Timestamp: time.AddSeconds(10)));
    state.Apply(new FleetEvent(FleetEventType.PlayerExitedShip, "Pilot", Ship: "AEGS_Sabre", Timestamp: time.AddSeconds(20)));

    var player = SinglePlayer(state);
    AssertEqual("ANVL_Arrow", player.Ship, "current ship");
    AssertEqual("High", player.ShipConfidence, "ship confidence");
}

static void ExitForCurrentShipClearsCurrentShip()
{
    var state = new FleetState();
    var time = DateTimeOffset.Parse("2026-07-07T20:00:00Z");

    state.Apply(new FleetEvent(FleetEventType.PlayerEnteredShip, "Pilot", Ship: "ANVL_Arrow", Timestamp: time));
    state.Apply(new FleetEvent(FleetEventType.PlayerExitedShip, "Pilot", Ship: "ANVL_Arrow", Timestamp: time.AddSeconds(10)));

    var player = SinglePlayer(state);
    AssertEqual("Unknown", player.Ship, "current ship");
    AssertEqual("None", player.ShipConfidence, "ship confidence");
}

static void ConfirmedImmediateExitVehiclesClearShip()
{
    var time = DateTimeOffset.Parse("2026-07-07T20:00:00Z");
    var confirmedVehicleCodes = new[]
    {
        "ANVL_Arrow",
        "CRUS_Starfighter_Inferno",
        "CRUS_Starfighter_Ion",
        "RSI_Scorpius",
        "RSI_Scorpius_Antares",
        "ANVL_Hornet_F7CM",
        "ANVL_Hornet_F7CM_Heartseeker_Mk2",
        "RSI_Aurora_MR",
        "CNOU_Mustang_Delta",
        "AEGS_Sabre_Firebird",
        "ANVL_Hurricane",
        "XIAN_Scout",
        "ARGO_ATLS_GEO",
        "TMBL_Cyclone_TR",
        "DRAK_Dragonfly_Yellow",
        "GRIN_ROC_DS"
    };

    foreach (var vehicleCode in confirmedVehicleCodes)
    {
        var state = new FleetState();
        state.Apply(new FleetEvent(FleetEventType.PlayerControllingShip, "Pilot", Ship: vehicleCode, Timestamp: time));
        state.Apply(new FleetEvent(FleetEventType.PlayerStoppedDrivingShip, "Pilot", Ship: vehicleCode, Timestamp: time.AddSeconds(10)));

        var player = SinglePlayer(state);
        AssertEqual("Unknown", player.Ship, $"{vehicleCode} current ship");
        AssertEqual("None", player.ShipConfidence, $"{vehicleCode} ship confidence");
    }
}

static void UnconfirmedVehiclesKeepShipOnControlRelease()
{
    var time = DateTimeOffset.Parse("2026-07-07T20:00:00Z");
    var unconfirmedVehicleCodes = new[]
    {
        "DRAK_Cutlass_Black",
        "AEGS_Avenger_Titan",
        "RSI_Aurora_Mk2",
        "CNOU_Mustang_Beta",
        "ESPR_Blade",
        "ESPR_Stinger"
    };

    foreach (var vehicleCode in unconfirmedVehicleCodes)
    {
        var state = new FleetState();
        state.Apply(new FleetEvent(FleetEventType.PlayerControllingShip, "Pilot", Ship: vehicleCode, Timestamp: time));
        state.Apply(new FleetEvent(FleetEventType.PlayerStoppedDrivingShip, "Pilot", Ship: vehicleCode, Timestamp: time.AddSeconds(10)));

        var player = SinglePlayer(state);
        AssertEqual(vehicleCode, player.Ship, $"{vehicleCode} current ship");
        AssertEqual(true, player.LastControlSeatLeftAt is not null, $"{vehicleCode} control-seat release timestamp");
    }
}

static void MedicalResponseNotificationParsesPlayerDowned()
{
    var parser = NewParserWithLocalPlayer();
    var fleetEvent = parser.TryParse(
        """<2026-07-15T04:54:52.099Z> [Notice] <SHUDEvent_OnNotification> Added notification "请等待，本地急救人员正在赶来的路上。: " [4] to queue.""");

    AssertEqual(FleetEventType.PlayerDowned, fleetEvent?.Type, "event type");
    AssertEqual("LocalPlayer", fleetEvent?.Player, "event player");
}

static void IncapacitatedEvidenceStaysInternalUntilDeathIsConfirmed()
{
    var parser = NewParserWithLocalPlayer();
    var downedEvent = parser.TryParse(
        "<2026-07-23T23:23:15.380Z> [Notice] <SHUDEvent_OnNotification> Added notification \"\u4E27\u5931\u884C\u52A8\u80FD\u529B: \u5F53\u4F60\u5931\u53BB\u884C\u52A8\u80FD\u529B\u65F6\uFF0C\u5728\u201C\u6B7B\u4EA1\u65F6\u95F4\u201D\u8BA1\u65F6\u5668\u7ED3\u675F\u524D\uFF0C\u901A\u8FC7\u4F60\u7684\u961F\u53CB\u8BA9\u4F60\u82CF\u9192\u3002\" [31] to queue.");
    var deathEvent = parser.TryParse(
        "<2026-07-23T23:23:38.720Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=729382953449");

    AssertEqual<FleetEvent?>(null, downedEvent, "non-safe-zone downed event");
    AssertEqual(FleetEventType.PlayerDied, deathEvent?.Type, "confirmed death event");
}

static void DuplicateDownedNotificationsEmitOnce()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-23T23:23:15.365Z> [Notice] <SHUDEvent_OnNotification> Added notification \"\u4E27\u5931\u884C\u52A8\u80FD\u529B: \u5F53\u4F60\u5931\u53BB\u884C\u52A8\u80FD\u529B\u65F6\uFF0C\u5728\u201C\u6B7B\u4EA1\u65F6\u95F4\u201D\u8BA1\u65F6\u5668\u7ED3\u675F\u524D\uFF0C\u901A\u8FC7\u4F60\u7684\u961F\u53CB\u8BA9\u4F60\u82CF\u9192\u3002\" [31] to queue.",
        "<2026-07-23T23:23:15.380Z> [Notice] <SHUDEvent_OnNotification> Added notification \"\u8BF7\u7B49\u5F85\uFF0C\u672C\u5730\u6025\u6551\u4EBA\u5458\u6B63\u5728\u8D76\u6765\u7684\u8DEF\u4E0A\u3002: \" [30] to queue."
    ]);

    AssertEqual(1, events.Count, "downed event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "event type");
    AssertEqual(LifeEventContext.SafeZoneMedicalResponse, events[0].LifeContext, "first evidence context");
}

static void DownedSliceDoesNotEmitDeathOrRespawn()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-15T05:49:11.013Z> [Notice] <SHUDEvent_OnNotification> Added notification \"请等待，本地急救人员正在赶来的路上。: \" [44] to queue.",
        "<2026-07-15T05:49:14.038Z> [Notice] <Stream started> Result: OK(0)",
        "<2026-07-15T05:49:21.515Z> [Notice] <CSCLoadingPlatformManager::OnLoadingPlatformStateChanged> Platform state changed to ObstructedAtLoadingPlatformLower"
    ]);

    AssertEqual(1, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "only event");
}

static void InventoryTerminationConfirmsDeathBeforeUnbind()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-23T23:41:35.643Z> [Notice] <SHUDEvent_OnNotification> Added notification \"\u8BF7\u7B49\u5F85\uFF0C\u672C\u5730\u6025\u6551\u4EBA\u5458\u6B63\u5728\u8D76\u6765\u7684\u8DEF\u4E0A\u3002: \" [57] to queue.",
        "<2026-07-23T23:41:40.646Z> [Notice] <UpdateNotificationItem> Notification \"\u8BF7\u7B49\u5F85\uFF0C\u672C\u5730\u6025\u6551\u4EBA\u5458\u6B63\u5728\u8D76\u6765\u7684\u8DEF\u4E0A\u3002: \" [57], Action: Remove",
        "<2026-07-23T23:41:43.927Z> [Notice] <Inventory Terminate Location Container> Player[pilot_alpha] removing location [204721330404:Location:141810852] from cache",
        "<2026-07-23T23:41:53.980Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=729382953449"
    ]);

    AssertEqual(2, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "downed event");
    AssertEqual(FleetEventType.PlayerDied, events[1].Type, "death event");
    AssertEqual(DateTimeOffset.Parse("2026-07-23T23:41:43.927Z"), events[1].Timestamp, "early death timestamp");
}

static void RemoveIgnoreConfirmsImmediateDeath()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-23T23:41:35.643Z> [Notice] <SHUDEvent_OnNotification> Added notification \"\u8BF7\u7B49\u5F85\uFF0C\u672C\u5730\u6025\u6551\u4EBA\u5458\u6B63\u5728\u8D76\u6765\u7684\u8DEF\u4E0A\u3002: \" [57] to queue.",
        "<2026-07-23T23:41:35.646Z> [Notice] <UpdateNotificationItem> Notification \"\u8BF7\u7B49\u5F85\uFF0C\u672C\u5730\u6025\u6551\u4EBA\u5458\u6B63\u5728\u8D76\u6765\u7684\u8DEF\u4E0A\u3002: \" [57], Action: RemoveIgnore",
        "<2026-07-23T23:41:53.980Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=729382953449"
    ]);

    AssertEqual(2, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "downed event");
    AssertEqual(FleetEventType.PlayerDied, events[1].Type, "death event");
    AssertEqual(DateTimeOffset.Parse("2026-07-23T23:41:35.646Z"), events[1].Timestamp, "immediate death timestamp");
}

static void DownedNotificationRemovalWaitsForEntityUnbind()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-15T05:49:11.013Z> [Notice] <SHUDEvent_OnNotification> Added notification \"请等待，本地急救人员正在赶来的路上。: \" [44] to queue.",
        "<2026-07-15T05:49:39.148Z> [Notice] <UpdateNotificationItem> Notification \"请等待，本地急救人员正在赶来的路上。: \" [44], Action: Remove",
        "<2026-07-15T05:49:57.450Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=204763068604"
    ]);

    AssertEqual(2, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "downed event");
    AssertEqual(FleetEventType.PlayerDied, events[1].Type, "death event");
    AssertEqual(DateTimeOffset.Parse("2026-07-15T05:49:57.450Z"), events[1].Timestamp, "death timestamp");
}

static void NonSafeZoneCorpseSequenceParsesDeathAndRespawn()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-24T00:04:13.313Z> [Notice] <Adding non kept item [CSCActorCorpseUtils::PopulateItemPortForItemRecoveryEntitlement]> Item 'body_01_noMagicPocket_718228779388 - Class(body_01_noMagicPocket) - Context(Streamable Runtime-spawned) - Socpak()', Recorded data is: Port Name 'Body_ItemPort', Class GUID: 'dbaa8a7d-755f-4104-8b24-7b58fd1e76f6', KeptId: '718228779388' [Team_CoreGameplayFeatures][Unknown]",
        "<2026-07-24T00:04:25.780Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player in batch 16183 playerGEID=204721330404 sessionId=\"session\" entityId=204721330404, className=\"Player\", classCrc=2961494058, parentEntityId=733628890752",
        "<2026-07-24T00:04:29.718Z> [Notice] <Recv Bind Batch End Player> Bind Batch End enabled player in batch 16336 playerGEID=204721330404 sessionId=\"session\" entityId=204721330404, className=\"Player\", classCrc=2961494058, parentEntityId=729384427710",
        "<2026-07-24T00:04:29.942Z> [Notice] <Update Inventory Location> Player [pilot_alpha] is changing location. Landing [0] -> [141810852]. Location [0] -> [3310153053]. Pending [0]",
        "<2026-07-24T00:04:29.946Z> [CSessionManager::OnClientSpawned] Spawned!"
    ]);

    AssertEqual(2, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDied, events[0].Type, "death event");
    AssertEqual(DateTimeOffset.Parse("2026-07-24T00:04:13.313Z"), events[0].Timestamp, "death evidence timestamp");
    AssertEqual(FleetEventType.PlayerRespawned, events[1].Type, "respawn event");
    AssertEqual(DateTimeOffset.Parse("2026-07-24T00:04:29.946Z"), events[1].Timestamp, "respawn timestamp");
}

static void SecondNonSafeZoneCorpseSequenceParsesDeathAndRespawn()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-24T00:27:46.906Z> [Notice] <AttachmentReceived> Player[pilot_alpha] Attachment[behr_gren_frag_01_735875763581, behr_gren_frag_01, 735875763581] Status[persistent] Port[weapon_attach_hand_right] Elapsed[6.114184] [Team_CoreGameplayFeatures][Inventory]",
        "<2026-07-24T00:28:48.005Z> [Notice] <Adding non kept item [CSCActorCorpseUtils::PopulateItemPortForItemRecoveryEntitlement]> Item 'body_01_noMagicPocket_718228779388 - Class(body_01_noMagicPocket) - Context(Streamable Runtime-spawned) - Socpak()', Recorded data is: Port Name 'Body_ItemPort', Class GUID: 'dbaa8a7d-755f-4104-8b24-7b58fd1e76f6', KeptId: '718228779388' [Team_CoreGameplayFeatures][Unknown]",
        "<2026-07-24T00:29:01.324Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player in batch 23053 playerGEID=204721330404 sessionId=\"session\" entityId=204721330404, className=\"Player\", classCrc=2961494058, parentEntityId=735571010078",
        "<2026-07-24T00:29:01.324Z> [Notice] <Recv Bind Batch Add Player> Bind Batch Add received for player in batch 23054 playerGEID=204721330404 sessionId=\"session\" entityId=204721330404, className=\"Player\", classCrc=2961494058, parentEntityId=735571014610",
        "<2026-07-24T00:29:02.482Z> [Notice] <Update Inventory Location> Player [pilot_alpha] is changing location. Landing [0] -> [0]. Location [0] -> [2627827560]. Pending [0] [Team_CoreGameplayFeatures][Inventory]",
        "<2026-07-24T00:29:02.487Z> [CSessionManager::OnClientSpawned] Spawned!"
    ]);

    AssertEqual(2, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDied, events[0].Type, "death event");
    AssertEqual(DateTimeOffset.Parse("2026-07-24T00:28:48.005Z"), events[0].Timestamp, "death evidence timestamp");
    AssertEqual(FleetEventType.PlayerRespawned, events[1].Type, "respawn event");
    AssertEqual(DateTimeOffset.Parse("2026-07-24T00:29:02.487Z"), events[1].Timestamp, "respawn timestamp");
}

static void RecoveredHandActivityParsesPlayerRevived()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(parser,
    [
        "<2026-07-18T04:47:43.700Z> [Notice] <SHUDEvent_OnNotification> Added notification \"Please wait, local medical responders are on the way.: \" [6] to queue.",
        "<2026-07-18T04:47:48.738Z> [Notice] <UpdateNotificationItem> Notification \"Please wait, local medical responders are on the way.: \" [6], Action: Remove",
        "<2026-07-18T04:48:02.613Z> [Notice] <AttachmentReceived> Player[pilot_alpha] Attachment[crlf_medgun_01_yellow01_718184796345, crlf_medgun_01_yellow01, 718184796345] Status[persistent] Port[weapon_attach_hand_right]",
        "<2026-07-18T04:49:00.000Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=720752916595"
    ]);

    AssertEqual(2, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "downed event");
    AssertEqual(FleetEventType.PlayerRevived, events[1].Type, "revived event");
    AssertEqual(DateTimeOffset.Parse("2026-07-18T04:48:02.613Z"), events[1].Timestamp, "revived timestamp");
}

static void UnbindWithoutDownedContextDoesNotParseDeath()
{
    var parser = NewParserWithLocalPlayer();
    var fleetEvent = parser.TryParse("<2026-07-15T05:49:57.450Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=204763068604");

    AssertEqual<FleetEvent?>(null, fleetEvent, "ordinary unbind");
}

static void RespawnSequenceParsesOnlyAfterRebindAndMedicalBed()
{
    var parser = NewParserWithLocalPlayer();
    var events = ParseLines(
        parser,
        DeathCycleLines("04:54:52.099", "204763068604", "684989414104", "04:55:10.344", "04:55:11.634", "04:55:15.491", "04:55:17.031"));

    AssertEqual(3, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "first event");
    AssertEqual(FleetEventType.PlayerDied, events[1].Type, "second event");
    AssertEqual(FleetEventType.PlayerRespawned, events[2].Type, "third event");
}

static void RespawnCompletesOnClientSpawnWithoutMedicalBedNotice()
{
    var parser = NewParserWithLocalPlayer();
    string[] lines =
    [
        "<2026-07-15T04:54:52.099Z> [Notice] <SHUDEvent_OnNotification> Added notification \"请等待，本地急救人员正在赶来的路上。: \" [4] to queue.",
        "<2026-07-15T04:55:10.344Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=204763068604",
        "<2026-07-15T04:55:11.634Z> [Notice] <Recv Bind Batch Add Player> Bind Batch Add received for player playerGEID=204721330404 entityId=204721330404, className=\"Player\", parentEntityId=684989414104",
        "<2026-07-15T04:55:15.491Z> [Notice] <Initializing Haptic> Initializing haptic component of local player",
        "<2026-07-15T04:55:15.541Z> [Notice] <AttachmentReceived> Player[pilot_alpha] Attachment[body_01, body_01, 200131820647] Status[persistent] Port[Body_ItemPort]",
        "<2026-07-15T04:55:15.549Z> [CSessionManager::OnClientSpawned] Spawned!"
    ];

    var events = ParseLines(parser, lines);
    AssertEqual(3, events.Count, "event count");
    AssertEqual(FleetEventType.PlayerDowned, events[0].Type, "first event");
    AssertEqual(FleetEventType.PlayerDied, events[1].Type, "second event");
    AssertEqual(FleetEventType.PlayerRespawned, events[2].Type, "third event");
}

static void ClientSpawnAloneDoesNotParseRespawn()
{
    var parser = NewParserWithLocalPlayer();
    var fleetEvent = parser.TryParse("<2026-07-15T04:55:15.549Z> [CSessionManager::OnClientSpawned] Spawned!");

    AssertEqual<FleetEvent?>(null, fleetEvent, "ordinary client spawn");
}

static void MedicalBedAloneDoesNotParseRespawn()
{
    var parser = NewParserWithLocalPlayer();
    var fleetEvent = parser.TryParse(MedicalBedLine("2026-07-15T04:57:16.668Z"));

    AssertEqual<FleetEvent?>(null, fleetEvent, "medical bed without rebind");
}

static void TwoSampleDeathCyclesParseTwoDeathsAndTwoRespawns()
{
    var parser = NewParserWithLocalPlayer();
    var lines = DeathCycleLines("04:54:52.099", "204763068604", "684989414104", "04:55:10.344", "04:55:11.634", "04:55:15.491", "04:55:17.031")
        .Concat([MedicalBedLine("2026-07-15T04:57:16.668Z")])
        .Concat(DeathCycleLines("04:57:26.049", "684986838657", "684989415473", "04:57:44.311", "04:57:44.321", "04:57:44.897", "04:57:46.491"));
    var events = ParseLines(parser, lines);

    AssertEqual(2, events.Count(item => item.Type == FleetEventType.PlayerDowned), "downed count");
    AssertEqual(2, events.Count(item => item.Type == FleetEventType.PlayerDied), "death count");
    AssertEqual(2, events.Count(item => item.Type == FleetEventType.PlayerRespawned), "respawn count");
}

static void PresenceBecomesAwayAfterFifteenInactiveMinutes()
{
    var lastInteraction = DateTimeOffset.Parse("2026-07-16T18:00:00Z");

    AssertEqual(
        PlayerPresenceKind.AppOnline,
        PlayerPresence.Resolve(true, false, lastInteraction, lastInteraction.AddMinutes(14).AddSeconds(59)),
        "presence before inactivity threshold");
    AssertEqual(
        PlayerPresenceKind.Away,
        PlayerPresence.Resolve(true, false, lastInteraction, lastInteraction.AddMinutes(15)),
        "presence at inactivity threshold");
}

static void RunningGameOverridesInactiveAppPresence()
{
    var lastInteraction = DateTimeOffset.Parse("2026-07-16T18:00:00Z");
    AssertEqual(
        PlayerPresenceKind.InGame,
        PlayerPresence.Resolve(true, true, lastInteraction, lastInteraction.AddHours(2)),
        "game-running presence");
}

static void PresenceWireValuesNormalizeOldAndNewClients()
{
    AssertEqual(PlayerPresenceKind.InGame, PlayerPresence.Normalize("Active", true), "legacy active status");
    AssertEqual(PlayerPresenceKind.AppOnline, PlayerPresence.Normalize("AppOnline", true), "application-online status");
    AssertEqual(PlayerPresenceKind.Away, PlayerPresence.Normalize("Away", true), "away status");
    AssertEqual(PlayerPresenceKind.Offline, PlayerPresence.Normalize("InGame", false), "offline heartbeat authority");
    AssertEqual(PlayerPresenceKind.Paused, PlayerPresence.Normalize("Paused", false), "privacy-paused status");
}

static void InvisiblePresenceReceivesWithoutPublishing()
{
    var decision = PlayerPresence.DecideSharing(
        PlayerPresenceKind.InGame,
        PlayerPresenceVisibilityMode.Invisible);

    AssertEqual(PlayerPresenceKind.Offline, decision.PublicPresence, "invisible public state");
    AssertEqual(false, decision.CanPublishRealtime, "invisible publishing");
    AssertEqual(true, decision.CanReceiveRealtime, "invisible receiving");
}

static void OfflinePresenceDisablesRealtimeState()
{
    var decision = PlayerPresence.DecideSharing(
        PlayerPresenceKind.InGame,
        PlayerPresenceVisibilityMode.Offline);

    AssertEqual(PlayerPresenceKind.Offline, decision.PublicPresence, "offline public state");
    AssertEqual(false, decision.CanPublishRealtime, "offline publishing");
    AssertEqual(false, decision.CanReceiveRealtime, "offline receiving");
}

static void UnconfirmedGameIdentityRequiresBinding()
{
    var assessment = IdentityBindingPolicy.Evaluate("pilot_alpha", null, "pilot_alpha");

    AssertEqual(IdentityVerificationState.BindingRequired, assessment.State, "binding state");
    AssertEqual(false, assessment.CanSynchronize, "sync permission");
}

static void ConfirmedMatchingGameIdentityAllowsSynchronization()
{
    var assessment = IdentityBindingPolicy.Evaluate(
        "pilot_alpha",
        DateTimeOffset.Parse("2026-07-16T20:00:00Z"),
        "PILOT_ALPHA");

    AssertEqual(IdentityVerificationState.Verified, assessment.State, "binding state");
    AssertEqual(true, assessment.CanSynchronize, "sync permission");
}

static void ConfirmedMismatchedGameIdentityBlocksSynchronization()
{
    var assessment = IdentityBindingPolicy.Evaluate(
        "pilot_alpha",
        DateTimeOffset.Parse("2026-07-16T20:00:00Z"),
        "another_pilot");

    AssertEqual(IdentityVerificationState.Mismatch, assessment.State, "binding state");
    AssertEqual(false, assessment.CanSynchronize, "sync permission");
}

static void ChatHistoryPagerLoadsNewestThenOlderPages()
{
    var messages = Enumerable.Range(1, 120).Select(sequence => (long)sequence).ToArray();
    var newest = SequenceHistoryPager.Page(messages, sequence => sequence, limit: 50);
    AssertEqual(50, newest.Items.Length, "newest page size");
    AssertEqual(71L, newest.Items[0], "newest page starts at sequence 71");
    AssertEqual(120L, newest.LatestSequence, "latest sequence");
    AssertEqual(true, newest.HasOlder, "newest page exposes older history");

    var older = SequenceHistoryPager.Page(messages, sequence => sequence, beforeSequence: newest.OldestSequence, limit: 50);
    AssertEqual(50, older.Items.Length, "older page size");
    AssertEqual(21L, older.Items[0], "older page starts at sequence 21");
    AssertEqual(70L, older.Items[^1], "older page ends immediately before the visible page");
    AssertEqual(true, older.HasOlder, "second page still exposes oldest history");

    var oldest = SequenceHistoryPager.Page(messages, sequence => sequence, beforeSequence: older.OldestSequence, limit: 50);
    AssertEqual(20, oldest.Items.Length, "oldest partial page size");
    AssertEqual(1L, oldest.Items[0], "history reaches first message");
    AssertEqual(false, oldest.HasOlder, "history endpoint is explicit");
}

static void ChatHistoryPagerSeparatesLiveMessagesFromOlderHistory()
{
    var messages = Enumerable.Range(1, 260).Select(sequence => (long)sequence).ToArray();
    var live = SequenceHistoryPager.Page(messages, sequence => sequence, afterSequence: 200, limit: 50);
    AssertEqual(50, live.Items.Length, "live page respects limit");
    AssertEqual(201L, live.Items[0], "live page begins after cursor");
    AssertEqual(250L, live.Items[^1], "live page remains incremental");

    var next = SequenceHistoryPager.Page(messages, sequence => sequence, afterSequence: live.Items[^1], limit: 50);
    AssertEqual(10, next.Items.Length, "remaining live page size");
    AssertEqual(260L, next.Items[^1], "live paging reaches newest message");
}

static RegexLogEventParser NewParserWithLocalPlayer()
{
    var parser = new RegexLogEventParser();
    parser.TryParse("""<2026-07-15T04:50:00.000Z> nickname="pilot_alpha" playerGEID=204721330404""");
    return parser;
}

static List<FleetEvent> ParseLines(RegexLogEventParser parser, IEnumerable<string> lines)
{
    var events = new List<FleetEvent>();
    foreach (var line in lines)
    {
        var fleetEvent = parser.TryParse(line);
        if (fleetEvent is not null)
        {
            events.Add(fleetEvent);
        }
    }

    return events;
}

static IEnumerable<string> DeathCycleLines(
    string deathClock,
    string oldParentId,
    string newParentId,
    string unbindClock,
    string bindClock,
    string hapticClock,
    string medicalClock)
{
    yield return $"""<2026-07-15T{deathClock}Z> [Notice] <SHUDEvent_OnNotification> Added notification "请等待，本地急救人员正在赶来的路上。: " [4] to queue.""";
    yield return $"""<2026-07-15T{deathClock}Z> [Notice] <UpdateNotificationItem> Notification "请等待，本地急救人员正在赶来的路上。: " [4], Action: RemoveIgnore""";
    yield return $"""<2026-07-15T{unbindClock}Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player in batch 1 playerGEID=204721330404 sessionId="session" entityId=204721330404, className="Player", classCrc=2961494058, parentEntityId={oldParentId}""";
    yield return $"""<2026-07-15T{bindClock}Z> [Notice] <Recv Bind Batch Add Player> Bind Batch Add received for player in batch 2 playerGEID=204721330404 sessionId="session" entityId=204721330404, className="Player", classCrc=2961494058, parentEntityId={newParentId}""";
    yield return $"""<2026-07-15T{hapticClock}Z> [Notice] <Initializing Haptic> Initializing haptic component of local player""";
    yield return $"""<2026-07-15T{hapticClock}Z> [Notice] <AttachmentReceived> Player[pilot_alpha] Attachment[body_01, body_01, 1] Status[persistent] Port[Body_ItemPort]""";
    yield return $"""<2026-07-15T{hapticClock}Z> [Notice] <Update Inventory Location> Player [pilot_alpha] is changing location. Landing [0] -> [3170699229]. Location [0] -> [2065796676]. Pending [0]""";
    yield return MedicalBedLine($"2026-07-15T{medicalClock}Z");
}

static string MedicalBedLine(string timestamp)
{
    return $"""<{timestamp}> [Notice] <SHUDEvent_OnNotification> Added notification "医疗床: 医疗床恢复了你的健康，重置了你的血药浓度。" [12] to queue.""";
}

static FleetPlayer SinglePlayer(FleetState state)
{
    return state.Players.Single();
}

static void AssertEqual<T>(T expected, T actual, string label)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"{label}: expected {expected}, got {actual}");
    }
}
