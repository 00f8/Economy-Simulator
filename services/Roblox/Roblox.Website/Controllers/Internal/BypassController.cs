using System.ComponentModel.DataAnnotations;
using System.Dynamic;
using System.Security.Cryptography;
using System.Text;
using System.Web;
using System.Xml.Linq;
using Microsoft.AspNetCore.Http.Extensions;
using Microsoft.Net.Http.Headers;
using Newtonsoft.Json;
using Roblox.Dto.Games;
using Roblox.Dto.Persistence;
using Roblox.Dto.Users;
using MVC = Microsoft.AspNetCore.Mvc;
using Roblox.Libraries.Assets;
using Roblox.Libraries.FastFlag;
using Roblox.Libraries.RobloxApi;
using Roblox.Logging;
using Roblox.Services.Exceptions;
using BadRequestException = Roblox.Exceptions.BadRequestException;
using Roblox.Models.Assets;
using Roblox.Models.GameServer;
using Roblox.Models.Users;
using Roblox.Services;
using Roblox.Services.App.FeatureFlags;
using Roblox.Website.Controllers.Internal;
using Roblox.Website.Filters;
using Roblox.Website.Middleware;
using Roblox.Website.WebsiteModels.Asset;
using Roblox.Website.WebsiteModels.Games;
using HttpGet = Roblox.Website.Controllers.HttpGetBypassAttribute;
using JsonSerializer = System.Text.Json.JsonSerializer;
using MultiGetEntry = Roblox.Dto.Assets.MultiGetEntry;
using SameSiteMode = Microsoft.AspNetCore.Http.SameSiteMode;
using ServiceProvider = Roblox.Services.ServiceProvider;
using Type = Roblox.Models.Assets.Type;

namespace Roblox.Website.Controllers
{
    [MVC.ApiController]
    [MVC.Route("/")]
    public class BypassController : ControllerBase
    {
        [HttpGet("internal/release-metadata")]
        public dynamic GetReleaseMetaData([Required] string requester)
        {
            throw new RobloxException(RobloxException.BadRequest, 0, "BadRequest");
        }

        [HttpGet("asset/shader")]
        public async Task<MVC.FileResult> GetShaderAsset(long id)
        {
            var isMaterialOrShader = BypassControllerMetadata.materialAndShaderAssetIds.Contains(id);
            if (!isMaterialOrShader)
            {
                // Would redirect but that could lead to infinite loop.
                // Just throw instead
                throw new RobloxException(400, 0, "BadRequest");
            }

            var assetId = id;
            try
            {
                var ourId = await services.assets.GetAssetIdFromRobloxAssetId(assetId);
                assetId = ourId;
            }
            catch (RecordNotFoundException)
            {
                // Doesn't exist yet, so create it
                var migrationResult = await MigrateItem.MigrateItemFromRoblox(assetId.ToString(), false, null, default, new ProductDataResponse()
                {
                    Name = "ShaderConversion" + id,
                    AssetTypeId = Type.Special, // Image
                    Created = DateTime.UtcNow,
                    Updated = DateTime.UtcNow,
                    Description = "ShaderConversion1.0",
                });
                assetId = migrationResult.assetId;
            }
            
            var latestVersion = await services.assets.GetLatestAssetVersion(assetId);
            if (latestVersion.contentUrl is null)
            {
                throw new RobloxException(403, 0, "Forbidden"); // ?
            }
            // These files are large, encourage clients to cache them
            HttpContext.Response.Headers.CacheControl = new CacheControlHeaderValue()
            {
                Public = true,
                MaxAge = TimeSpan.FromDays(360),
            }.ToString();
            var assetContent = await services.assets.GetAssetContent(latestVersion.contentUrl);
            return File(assetContent, "application/binary");
        }

        private bool IsRcc()
        {
            var rccAccessKey = Request.Headers.ContainsKey("accesskey") ? Request.Headers["accesskey"].ToString() : null;
            var isRcc = rccAccessKey == Configuration.RccAuthorization;
            return isRcc;
        }

        [HttpGet("asset")]
        public async Task<MVC.ActionResult> GetAssetById(long id)
        {
            // TODO: This endpoint needs to be updated to return a URL to the asset, not the asset itself.
            // The reason for this is so that cloudflare can cache assets without caching the response of this endpoint, which might be different depending on the client making the request (e.g. under 18 user, over 18 user, rcc, etc).
            var is18OrOver = false;
            if (userSession != null)
            {
                is18OrOver = await services.users.Is18Plus(userSession.userId);
            }

            // TEMPORARY UNTIL AUTH WORKS ON STUDIO! REMEMBER TO REMOVE
            if (HttpContext.Request.Headers.ContainsKey("RbxTempBypassFor18PlusAssets"))
            {
                is18OrOver = true;
            }
            
            var assetId = id;
            var invalidIdKey = "InvalidAssetIdForConversionV1:" + assetId;
            // Opt
            if (Services.Cache.distributed.StringGetMemory(invalidIdKey) != null)
                throw new RobloxException(400, 0, "Asset is invalid or does not exist");
            
            var isBotRequest = Request.Headers["bot-auth"].ToString() == Roblox.Configuration.BotAuthorization;
            var isLoggedIn = userSession != null;
            var encryptionEnabled = !isBotRequest; // bots can't handle encryption :(
#if DEBUG == false
            var userAgent = Request.Headers["User-Agent"].FirstOrDefault()?.ToLower();
            var requester = Request.Headers["Requester"].FirstOrDefault()?.ToLower();
            if (!isBotRequest && !isLoggedIn) {
                if (userAgent is null) throw new BadRequestException();
                if (requester is null) throw new BadRequestException();
                // Client = studio/client, Server = rcc
                if (requester != "client" && requester != "server")
                {
                    throw new BadRequestException();
                }

                if (!BypassControllerMetadata.allowedUserAgents.Contains(userAgent))
                {
                    throw new BadRequestException();
                }
            }
#endif

            var isMaterialOrShader = BypassControllerMetadata.materialAndShaderAssetIds.Contains(assetId);
            if (isMaterialOrShader)
            {
                return new MVC.RedirectResult("/asset/shader?id=" + assetId);
            }

            var isRcc = IsRcc();
            if (isRcc)
                encryptionEnabled = false;
#if DEBUG
            encryptionEnabled = false;
#endif
            MultiGetEntry details;
            try 
            {
                details = await services.assets.GetAssetCatalogInfo(assetId);
            } 
            catch (RecordNotFoundException) 
            {
                try
                {
                    var ourId = await services.assets.GetAssetIdFromRobloxAssetId(assetId);
                    assetId = ourId;
                }
                catch (RecordNotFoundException)
                {
                    if (await Services.Cache.distributed.StringGetAsync(invalidIdKey) != null)
                        throw new RobloxException(400, 0, "Asset is invalid or does not exist");
                    
                    try
                    {
                        // Doesn't exist yet, so create it
                        var migrationResult = await MigrateItem.MigrateItemFromRoblox(assetId.ToString(), false, null,
                            new List<Type>()
                            {
                                Type.Image,
                                Type.Audio,
                                Type.Mesh,
                                Type.Lua,
                                Type.Model,
                                Type.Decal,
                                Type.Animation,
                                Type.SolidModel,
                                Type.MeshPart,
                                Type.ClimbAnimation,
                                Type.DeathAnimation,
                                Type.FallAnimation,
                                Type.IdleAnimation,
                                Type.JumpAnimation,
                                Type.RunAnimation,
                                Type.SwimAnimation,
                                Type.WalkAnimation,
                                Type.PoseAnimation,
                            }, default, default, true);
                        assetId = migrationResult.assetId;
                    }
                    catch (AssetTypeNotAllowedException)
                    {
                        // TODO: permanently insert as invalid for AssetTypeNotAllowedException in a table
                        await Services.Cache.distributed.StringSetAsync(invalidIdKey,
                            "{}", TimeSpan.FromDays(7));
                        throw new RobloxException(400, 0, "Asset is invalid or does not exist");
                    }
                    catch (Exception e)
                    {
                        // temporary failure? mark as invalid, but only temporarily
                        Writer.Info(LogGroup.AssetDelivery, "Failed to migrate asset " + assetId + " - " + e.Message + "\n" + e.StackTrace);
                        await Services.Cache.distributed.StringSetAsync(invalidIdKey,
                            "{}", TimeSpan.FromMinutes(1));
                        throw new RobloxException(400, 0, "Asset is invalid or does not exist");
                    }
                }
                details = await services.assets.GetAssetCatalogInfo(assetId);
            }
            if (details.is18Plus && !isRcc && !isBotRequest && !is18OrOver)
                throw new RobloxException(400, 0, "AssetTemporarilyUnavailable");
            if (details.moderationStatus != ModerationStatus.ReviewApproved && !isRcc && !isBotRequest)
                throw new RobloxException(403, 0, "Asset not approved for requester");
            
            var latestVersion = await services.assets.GetLatestAssetVersion(assetId);
            Stream? assetContent = null;
            switch (details.assetType)
            {
                // Special types
                case Roblox.Models.Assets.Type.TeeShirt:
                    return new MVC.FileContentResult(Encoding.UTF8.GetBytes(ContentFormatters.GetTeeShirt(latestVersion.contentId)), "application/binary");
                case Models.Assets.Type.Shirt:
                    return new MVC.FileContentResult(Encoding.UTF8.GetBytes(ContentFormatters.GetShirt(latestVersion.contentId)), "application/binary");
                case Models.Assets.Type.Pants:
                    return new MVC.FileContentResult(Encoding.UTF8.GetBytes(ContentFormatters.GetPants(latestVersion.contentId)), "application/binary");
                // Types that require no authentication and aren't encrypted
                case Models.Assets.Type.Image:
                case Models.Assets.Type.Special:
                    if (latestVersion.contentUrl != null)
                        assetContent = await services.assets.GetAssetContent(latestVersion.contentUrl);
                    // encryptionEnabled = false;
                    break;
                // Types that require no authentication
                case Models.Assets.Type.Audio:
                case Models.Assets.Type.Mesh:
                case Models.Assets.Type.Hat:
                case Models.Assets.Type.Model:
                case Models.Assets.Type.Decal:
                case Models.Assets.Type.Head:
                case Models.Assets.Type.Face:
                case Models.Assets.Type.Gear:
                case Models.Assets.Type.Badge:
                case Models.Assets.Type.Animation:
                case Models.Assets.Type.Torso:
                case Models.Assets.Type.RightArm:
                case Models.Assets.Type.LeftArm:
                case Models.Assets.Type.RightLeg:
                case Models.Assets.Type.LeftLeg:
                case Models.Assets.Type.Package:
                case Models.Assets.Type.GamePass:
                case Models.Assets.Type.Plugin: // TODO: do plugins need auth?
                case Models.Assets.Type.MeshPart:
                case Models.Assets.Type.HairAccessory:
                case Models.Assets.Type.FaceAccessory:
                case Models.Assets.Type.NeckAccessory:
                case Models.Assets.Type.ShoulderAccessory:
                case Models.Assets.Type.FrontAccessory:
                case Models.Assets.Type.BackAccessory:
                case Models.Assets.Type.WaistAccessory:
                case Models.Assets.Type.ClimbAnimation:
                case Models.Assets.Type.DeathAnimation:
                case Models.Assets.Type.FallAnimation:
                case Models.Assets.Type.IdleAnimation:
                case Models.Assets.Type.JumpAnimation:
                case Models.Assets.Type.RunAnimation:
                case Models.Assets.Type.SwimAnimation:
                case Models.Assets.Type.WalkAnimation:
                case Models.Assets.Type.PoseAnimation:
                case Models.Assets.Type.SolidModel:
                    if (latestVersion.contentUrl is null)
                        throw new RobloxException(400, 0, "BadRequest"); // todo: should we log this?
                    if (details.assetType == Models.Assets.Type.Audio)
                    {
                        // Convert to WAV file since that's what web client requires
                        assetContent = await services.assets.GetAudioContentAsWav(assetId, latestVersion.contentUrl);
                    }
                    else
                    {
                        assetContent = await services.assets.GetAssetContent(latestVersion.contentUrl);
                    }
                    break;
                default:
                    // anything else requires auth
                    var ok = false;
                    if (isRcc)
                    {
                        encryptionEnabled = false;
                        var placeIdHeader = Request.Headers["roblox-place-id"].ToString();
                        long placeId = 0;
                        if (!string.IsNullOrEmpty(placeIdHeader))
                        {
                            try
                            {
                                placeId = long.Parse(Request.Headers["roblox-place-id"].ToString());
                            }
                            catch (FormatException)
                            {
                                // Ignore
                            }
                        }
                        // if rcc is trying to access current place, allow through
                        ok = (placeId == assetId);
                        // If game server is trying to load a new place (current placeId is empty), then allow it
                        if (!ok && details.assetType == Models.Assets.Type.Place && placeId == 0)
                        {
                            // Game server is trying to load, so allow it
                            ok = true;
                        }
                        // If rcc is making the request, but it's not for a place, validate the request:
                        if (!ok)
                        {
                            // Check permissions
                            var placeDetails = await services.assets.GetAssetCatalogInfo(placeId);
                            if (placeDetails.creatorType == details.creatorType &&
                                placeDetails.creatorTargetId == details.creatorTargetId)
                            {
                                // We are authorized
                                ok = true;
                            }
                        }
                    }
                    else
                    {
                        // It's not RCC making the request. are we authorized?
                        if (userSession != null)
                        {
                            // Use current user as access check
                            ok = await services.assets.CanUserModifyItem(assetId, userSession.userId);
                            if (!ok)
                            {
                                // Note that all users have access to "Roblox"'s content for legacy reasons
                                ok = (details.creatorType == CreatorType.User && details.creatorTargetId == 1);
                            }
#if DEBUG
                            // If staff, allow access in debug builds
                            if (await services.users.IsUserStaff(userSession.userId))
                            {
                                ok = true;
                            }
#endif
                            // Don't encrypt assets being sent to authorized users - they could be trying to download their own place to give to a friend or something
                            if (ok)
                            {
                                encryptionEnabled = false;
                            }
                        }
                    }

                    if (ok && latestVersion.contentUrl != null)
                    {
                        assetContent = await services.assets.GetAssetContent(latestVersion.contentUrl);
                    }

                    break;
            }

            if (assetContent != null)
            {
                return File(assetContent, "application/binary");
            }

            Console.WriteLine("[info] got BadRequest on /asset/ endpoint");
            throw new BadRequestException();
        }

        [HttpGet("Game/GamePass/GamePassHandler.ashx")]
        public async Task<string> GamePassHandler(string Action, long UserID, long PassID)
        {
            if (Action == "HasPass")
            {
                var has = await services.users.GetUserAssets(UserID, PassID);
                return has.Any() ? "True" : "False";
            }

            throw new NotImplementedException();
        }

        [HttpGet("Game/LuaWebService/HandleSocialRequest.ashx")]
        public async Task<string> LuaSocialRequest([Required, MVC.FromQuery] string method, long? playerid = null, long? groupid = null, long? userid = null)
        {
            // TODO: Implement these
            method = method.ToLower();
            if (method == "isingroup" && playerid != null && groupid != null)
            {
                bool isInGroup = false;
                try
                {
                    var group = await services.groups.GetUserRoleInGroup((long) groupid, (long) playerid);
                    if (group.rank != 0)
                        isInGroup = true;
                }
                catch (Exception)
                {
                    
                }

                return "<Value Type=\"boolean\">"+(isInGroup ? "true" : "false")+"</Value>";
            }

            if (method == "getgrouprank" && playerid != null && groupid != null)
            {
                int rank = 0;
                try
                {
                    var group = await services.groups.GetUserRoleInGroup((long) groupid, (long) playerid);
                    rank = group.rank;
                }
                catch (Exception)
                {
                    
                }

                return "<Value Type=\"integer\">"+rank+"</Value>";
            }

            if (method == "getgrouprole" && playerid != null && groupid != null)
            {
                var groups = await services.groups.GetAllRolesForUser((long) playerid);
                foreach (var group in groups)
                {
                    if (group.groupId == groupid)
                    {
                        return group.name;
                    }
                }

                return "Guest";
            }

            if (method == "isfriendswith" && playerid != null && userid != null)
            {
                var status = (await services.friends.MultiGetFriendshipStatus((long) playerid, new[] {(long) userid})).FirstOrDefault();
                if (status != null && status.status == "Friends")
                {
                    return "<Value Type=\"boolean\">True</Value>";
                }
                return "<Value Type=\"boolean\">False</Value>";

            }

            if (method == "isbestfriendswith")
            {
                return "<Value Type\"boolean\">False</value>";
            }

            throw new NotImplementedException();
        }

        [HttpGet("login/negotiate.ashx"), HttpGet("login/negotiateasync.ashx")]
        public void Negotiate([Required, MVC.FromQuery] string suggest)
        {
            HttpContext.Response.Cookies.Append(".ROBLOSECURITY", suggest, new CookieOptions
            {
                Domain = ".economysimulator.com",
                Secure = false,
                Expires = DateTimeOffset.Now.Add(TimeSpan.FromDays(364)),
                IsEssential = true,
                Path = "/",
                SameSite = SameSiteMode.Lax,
            });
        }

        [HttpGet("/auth/submit")]
        public MVC.RedirectResult SubmitAuth(string auth)
        {
            return new MVC.RedirectResult("/");
        }

        [HttpGetBypass("/game/PlaceLauncher.ashx")]
        [HttpPostBypass("/game/PlaceLauncher.ashx")]
        public async Task<dynamic> PlaceLaunch(long placeId)
        {
            if (userSession == null)
            {
                return BadRequest();
            }
            FeatureFlags.FeatureCheck(FeatureFlag.GamesEnabled, FeatureFlag.GameJoinEnabled);
            GameServerJwt details = new GameServerJwt
            {
                userId = userSession.userId,
                placeId = placeId,
                t = "GameJoinTicketV1.1",
                iat = DateTimeOffset.Now.ToUnixTimeSeconds(),
                ip = GetIP()
            };
            var result = await services.gameServer.GetServerForPlace(details.placeId);
            if (result.status == JoinStatus.Joining)
            {
                await Roblox.Metrics.GameMetrics.ReportGameJoinPlaceLauncherReturned(details.placeId);
                return new
                {
                    jobId = result.job,
                    status = (int)result.status,
                    joinScriptUrl = $"{Configuration.BaseUrl}/Game/Join.ashx?jobId={result.job}&placeId={placeId}",
                    authenticationUrl = Configuration.BaseUrl + "/Login/Negotiate.ashx",
                    authenticationTicket = Request.Cookies[".ROBLOSECURITY"],
                    message = (string?)null,
                };
            }

            return new
            {
                jobId = (string?)null,
                status = (int)result.status,
                message = "Waiting for server",
            };
        }

        public static long startUserId {get;set;} = 30;
#if DEBUG
        [HttpGetBypass("/game/get-join-script-debug")]
        public async Task<dynamic> GetJoinScriptDebug(long placeId, long userId = 12)
        {
            //startUserId = 12;
            var result = services.gameServer.CreateTicket(startUserId, placeId, GetIP());
            startUserId++;
            return new
            {
                placeLauncher = $"{Configuration.BaseUrl}/placelauncher.ashx?ticket={HttpUtility.UrlEncode(result)}",
                authenticationTicket = result,
            };
        }
#endif

        [HttpGetBypass("game/join.ashx")]
        public async Task<dynamic> JoinGame(string jobId, long placeId)
        {
            GamesService gamesService = new GamesService();
            PlaceEntry uni = (await gamesService.MultiGetPlaceDetails(new[] { placeId })).First();
            string username = userSession!.username;
            long userId = userSession!.userId;
            string membership;
            var membership2 = await services.users.GetUserMembership(userId);
            if (membership2  == null)
            {
                membership = "None";
            }
            else
            {
                membership = (int)membership2!.membershipType == 3 ? "OutrageousBuildersClub" : (int)membership2.membershipType == 2 ? "TurboBuildersClub" : (int)membership2.membershipType == 1 ? "BuildersClub" : "None";

            }
            var userInfo = await services.users.GetUserById(userId);
            var accountAgeDays = DateTime.UtcNow.Subtract(userInfo.created).Days;
            string characterAppearanceUrl = $"{Configuration.BaseUrl}/Asset/CharacterFetch.ashx?placeId={placeId}&userId={userId}";
            DateTime currentUtcDateTime = DateTime.UtcNow;
            string formattedDateTime = currentUtcDateTime.ToString("M/d/yyyy h:mm:ss tt");

            string cticket = $"{userId}\n{jobId}\n{formattedDateTime}";
            string ticketSignature = SignatureController.SignStringResponseForClientFromPrivateKey(cticket);
            
            string ticket2 = $"{userId}\n{username}\n{characterAppearanceUrl}\n{jobId}\n{formattedDateTime}";
            string ticketSignature2 = SignatureController.SignStringResponseForClientFromPrivateKey(ticket2);
            string finalTicket = $"{formattedDateTime};{ticketSignature2};{ticketSignature}";
            FeatureFlags.FeatureCheck(FeatureFlag.GamesEnabled, FeatureFlag.GameJoinEnabled);

            dynamic joinScript = new
            {
                ClientPort = 0,
                MachineAddress = "75.162.0.5",
                ServerPort = GameServerService.currentGameServerPorts[jobId],
                PingUrl = "",
                PingInterval = 120,
                UserName = username,
                SeleniumTestMode = false,
                UserId = userId,
                SuperSafeChat = false,
                CharacterAppearance =
                    $"{Configuration.BaseUrl}/Asset/CharacterFetch.ashx?placeId={placeId}&userId={userId}",
                ClientTicket = finalTicket,
                GameId = jobId,
                PlaceId = placeId,
                MeasurementUrl = "",
                WaitingForCharacterGuid = Guid.NewGuid().ToString(),
                BaseUrl = Configuration.BaseUrl,
                ChatStyle = "ClassicAndBubble",
                VendorId = 0,
                ScreenShotInfo = "",
                VideoInfo = "",
                CreatorId = uni.builderId,
                CreatorTypeEnum = "User",
                MembershipType = membership,
                AccountAge = accountAgeDays,
                CookieStoreFirstTimePlayKey = "rbx_evt_ftp",
                CookieStoreFiveMinutePlayKey = "rbx_evt_fmp",
                CookieStoreEnabled = true,
                IsRobloxPlace = uni.builderId == 1,
                GenerateTeleportJoin = false,
                IsUnknownOrUnder13 = false,
                SessionId = "",
                DataCenterId = 0,
                UniverseId = 0,
                BrowserTrackerId = 0,
                UsePortraitMode = false,
                FollowUserId = 0
            };
            Console.WriteLine("hi");
            return SignatureController.SignJsonResponseForClientFromPrivateKey(joinScript);
        }

        [HttpGetBypass("Asset/CharacterFetch.ashx")]
        public async Task<string> CharacterFetch(long userId)
        {
            var assets = await services.avatar.GetWornAssets(userId);
            return
                $"{Configuration.BaseUrl}/Asset/BodyColors.ashx?userId={userId};{string.Join(";", assets.Select(c => Configuration.BaseUrl + "/Asset/?id=" + c))}";
        }

        private void CheckServerAuth(string auth)
        {
            if (auth != Configuration.GameServerAuthorization)
            {
                Roblox.Metrics.GameMetrics.ReportRccAuthorizationFailure(HttpContext.Request.GetEncodedUrl(),
                    auth, GetRequesterIpRaw(HttpContext));
                throw new BadRequestException();
            }
        }

        [HttpPostBypass("/gs/activity")]
        public async Task<dynamic> GetGsActivity([Required, MVC.FromBody] ReportActivity request)
        {
            Console.WriteLine(request.authorization);

            CheckServerAuth(request.authorization);
            var result = await services.gameServer.GetLastServerPing(request.serverId);
            return new
            {
                isAlive = result >= DateTime.UtcNow.Subtract(TimeSpan.FromMinutes(1)),
                updatedAt = result,
            };
        }

        [HttpPostBypass("/gs/ping")]
        public async Task ReportServerActivity([Required, MVC.FromBody] ReportActivity request)
        {
            CheckServerAuth(request.authorization);
            await services.gameServer.SetServerPing(request.serverId);
        }

        [HttpPostBypass("/gs/delete")]
        public async Task DeleteServer([Required, MVC.FromBody] ReportActivity request)
        {
            CheckServerAuth(request.authorization);
            await services.gameServer.DeleteGameServer(request.serverId);
        }

        [HttpPostBypass("/gs/shutdown")]
        public void ShutDownServer([Required, MVC.FromBody] ReportActivity request)
        {
            CheckServerAuth(request.authorization);
            services.gameServer.ShutDownServer(request.serverId);
        }

        [HttpPostBypass("/gs/players/report")]
        public async Task ReportPlayerActivity([Required, MVC.FromBody] ReportPlayerActivity request)
        {
            CheckServerAuth(request.authorization);
            if (request.eventType == "Leave")
            {
                await services.gameServer.OnPlayerLeave(request.userId, request.placeId, request.serverId);
            }
            else if (request.eventType == "Join")
            {
                await Roblox.Metrics.GameMetrics.ReportGameJoinSuccess(request.placeId);
                await services.gameServer.OnPlayerJoin(request.userId, request.placeId, request.serverId);
            }
            else
            {
                throw new Exception("Unexpected type " + request.eventType);
            }
        }

        [HttpPostBypass("/gs/a")]
        public void ReportGS()
        {
            // Doesn't do anything yet. See: services/api/src/controllers/bypass.ts:1473
            return;
        }

        [HttpPostBypass("/Game/ValidateTicket.ashx")]
        public async Task<string> ValidateClientTicketRcc([Required, MVC.FromBody] ValidateTicketRequest request)
        {
#if DEBUG
            return "true";
#endif
            
            try
            {
                // Below is intentionally caught by local try/catch. RCC could crash if we give a 500 error.
                FeatureFlags.FeatureCheck(FeatureFlag.GamesEnabled, FeatureFlag.GameJoinEnabled);
                var ticketData = services.gameServer.DecodeTicket(request.ticket, null);
                if (ticketData.userId != request.expectedUserId)
                {
                    // Either bug or someone broke into RCC
                    Roblox.Metrics.GameMetrics.ReportTicketErrorUserIdNotMatchingTicket(request.ticket,
                        ticketData.userId, request.expectedUserId);
                    throw new Exception("Ticket userId does not match expected userId");
                }
                // From TS: it is possible for a client to spoof username or appearance to be empty string, 
                // so make sure you don't do much validation on those params (aside from assertion that it's a string)
                if (request.expectedUsername != null)
                {
                    var userInfo = await services.users.GetUserById(ticketData.userId);
                    if (userInfo.username != request.expectedUsername)
                    {
                        throw new Exception("Ticket username does not match expected username");
                    }
                }

                if (request.expectedAppearanceUrl != null)
                {
                    // will always be format of "http://localhost/Asset/CharacterFetch.ashx?userId=12", NO EXCEPTIONS!
                    var expectedUrl =
                        $"{Roblox.Configuration.BaseUrl}/Asset/CharacterFetch.ashx?userId={ticketData.userId}";
                    if (request.expectedAppearanceUrl != expectedUrl)
                    {
                        throw new Exception("Character URL is bad");
                    }
                }
                
                // Confirm user isn't already in a game
                var gameStatus = (await services.users.MultiGetPresence(new [] {ticketData.userId})).First();
                if (gameStatus.placeId != null && gameStatus.userPresenceType == PresenceType.InGame)
                {
                    // Make sure that the only game they are playing is the one they are trying to join.
                    var playingGames = await services.gameServer.GetGamesUserIsPlaying(ticketData.userId);
                    foreach (var game in playingGames)
                    {
                        if (game.id != request.gameJobId)
                            throw new Exception("User is already playing another game");
                    }
                }

                return "true";
            }
            catch (Exception e)
            {
                Console.WriteLine("[error] Verify ticket failed. Error = {0}\n{1}", e.Message, e.StackTrace);
                return "false";
            }
        }

        [HttpPostBypass("/game/validate-machine")]
        public dynamic ValidateMachine()
        {
            return new
            {
                success = true,
                message = "",
            };
        }

        [HttpGetBypass("Users/ListStaff.ashx")]
        public async Task<IEnumerable<long>> GetStaffList()
        {
            return (await StaffFilter.GetStaff()).Where(c => c != 12);
        }

        [HttpGetBypass("Users/GetBanStatus.ashx")]
        public async Task<IEnumerable<dynamic>> MultiGetBanStatus(string userIds)
        {

            var ids = userIds.Split(",").Select(long.Parse).Distinct();
            var result = new List<dynamic>();
#if DEBUG
            return ids.Select(c => new
            {
                userId = c,
                isBanned = false,
            });
#else
            var multiGetResult = await services.users.MultiGetAccountStatus(ids);
            foreach (var user in multiGetResult)
            {
                result.Add(new
                {
                    userId = user.userId,
                    isBanned = user.accountStatus != AccountStatus.Ok,
                });
            }

            return result;
#endif
        }

        [HttpGetBypass("Asset/BodyColors.ashx")]
        public async Task<string> GetBodyColors(long userId)
        {
            var colors = await services.avatar.GetAvatar(userId);

            var xsi = XNamespace.Get("http://www.w3.org/2001/XMLSchema-instance");

            var robloxRoot = new XElement("roblox",
                new XAttribute(XNamespace.Xmlns + "xmime", "http://www.w3.org/2005/05/xmlmime"),
                new XAttribute(XNamespace.Xmlns + "xsi", "http://www.w3.org/2001/XMLSchema-instance"),
                new XAttribute(xsi + "noNamespaceSchemaLocation", "http://www.roblox.com/roblox.xsd"),
                new XAttribute("version", 4)
            );
            robloxRoot.Add(new XElement("External", "null"));
            robloxRoot.Add(new XElement("External", "nil"));
            var items = new XElement("Item", new XAttribute("class", "BodyColors"));
            var properties = new XElement("Properties");
            // set colors
            properties.Add(new XElement("int", new XAttribute("name", "HeadColor"), colors.headColorId.ToString()));
            properties.Add(new XElement("int", new XAttribute("name", "LeftArmColor"), colors.leftArmColorId.ToString()));
            properties.Add(new XElement("int", new XAttribute("name", "LeftLegColor"), colors.leftLegColorId.ToString()));
            properties.Add(new XElement("string", new XAttribute("name", "Name"), "Body Colors"));
            properties.Add(new XElement("int", new XAttribute("name", "RightArmColor"), colors.rightArmColorId.ToString()));
            properties.Add(new XElement("int", new XAttribute("name", "RightLegColor"), colors.rightLegColorId.ToString()));
            properties.Add(new XElement("int", new XAttribute("name", "TorsoColor"), colors.torsoColorId.ToString()));
            properties.Add(new XElement("bool", new XAttribute("name", "archivable"), "true"));
            // add
            items.Add(properties);
            robloxRoot.Add(items);
            // return as string
            return new XDocument(robloxRoot).ToString();
        }

        [MVC.HttpPost("/moderation/filtertext/")]
        public dynamic GetModerationText()
        {
            var text = HttpContext.Request.Form["text"].ToString();
            return new
            {
                data = new
                {
                    white = text,
                    black = text,
                },
            };
        }

        private void ValidateBotAuthorization()
        {
#if DEBUG == false
	        if (Request.Headers["bot-auth"].ToString() != Roblox.Configuration.BotAuthorization)
	        {
		        throw new Exception("Internal");
	        }
#endif
        }

        [HttpGetBypass("botapi/migrate-alltypes")]
        public async Task<dynamic> MigrateAllItemsBot([Required, MVC.FromQuery] string url)
        {
            ValidateBotAuthorization();
            return await MigrateItem.MigrateItemFromRoblox(url, false, null, new List<Type>()
            {
                Type.Image,
                Type.Audio,
                Type.Mesh,
                Type.Lua,
                Type.Model,
                Type.Decal,
                Type.Animation,
                Type.SolidModel,
                Type.MeshPart,
                Type.ClimbAnimation,
                Type.DeathAnimation,
                Type.FallAnimation,
                Type.IdleAnimation,
                Type.JumpAnimation,
                Type.RunAnimation,
                Type.SwimAnimation,
                Type.WalkAnimation,
                Type.PoseAnimation,
            }, default, false);
        }

        [HttpGetBypass("botapi/migrate-clothing")]
        public async Task<dynamic> MigrateClothingBot([Required] string assetId)
        {
            ValidateBotAuthorization();
            return await MigrateItem.MigrateItemFromRoblox(assetId, true, 5, new List<Models.Assets.Type>() { Models.Assets.Type.TeeShirt, Models.Assets.Type.Shirt, Models.Assets.Type.Pants });
        }
        
        [HttpGetBypass("BuildersClub/Upgrade.ashx")]
        public MVC.IActionResult UpgradeNow()
        {
            return new MVC.RedirectResult("/internal/membership");
        }
        
        [HttpGetBypass("GetAllowedMD5Hashes")]
        public MVC.ActionResult<dynamic> AllowedMD5Hashes()
        {
            List<string> allowedList = new List<string>()
            {
                "9430a0ef797805865b4696f4f028ce13"
            };

            return new { data = allowedList };
        }
        
        [HttpGetBypass("GetAllowedSecurityVersions")]
        [HttpGetBypass("GetAllowedSecurityKeys")]
        public MVC.ActionResult<dynamic> AllowedSecurityVersions()
        {
            List<string> allowedList = new List<string>()
            {
                "0.1.0ecspcplayer"
            };

            return new { data = allowedList };
        }
        
        [HttpGetBypass("Setting/QuietGet/{type}")]
        public MVC.ActionResult<dynamic> GetAppSettings(string type)
        {
            try
            {
                string jsonFilePath = Path.Combine(Configuration.JsonDataDirectory, type + ".json");
                string jsonContent = System.IO.File.ReadAllText(jsonFilePath);
                dynamic? clientAppSettingsData = JsonConvert.DeserializeObject<ExpandoObject>(jsonContent);

                return clientAppSettingsData ?? "";
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[RetrieveClientFFlags] Error while retrieving FFlags: {ex.Message}");
                return new { };
            }
        }

        [HttpGetBypass("abusereport/UserProfile"), HttpGetBypass("abusereport/asset"), HttpGetBypass("abusereport/user"), HttpGetBypass("abusereport/users")]
        public MVC.IActionResult ReportAbuseRedirect()
        {
            return new MVC.RedirectResult("/internal/report-abuse");
        }

        [HttpGetBypass("/info/blog")]
        public MVC.IActionResult RedirectToUpdates()
        {
            return new MVC.RedirectResult("/internal/updates");
        }

        [HttpGetBypass("/my/economy-status")]
        public dynamic GetEconomyStatus()
        {
            return new
            {
                isMarketplaceEnabled = true,
                isMarketplaceEnabledForAuthenticatedUser = true,
                isMarketplaceEnabledForUser = true,
                isMarketplaceEnabledForGroup = true,
            };
        }

        [HttpGetBypass("/currency/balance")]
        public async Task<dynamic> GetBalance()
        {
            return await services.economy.GetBalance(CreatorType.User, safeUserSession.userId);
        }

        [HttpGetBypass("/ownership/hasasset")]
        public async Task<string> DoesOwnAsset(long userId, long assetId)
        {
            return (await services.users.GetUserAssets(userId, assetId)).Any() ? "true" : "false";
        }

        [HttpPostBypass("persistence/increment")]
        public async Task<dynamic> IncrementPersistence(long placeId, string key, string type, string scope, string target, int value)
        {
            // increment?placeId=%i&key=%s&type=%s&scope=%s&target=&value=%i
            
            if (!IsRcc())
                throw new RobloxException(400, 0, "BadRequest");
            
            return new
            {
                data = (object?) null,
            };
        }

        [HttpPostBypass("persistence/getSortedValues")]
        public async Task<dynamic> GetSortedPersistenceValues(long placeId, string type, string scope, string key, int pageSize, bool ascending, int inclusiveMinValue = 0, int inclusiveMaxValue = 0)
        {
            // persistence/getSortedValues?placeId=0&type=sorted&scope=global&key=Level%5FHighscores20&pageSize=10&ascending=False"
            // persistence/set?placeId=124921244&key=BF2%5Fds%5Ftest&&type=standard&scope=global&target=BF2%5Fds%5Fkey%5Ftmp&valueLength=31
            
            if (!IsRcc())
                throw new RobloxException(400, 0, "BadRequest");
            
            return new
            {
                data = new
                {
                    Entries = ArraySegment<int>.Empty,
                    ExclusiveStartKey = (string?)null,
                },
            };
        }

        [HttpPostBypass("persistence/getv2")]
        public async Task<dynamic> GetPersistenceV2(long placeId, string type, string scope)
        {
            var rawBody = await new StreamReader(Request.Body).ReadToEndAsync();
            if (rawBody.StartsWith("&"))
            {
                rawBody = rawBody.Substring(1);
            }
            // getV2?placeId=%i&type=%s&scope=%s
            // Expected format is:
            //	{ "data" : 
            //		[
            //			{	"Value" : value,
            //				"Scope" : scope,							
            //				"Key" : key,
            //				"Target" : target
            //			}
            //		]
            //	}
            // or for non-existing key:
            // { "data": [] }
            
            // for no sub key:
            // Expected format is:
            //	{ "data" : value }
            Console.WriteLine("Request = {0}", rawBody);
            using var ds = ServiceProvider.GetOrCreate<DataStoreService>();
            var requests = rawBody.Split("\n").Where(c => !string.IsNullOrWhiteSpace(c)).Distinct();
            
            var result = new List<GetKeyEntry>();
            foreach (var request in requests)
            {
                var des = JsonSerializer.Deserialize<GetKeyScope>(request);
                
                var res = await ds.Get(placeId, type, des.scope ?? scope, des.key, des.target);
                if (!string.IsNullOrWhiteSpace(res))
                    result.Add(new GetKeyEntry()
                    {
                        Key = des.key,
                        Scope = des.scope ?? scope,
                        Target =des.target,
                        Value = res,
                    });
            }

            if (!IsRcc())
                throw new RobloxException(400, 0, "BadRequest");
            
            return new
            {
                data = result,
            };
        }

        [HttpPostBypass("persistence/set")]
        public async Task<dynamic> Set(long placeId, string key, string type, string scope, string target, int valueLength, [Required, MVC.FromBody] SetRequest request)
        {
            // { "data" : value }
            if (!IsRcc())
                throw new RobloxException(400, 0, "BadRequest");
            await ServiceProvider.GetOrCreate<DataStoreService>()
                .Set(placeId, target, type, scope, key, valueLength, request.data);
            
            return new
            {
                data = request.data,
            };
        }

#if DEBUG
        [HttpGetBypass("integration-test/create-account-and-set-cookie")]
        public async Task<string> CreateAccountAndSetCookie()
        {
            var name = Guid.NewGuid().ToString().Replace("-", "").Substring(0, 14);
            var result = await services.users.CreateUser(name, "AmogusDrip69", Gender.Male);
            await services.users.InsertOrUpdateMembership(result.userId, MembershipType.BuildersClub);
            var id = await services.users.CreateApplication(new CreateUserApplicationRequest()
            {
                about = "Integration test",
                socialPresence = "",
                isVerified = true,
                verifiedUrl = "https://economysimulator.com/",
                verificationPhrase = "Integration test",
                verifiedId = "1",
            });
            var joinId = await services.users.ProcessApplication(id, 1, UserApplicationStatus.Approved);
            await services.users.SetApplicationUserIdByJoinId(joinId, result.userId);
            
            var sess = await services.users.CreateSession(result.userId);
            var sessionCookie = Roblox.Website.Middleware.SessionMiddleware.CreateJwt(new Middleware.JwtEntry()
            {
                sessionId = sess,
                createdAt = DateTimeOffset.Now.ToUnixTimeSeconds(),
            });
            Response.Cookies.Append(SessionMiddleware.CookieName, sessionCookie, new CookieOptions()
            {
                HttpOnly = true,
                Secure = true,
                SameSite = SameSiteMode.Lax,
                IsEssential = true,
                Expires = DateTimeOffset.Now.AddDays(1),
                Path = "/",
            });
            return "Created user " + name + "...\nOK";
        }
#endif
    }
}

