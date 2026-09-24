using System.Text.Json.Serialization;

namespace StarBridge.Core.Presence;

public sealed record CommunityMemberDirectoryRequest(
    [property: JsonRequired] int SchemaVersion,
    [property: JsonRequired] CommunityRealtimeScope Scope, int Offset = 0, string? Revision = null);

public sealed record CommunityMemberSharingTarget(
    [property: JsonRequired] string AccountId,
    [property: JsonRequired] DateTimeOffset JoinedAt,
    [property: JsonRequired] string Name,
    [property: JsonRequired] string Handle,
    [property: JsonRequired] bool DefaultCanView,
    [property: JsonRequired] bool IsSelf,
    [property: JsonRequired] PlayerSharedStateFields LegacyGroupFields);

public sealed record CommunityMemberDirectoryPage(
    [property: JsonRequired] int SchemaVersion,
    [property: JsonRequired] string Code,
    [property: JsonRequired] DateTimeOffset JoinedAt,
    [property: JsonRequired] string Revision,
    [property: JsonRequired] int Offset,
    [property: JsonRequired] int Total,
    [property: JsonRequired] CommunityMemberSharingTarget[] Members);
