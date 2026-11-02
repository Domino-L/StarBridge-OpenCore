using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Friends;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Caller owns account generation validation and the existing bounded session-refresh policy.
    internal async Task<FriendsView> SearchParticipantsAsync(ScmOAuthSession session, string query, CancellationToken token)
    {
        if (query.Length is < 2 or > 64 || query.Any(char.IsControl))
            throw new Account.AccountBridgeHostException("friends.invalid_request");
        using var request = new HttpRequestMessage(HttpMethod.Post,
            new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/participants/search"))
            { Content = JsonContent.Create(new { query }) };
        return FriendsReader.ParseScmSearch(await ReadParticipantBytesAsync(session, request, token), query);
    }

    internal async Task<FriendView> ReadFriendIdentityAsync(ScmOAuthSession session, string id, CancellationToken token)
    {
        if (!FriendsReader.IsScmBusinessId(id)) throw new Account.AccountBridgeHostException("friends.data_invalid");
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(options.ResourceServerBaseUri,
            "app-api/starbridge/v1/participants/" + Uri.EscapeDataString(id) + "/friend-identity"));
        return FriendsReader.ParseScmFriendIdentity(await ReadParticipantBytesAsync(session, request, token), id);
    }

    private async Task<byte[]> ReadParticipantBytesAsync(ScmOAuthSession session, HttpRequestMessage request, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        try {
            using var response = await scmHttpClient.SendAsync(request, session.AccessToken, deadline.Token,
                completionOption: HttpCompletionOption.ResponseHeadersRead);
            // Bound before decoding, including chunked responses with no Content-Length.
            if (response.Content.Headers.ContentLength > 64 * 1024)
                throw new ScmApiProtocolException("参与者搜索响应过大。");
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[4096];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) != 0) {
                if (buffer.Length + count > 64 * 1024) throw new ScmApiProtocolException("参与者搜索响应过大。");
                buffer.Write(chunk, 0, count);
            }
            var bytes = buffer.ToArray();
            // Error decoding also uses the bounded body.
            response.Content.Dispose();
            response.Content = new ByteArrayContent(bytes);
            await ScmHttpClient.EnsureSuccessAsync(response, "参与者搜索", deadline.Token);
            return bytes;
        } catch (OperationCanceledException error) when (!token.IsCancellationRequested) {
            throw FriendsReadFailures.FromTransport(error, token);
        } catch (ScmApiAuthenticationException) { throw;
        } catch (ScmApiForbiddenException) {
            throw new Account.AccountBridgeHostException("friends.forbidden");
        } catch (ScmApiProtocolException) {
            throw new Account.AccountBridgeHostException("friends.data_invalid");
        } catch (Exception error) when (error is HttpRequestException or IOException) {
            throw FriendsReadFailures.FromTransport(error, token);
        }
    }
}
