using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Dapper;
using Roblox.Dto.Games;
using Roblox.Libraries.EasyJwt;
using Roblox.Libraries.Password;
using Roblox.Logging;
using Roblox.Metrics;
using Roblox.Models.Assets;
using Roblox.Models.Economy;
using Roblox.Models.GameServer;
using Roblox.Rendering;
using Roblox.Services.App.FeatureFlags;
using Roblox.Services.Exceptions;

namespace Roblox.Services;

public class GameServerService : ServiceBase
{
    private const string ClientJoinTicketType = "GameJoinTicketV1.1";
    private const string ServerJoinTicketType = "GameServerTicketV2";
    private static HttpClient client { get; } = new();
    private static string jwtKey { get; set; } = string.Empty;
    private static EasyJwt jwt { get; } = new();
    private static Random RandomComponent = new Random();
    private static PasswordHasher hasher { get; } = new();
    private static Dictionary<long, long> gamePlayerCounts = new Dictionary<long, long>(); // placeid, playercount
    private static Dictionary<string, Process> jobRccs = new Dictionary<string, Process>(); // jobid, rcc process
    public static Dictionary<string, int> currentGameServerPorts = new Dictionary<string, int>() {}; // networkserver ports, jobid, port
    private static Dictionary<long, string> currentPlaceIdsInUse = new Dictionary<long, string>(); // placeid, jobid
    public static Dictionary<long, long> CurrentPlayersInGame = new Dictionary<long, long>() { }; // userid, placeid
    public static Dictionary<Process, int> mainRCCPortsInUse = new Dictionary<Process, int>(); // Process, main RCC soap port
    public static void Configure(string newJwtKey)
    {
        jwtKey = newJwtKey;
    }

    private string HashIpAddress(string hashedIpAddress)
    {
        return hasher.Hash(hashedIpAddress);
    }

    private bool VerifyIpAddress(string hashedIpAddress, string providedIpAddress)
    {
        return hasher.Verify(hashedIpAddress, providedIpAddress);
    }

    /// <summary>
    /// Create a ticket for joining a game
    /// </summary>
    /// <param name="userId">The ID of the user</param>
    /// <param name="placeId">The ID of the place</param>
    /// <param name="ipHash">The IP Address from ControllerBase.GetIP()</param>
    /// <returns></returns>
    public string CreateTicket(long userId, long placeId, string ipHash)
    {
        var entry = new GameServerJwt
        {
            t = ClientJoinTicketType,
            userId = userId,
            placeId = placeId,
            ip = HashIpAddress(ipHash),
            iat = DateTimeOffset.Now.ToUnixTimeSeconds(),
        };
        return jwt.CreateJwt(entry, jwtKey);
    }

    public bool IsExpired(long issuedAt)
    {
        var createdAt = new DateTime(1970, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc).AddSeconds(issuedAt);
        var notExpired = createdAt.Add(TimeSpan.FromMinutes(5)) > DateTime.UtcNow;
        if (!notExpired)
        {
            return true;
        }

        return false;
    }

    public GameServerJwt DecodeTicket(string ticket, string? expectedIpAddress)
    {
        var value = jwt.DecodeJwt<GameServerJwt>(ticket, jwtKey);
        if (value.t != ClientJoinTicketType) throw new ArgumentException("Invalid ticket");
        if (IsExpired(value.iat))
        {
            throw new ArgumentException("Invalid ticket");
        }

        if (expectedIpAddress != null)
        {
            var ipOk = hasher.Verify(value.ip, expectedIpAddress);
            if (!ipOk)
            {
                throw new ArgumentException("Invalid ticket");
            }
        }

        return value;
    }

    public string CreateGameServerTicket(long placeId, string domain)
    {
        var ticket = new GameServerTicketJwt
        {
            t = ServerJoinTicketType,
            placeId = placeId,
            domain = domain,
            iat = DateTimeOffset.Now.ToUnixTimeSeconds(),
        };
        return jwt.CreateJwt(ticket, jwtKey);
    }

    public GameServerTicketJwt DecodeGameServerTicket(string ticket)
    {
        var value = jwt.DecodeJwt<GameServerTicketJwt>(ticket, jwtKey);
        if (value.t != ServerJoinTicketType) throw new ArgumentException("Invalid ticket");
        if (IsExpired(value.iat))
        {
            throw new ArgumentException("Invalid ticket");
        }

        return value;
    }

    public async Task OnPlayerJoin(long userId, long placeId, string serverId)
    {
        /*await db.ExecuteAsync(
            "INSERT INTO asset_server_player (asset_id, user_id, server_id) VALUES (:asset_id, :user_id, :server_id::uuid)",
            new
            {
                asset_id = placeId,
                user_id = userId,
                server_id = serverId,
            });
            */
        CurrentPlayersInGame.Add(userId, placeId);
        await InsertAsync("asset_play_history", new
        {
            asset_id = placeId,
            user_id = userId,
        });
        await db.ExecuteAsync("UPDATE asset_place SET visit_count = visit_count + 1 WHERE asset_id = :id", new
        {
            id = placeId,
        });
        // give ticket to creator
        await InTransaction(async _ =>
        {
            using var assets = ServiceProvider.GetOrCreate<AssetsService>(this);
            var placeDetails = await assets.GetAssetCatalogInfo(placeId);
            using var ec = ServiceProvider.GetOrCreate<EconomyService>(this);
            if (placeDetails.creatorType == CreatorType.Group)
            {
                await InsertAsync("user_transaction", new
                {
                    amount = 10,
                    currency_type = CurrencyType.Tickets,
                    user_id_one = (long?)null,
                    user_id_two = userId,
                    group_id_one = placeDetails.creatorTargetId,
                    type = PurchaseType.PlaceVisit,
                    // store id of the game as well
                    asset_id = placeId,
                });
            }
            else
            {
                await ec.IncrementCurrency(placeDetails.creatorTargetId, CurrencyType.Tickets, 1);
                await InsertAsync("user_transaction", new
                {
                    amount = 10,
                    currency_type = CurrencyType.Tickets,
                    user_id_one = placeDetails.creatorTargetId,
                    user_id_two = userId,
                    type = PurchaseType.PlaceVisit,
                    // store id of the game as well
                    asset_id = placeId,
                });
            }

            return 0;
        });
    }

    public async Task OnPlayerLeave(long userId, long placeId, string serverId)
    {
        CurrentPlayersInGame.Remove(userId);
        var latestSession = await db.QuerySingleOrDefaultAsync<AssetPlayEntry>(
            "SELECT id, created_at as createdAt FROM asset_play_history WHERE user_id = :user_id AND asset_id = :asset_id AND ended_at IS NULL ORDER BY asset_play_history.id DESC LIMIT 1",
            new
            {
                user_id = userId,
                asset_id = placeId,
            });
        if (latestSession != null)
        {
            await db.ExecuteAsync("UPDATE asset_play_history SET ended_at = now() WHERE id = :id", new
            {
                id = latestSession.id,
            });
            
            if (latestSession.createdAt.Year != DateTime.UtcNow.Year) return;
            
            var playTimeMinutes = (long)Math.Truncate((DateTime.UtcNow - latestSession.createdAt).TotalMinutes);
            var earnedTickets = Math.Min(playTimeMinutes * 10, 60); // temp cap, might reduce in the future?
            // cap is 10k tickets per 12 hours (about 1k robux)
            const long maxEarningsPerPeriod = 10000;
            using (var ec = ServiceProvider.GetOrCreate<EconomyService>(this))
            {
                var earningsToday =
                    await ec.CountTransactionEarningsOfType(userId, PurchaseType.PlayingGame, null, TimeSpan.FromHours(12));
                
                if (earningsToday >= maxEarningsPerPeriod)
                    return;
            }
            
            await InTransaction(async _ =>
            {
                using var ec = ServiceProvider.GetOrCreate<EconomyService>(this);
                await ec.IncrementCurrency(userId, CurrencyType.Tickets, earnedTickets);
                await InsertAsync("user_transaction", new
                {
                    amount = earnedTickets,
                    currency_type = CurrencyType.Tickets,
                    user_id_one = userId,
                    user_id_two = 1,
                    type = PurchaseType.PlayingGame,
                    // store id of the game they played as well
                    asset_id = placeId,
                });

                return 0;
            });
        }
    }

    private async Task<T> PostToGameServer<T>(string ipAddress, string port, string methodName, List<dynamic>? args = null, CancellationToken? cancelToken = null)
    {
        var jsonRequest = new
        {
            method = methodName,
            arguments = args ?? new List<dynamic>(),
        };
        var content = new StringContent(JsonSerializer.Serialize(jsonRequest));
        content.Headers.Add("roblox-server-authorization", Configuration.GameServerAuthorization);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");

        if (cancelToken == null)
        {
            var source = new CancellationTokenSource();
            source.CancelAfter(TimeSpan.FromSeconds(30));
            cancelToken = source.Token;
        }

        var result = await client.PostAsync("http://" + ipAddress + ":" + port + "/api/public-method/", content,
            cancelToken.Value);
        if (!result.IsSuccessStatusCode) throw new Exception("Unexpected statusCode: " + result.StatusCode + "\nIP = " + ipAddress + "\nPort = " + port);
        var response = JsonSerializer.Deserialize<T>(await result.Content.ReadAsStringAsync(cancelToken.Value));
        if (response == null)
        {
            throw new Exception("Null response from PostToGameServer");
        }
        return response;
    }

    public async Task<GameServerInfoResponse?> GetGameServerInfo(string ipAddress, string port)
    {
        try
        {
            using var cancelToken = new CancellationTokenSource();
            cancelToken.CancelAfter(TimeSpan.FromSeconds(5));
            return await PostToGameServer<GameServerInfoResponse>(ipAddress, port, "getStatus", default, cancelToken.Token);
        }
        catch (Exception e) when (e is TaskCanceledException or TimeoutException or HttpRequestException)
        {
            // TODO: log this somewhere, should not happen
            return null;
        }
    }

    public async Task StartGame(string ipAddress, string port, long placeId, string gameServerId, int gameServerPort)
    {
        await PostToGameServer<GameServerEmptyResponse>(ipAddress, port, "startGame",
            new List<dynamic> {placeId, gameServerId, gameServerPort});
    }

    public void ShutDownServer(string serverId)
    {
        // TODO: When we add multiple servers for the same game (most likely not for a while), get the jobId or kill the server a better way.
        string placeJobId = serverId; // hopefully not null, shouldn't be??
        long placeId = GetPlaceIdByJobId(serverId);
        Process rccProcess = jobRccs[placeJobId];
        rccProcess.Kill(); // soft kill soon instead of force kill
            
        // Remove from our dictionaries now.
        currentPlaceIdsInUse.Remove(placeId);
        currentGameServerPorts.Remove(placeJobId);
        jobRccs.Remove(placeJobId);
        mainRCCPortsInUse.Remove(rccProcess);
        RemoveAllPlayersFromPlaceId(placeId);
        Console.WriteLine($"GameServer {placeJobId} (place {placeId}) was successfully closed!");
    }
    
    public static void RemoveAllPlayersFromPlaceId(long placeId)
    {
        List<long> playersToRemove = CurrentPlayersInGame.Where(kvp => kvp.Value == placeId).Select(kvp => kvp.Key).ToList();
    
        foreach (var playerID in playersToRemove)
        {
            CurrentPlayersInGame.Remove(playerID);
        }
    }
    
    public static long GetUserPlaceId(long userId) // get user game is in
    {
        bool isInGame = CurrentPlayersInGame.ContainsKey(userId);
        if (!isInGame)
            return 0;

        return CurrentPlayersInGame[userId];
    }
    
    public static long GetPlaceIdByJobId(string jobId)
    {
        foreach (var kvp in currentPlaceIdsInUse)
        {
            if (kvp.Value == jobId)
            {
                return kvp.Key;
            }
        }
            
        return 0; // we never throw exceptions. EVER.
    }

    public async Task<DateTime> GetLastServerPing(string serverId)
    {
        var result = await db.QuerySingleOrDefaultAsync("SELECT updated_at FROM asset_server WHERE id = :id::uuid", new
        {
            id = serverId,
        });
        return (DateTime) result.updated_at;
    }

    public async Task SetServerPing(string serverId)
    {
        await db.ExecuteAsync("UPDATE asset_server SET updated_at = :u WHERE id = :id::uuid", new
        {
            u = DateTime.UtcNow,
            id = serverId,
        });
    }

    public async Task DeleteGameServer(string serverId)
    {
        // then we can delete it...
        await db.ExecuteAsync("DELETE FROM asset_server_player WHERE server_id = :id::uuid", new {id = serverId});
        await db.ExecuteAsync("DELETE FROM asset_server WHERE id = :id::uuid", new {id = serverId});
    }
    
    private static readonly IEnumerable<int> GameServerPorts = new []
    {
        // this must always stay in sync with nginx config file
        53640, // es1-1
        53641, // es1-2, etc
        53642, // 3
        53643, // 4
        53644, // 5
        53645, // 6
        53646, // 7
        53647, // 8
        53648, // 9
        53649, // 10
#if false
        53650,
        53651,
        53652,
        53653,
        53654,
        53655,
#endif
    };
    
    private GameServerPort GetPreferredPortForGameServer(IEnumerable<GameServerMultiRunEntry> runningGames)
    {
        var games = runningGames.ToList();
        var ports = GameServerPorts.ToArray();
        // Find a port that's not in use
        int port = 0;
        int id = 0;
        for (var i = 0; i < ports.Length; i++)
        {
            var portOk = games.Find(c => c.port == ports[i]) == null;
            if (portOk)
            {
                port = ports[i];
                id = i + 1;
                break;
            }
        }
        
        if (port == 0)
        {
            throw new Exception("Cannot find a free port for game server");
        }

        return new GameServerPort(port, id);
    }

    private GameServerPort GetPortByPortNumber(int port)
    {
        var ports = GameServerPorts.ToArray();
        for (int i = 0; i < ports.Length; i++)
        {
            if (ports[i] == port)
            {
                return new GameServerPort(ports[i], i + 1);
            }
        }

        throw new ArgumentOutOfRangeException();
    }
    
    public async Task<List<Tuple<GameServerInfoResponse,GameServerConfigEntry>>> GetAllGameServers()
    {
        var getServerDataTasks = new List<Task<GameServerInfoResponse?>>();
        foreach (var entry in Configuration.GameServerIpAddresses)
        {
            var data = entry.ip.Split(":");
            var ip = data[0];
            var port = data[1];
            getServerDataTasks.Add(GetGameServerInfo(ip, port));
        }

        var getServerDataResults = await Task.WhenAll(getServerDataTasks);

        var serverData =getServerDataResults.Select((c, idx) =>
                new Tuple<GameServerInfoResponse?, GameServerConfigEntry>(c, Configuration.GameServerIpAddresses.ToArray()[idx]))
            .Where(v => v.Item1 != null)
            .ToList();
        return serverData!;
    }

    /*private async Task<GameServerGetOrCreateResponse> GetServerForPlaceV2(long placeId)
    {
        await using var serverCreationLock = await Cache.redLock.CreateLockAsync("CreateGameServerV1", TimeSpan.FromSeconds(30));
        if (!serverCreationLock.IsAcquired)
            return new GameServerGetOrCreateResponse
            {
                status = JoinStatus.Waiting,
            };

        var serverData = await GetAllGameServers();

        long maxPlayerCount;
        using (var gs = ServiceProvider.GetOrCreate<GamesService>())
        {
            maxPlayerCount = await gs.GetMaxPlayerCount(placeId);
        } 
        // First, try to see if this game is already running. If it is, we should make the player join that.
        foreach (var (serverInfo, entry) in serverData)
        {
            var runningGames = serverInfo!.data.ToList();
            var runningPlaces = runningGames.ToArray();
            if (runningPlaces.Length == 0) continue;
            foreach (var runningPlace in runningPlaces)
            {
#if RELEASE
                // TODO: move this to bg job or something.
                // This fixes a bug when the server seems to not be shut down properly - sometimes there will be a
                // lingering game for hours after the server *should* have been shutdown.
                // first part, do game servers
                var serversToDelete = await db.QuerySingleOrDefaultAsync<GameServerWithUpdated>(
                    "SELECT id::text, asset_id as assetId, created_at as createdAt, updated_at as updatedAt FROM asset_server WHERE id = :id::uuid",
                    new
                    {
                        id = runningPlace.id,
                    });
                if (serversToDelete == null ||
                    serversToDelete.updatedAt <= DateTime.UtcNow.Subtract(TimeSpan.FromMinutes(5)))
                {
                    Writer.Info(LogGroup.GameServerJoin, "closing server with id={0} due to it being last updated over 5 minutes ago or not existing. updatedAt={1}", runningPlace.id, serversToDelete?.updatedAt);
                    var ipPort = entry.ip.Split(":");
                    Roblox.Metrics.GameMetrics.ReportServerShutdownWithoutDatabaseEntry(entry.ip,
                        runningPlace.placeId);
                    // Either server doesn't exist, or the server wasn't deleted when it should have been. release it.
                    await PostToGameServer<GameServerEmptyResponse>(ipPort[0], ipPort[1], "shutdown", new List<dynamic> { runningPlace.id });
                    continue; // Don't try to use this server yet.
                }
#endif
                // check if this is the right place
                if (runningPlace.placeId != placeId)
                    continue;
                // check if server has too many players
                var currentPlayerCount = await GetGameServerPlayers(runningPlace.id);
                if (currentPlayerCount.Count() >= maxPlayerCount)
                    continue;
                // We found a good place! Tell them to join...
                var joinUrl = GetPortByPortNumber(runningPlace.port).ApplyIdToUrl(entry.domain);
                Writer.Info(LogGroup.GameServerJoin, "Found a good place! placeId = {0} port = {1} url = {2}", placeId, runningPlace.port, joinUrl);
                return new()
                {
                    status = JoinStatus.Joining,
                    job = CreateGameServerTicket(placeId, joinUrl),
                };   
            }
        }
        // Sort by least loaded
        serverData = serverData.Where(a => a.Item1 != null && a.Item1.data != null).ToList();
        serverData.Sort((a, b) =>
        {
            var cOne = a.Item1!.data.Count();
            var cTwo = b.Item1!.data.Count();
            return cOne > cTwo ? 1 : cOne == cTwo ? 0 : -1;
        });
        Writer.Info(LogGroup.GameServerJoin, "Least loaded server is {0} with {1} games running", serverData[0].Item2.ip, serverData[0].Item1!.data.Count());
        foreach (var (serverInfo, entry) in serverData)
        {
            var data = entry.ip.Split(":");
            var ip = data[0];
            var port = data[1];
            var runningCount = serverInfo!.data.Count();
            if (runningCount >= entry.maxServerCount)
            {
                Writer.Info(LogGroup.GameServerJoin, "cannot start server on {0} since it has too many games running ({1} vs {2})", entry.ip, runningCount, entry.maxServerCount);
                continue;
            }
            // Create the server
            var id = Guid.NewGuid().ToString();
            var gamePort = GetPreferredPortForGameServer(serverInfo.data);
            await db.ExecuteAsync(
                "INSERT INTO asset_server (id, asset_id, ip, port, server_connection) VALUES (:id::uuid, :asset_id, :ip, :port, :server_connection)",
                new
                {
                    id,
                    asset_id = placeId,
                    ip,
                    gamePort.port,
                    server_connection = entry.ip, // ip:port
                });
            try
            {
                var watch = new Stopwatch();
                watch.Start();
                await StartGame(ip, port, placeId, id, gamePort.port);
                watch.Stop();
                GameMetrics.ReportTimeToStartGameServer(ip, port, watch.ElapsedMilliseconds);
            }
            catch (Exception e)
            {
                await db.ExecuteAsync("DELETE FROM asset_server WHERE id = :id::uuid", new {id});
                throw new Exception("Cannot start game server", e);
            }

            Writer.Info(LogGroup.GameServerJoin, "Created server for {0} at {1}:{2}. Join url = {3}", placeId, entry.domain, gamePort.port, gamePort.ApplyIdToUrl(entry.domain));

            return new()
            {
                status = JoinStatus.Joining,
                job = CreateGameServerTicket(placeId, gamePort.ApplyIdToUrl(entry.domain)),
            };
        }
        
        // Default
        return new()
        {
            status = JoinStatus.Waiting,
        };
    }
    */

    public async Task<GameServerGetOrCreateResponse> GetServerForPlace(long placeId)
    {
        string jobId = Guid.NewGuid().ToString();

        int mainRCCPort = RandomComponent.Next(30000, 40000);
        int networkServerPort = RandomComponent.Next(50000, 60000);
        string StartGameInfo;
        
        if (currentPlaceIdsInUse.ContainsKey(placeId)!)
        {
            jobId = currentPlaceIdsInUse[placeId];
            StartGameInfo = "OK";
        }
        else
        {
            StartGameInfo = await StartGameServer(placeId, mainRCCPort, networkServerPort, jobId, 43200);
        }

        return StartGameInfo != "BAD"
            ? new GameServerGetOrCreateResponse()
            {
                job = jobId,
                status = JoinStatus.Joining
            }
            : new GameServerGetOrCreateResponse()
            {
                status = JoinStatus.Waiting
            };
    }
    
    public async Task<string> StartGameServer(long placeId, int RCCPort, int networkServerPort, string jobId, int JobExpiration)
    {
        // Before we waste our time, check if the place exists.
        AssetsService assetsService = new AssetsService();
        GamesService gamesService = new GamesService();
        var AssetCatalogInfo = await assetsService.GetAssetCatalogInfo(placeId);
        var uni = (await gamesService.MultiGetPlaceDetails(new[] { placeId })).First();
        if (AssetCatalogInfo.assetType != Models.Assets.Type.Place)
        {
            return "BAD";
        }
        Process rccServer = new Process();
        rccServer.StartInfo.CreateNoWindow = false;
        rccServer.StartInfo.WindowStyle = ProcessWindowStyle.Minimized;
        rccServer.StartInfo.FileName = $"{RenderingHandler.RccServicePath}RCCService.exe";
        rccServer.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
        rccServer.StartInfo.RedirectStandardError = false;
        rccServer.StartInfo.RedirectStandardOutput = false;
        rccServer.StartInfo.UseShellExecute = true;
        rccServer.Start();
        string originalScript = File.ReadAllText($"{RenderingHandler.LuaScriptPath}GameServerFloatzel.lua");
        string finalScript = originalScript.Replace
            ("%port%", $"{networkServerPort}").Replace
            ("%placeId%", $"{placeId}").Replace
            ("%creatorId%", $"{uni.builderId}").Replace
            ("_AUTHORIZATION_STRING_", Configuration.GameServerAuthorization);
        string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <OpenJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{jobId}</id>
                            <category>1</category>
                            <cores>1</cores>
                            <expirationInSeconds>{JobExpiration}</expirationInSeconds>
                        </job>
                        <script>
                            <name>{Guid.NewGuid().ToString()}</name>
                            <script>
                                <![CDATA[
                                {finalScript}
                                ]]>
                            </script>
                        </script>
                    </OpenJobEx>
                </soap:Body>
            </soap:Envelope>";
        await SendSoapRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "OpenJobEx");
        currentPlaceIdsInUse.Add(placeId, jobId);
        currentGameServerPorts.Add(jobId, networkServerPort);
        jobRccs.Add(jobId, rccServer);
        return "OK";
    }
    
    public static async Task SendSoapRequestToRcc(string URL, string XML, string SOAPAction)
    {
        using (HttpClient RccHttpClient = new HttpClient())
        {
            RccHttpClient.DefaultRequestHeaders.Add("SOAPAction", $"http://economysimulator.com/{SOAPAction}");
            HttpContent XMLContent = new StringContent(XML, Encoding.UTF8, "text/xml");
            try
            {
                HttpResponseMessage RccHttpClientPost = await RccHttpClient.PostAsync(URL, XMLContent);
                string RccHttpClientResponse = await RccHttpClientPost.Content.ReadAsStringAsync();
                if (!RccHttpClientPost.IsSuccessStatusCode)
                {
                    return;
                }
            }
            catch (Exception e)
            {
                Console.WriteLine($"[RCCSendRequest] Failed to send request to RCC: {e}");
            }
        }
    }
    
    public async Task DeleteOldGameServers()
    {
        // first part, do game servers
        var serversToDelete = (await db.QueryAsync<GameServerEntry>("SELECT id::text, asset_id as assetId FROM asset_server WHERE updated_at <= :t", new
        {
            t = DateTime.UtcNow.Subtract(TimeSpan.FromMinutes(2)),
        })).ToList();
        Console.WriteLine("[info] there are {0} bad servers", serversToDelete.Count);
        foreach (var server in serversToDelete)
        {
            var players = await GetGameServerPlayers(server.id);
            foreach (var player in players)
            {
                await OnPlayerLeave(player.userId, server.assetId, server.id);
            }
            Console.WriteLine("[info] deleting server {0}", server.id);
            await db.ExecuteAsync("DELETE FROM asset_server_player WHERE server_id = :id::uuid", new
            {
                id = server.id,
            });
            await db.ExecuteAsync("DELETE FROM asset_server WHERE id = :id::uuid", new
            {
                id = server.id,
            });
        }
        // second part, do game server players
        // this is so ugly jeez
        var orphanedPlayers =
            await db.QueryAsync(
                "SELECT s.id, p.server_id FROM asset_server_player p LEFT JOIN asset_server s ON s.id = p.server_id WHERE s.id IS NULL");
        foreach (var deadbeatDad in orphanedPlayers.Select(c => ((Guid) c.server_id).ToString()).Distinct())
        {
            Console.WriteLine("[info] deleting all orphans for serverId = {0}",deadbeatDad);
            await db.ExecuteAsync("DELETE FROM asset_server_player WHERE server_id = :id::uuid", new
            {
                id = deadbeatDad,
            });
        }
    }

    public async Task<IEnumerable<GameServerPlayer>> GetGameServerPlayers(string serverId)
    {
        return await db.QueryAsync<GameServerPlayer>(
            "SELECT user_id as userId, u.username FROM asset_server_player INNER JOIN \"user\" u ON u.id = asset_server_player.user_id WHERE server_id = :id::uuid", new
            {
               id = serverId,
            });
    }

    public async Task<IEnumerable<GameServerEntryWithPlayers>> GetGameServers(long placeId, int offset, int limit)
    {
        var result = (await db.QueryAsync<GameServerEntryWithPlayers>("SELECT id::text, asset_id as assetId FROM asset_server WHERE asset_id = :id LIMIT :limit OFFSET :offset", new
        {
            id = placeId,
            limit,
            offset,
        })).ToList();
        foreach (var server in result)
        {
            server.players = await GetGameServerPlayers(server.id);
        }

        return result;
    }

    public async Task<IEnumerable<GameServerEntry>> GetGamesUserIsPlaying(long userId)
    {
       return await db.QueryAsync<GameServerEntry>(
            "SELECT s.id::text, s.asset_id as assetId FROM asset_server_player p INNER JOIN asset_server s ON s.id = p.server_id WHERE p.user_id = :id",
            new
            {
                id = userId,
            });
    }
}