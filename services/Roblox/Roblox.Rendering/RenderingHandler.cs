// 10/31/2023 Halloween Special
// Open Source Replacement for game-server for Economy Simulator Revivals.
// Be sure to check out https://www.fossci.com for an actually good revival. Written by Aep obviously.

using System.Diagnostics;
using System.Text;
using System.Xml.Linq;

namespace Roblox.Rendering
{
    public class RenderingHandler
    {
        private static string BaseUrl = "";
        public static string LuaScriptPath = "";
        public static string RccServicePath = "";
        private static Random RandomComponent = new Random();

        public static void Configure(string baseUrl, string rccPath, string luaScriptPath)
        {
            BaseUrl = baseUrl;
            RccServicePath = rccPath;
            LuaScriptPath = luaScriptPath;
        }
        
        public static async Task<string> SendRequestToRcc(string URL, string XML, string SOAPAction)
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
                        Console.WriteLine($"[RCCSendRequest] Recieved not OK status request: {RccHttpClientPost.StatusCode}, full response: {RccHttpClientResponse}");
                    }
                    XDocument Doc = XDocument.Parse(RccHttpClientResponse);
                    XNamespace ns1 = "http://economysimulator.com/";
                    XElement Element = Doc.Descendants(ns1 + "value").FirstOrDefault()!;
                    string LuaValue = Element.Value ?? "";
                    return LuaValue;
                }
                catch (Exception e)
                {
                    //Console.WriteLine($"[RCCSendRequest] Failed to send request to RCC: {e}");
                }
            }
            return "FAILURE"; // failure
        }
        
        public static async Task<string> RequestHatThumbnail(long assetId, int JobExpiration)
        {
            string assetUrl = $"{BaseUrl}/asset/?id={assetId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.Start();

            string originalScript = File.ReadAllText($"{LuaScriptPath}Hat.lua");
            string finalScript = originalScript.Replace
                ("%assetUrl%", $@"""{assetUrl}""").Replace
                ("%fileExtension%", $@"""png""").Replace
                ("%x%", @"""1680""").Replace
                ("%y%", @"""1680""").Replace
                ("%baseUrl%", $@"""{BaseUrl}/""");
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }
        
        public static async Task<string> RequestMeshThumbnail(long assetId, int JobExpiration)
        {
            string assetUrl = $"{BaseUrl}/asset/?id={assetId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.Start();

            string originalScript = File.ReadAllText($"{LuaScriptPath}Mesh.lua");
            string finalScript = originalScript.Replace
                ("%assetUrl%", $@"""{assetUrl}""").Replace
                ("%fileExtension%", $@"""png""").Replace
                ("%x%", @"""1260""").Replace
                ("%y%", @"""1260""").Replace
                ("%baseUrl%", $@"""{BaseUrl}/""");
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""hhttp://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }
        
        public static async Task<string> RequestImageThumbnail(long assetId, int JobExpiration, bool isFace = false)
        {
            string assetUrl = $"{BaseUrl}/asset/?id={assetId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.Start();

            int x = isFace ? 1680 : 600;
            int y = isFace ? 1680 : 600;

            string originalScript = File.ReadAllText($"{LuaScriptPath}Decal.lua");
            string finalScript = originalScript.Replace
                ("%assetUrl%", $@"""{assetUrl}""").Replace
                ("%fileExtension%", $@"""png""").Replace
                ("%x%", @$"""{x}""").Replace
                ("%y%", @$"""{y}""").Replace
                ("%baseUrl%", $@"""{BaseUrl}/""");
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }
        
        public static async Task<string> RequestPlaceRender(long assetId, int JobExpiration, int x, int y)
        {
            string assetUrl = $"{BaseUrl}/asset/?id={assetId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = true;
            renderRcc.StartInfo.CreateNoWindow = true;
            //renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = false;
            renderRcc.Start();

            string originalScript = File.ReadAllText($"{LuaScriptPath}Place.lua");
            string finalScript = originalScript.Replace
                ("%assetUrl%", $@"""{assetUrl}""").Replace
                ("%fileExtension%", $@"""png""").Replace
                ("%x%", $@"""{x}""").Replace
                ("%y%", $@"""{y}""").Replace
                ("%baseUrl%", $@"""{BaseUrl}/""").Replace
                ("%universeId%", $@"""{assetId}""");
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }
        
        public static async Task<string> RequestClothingRender(long assetId, int JobExpiration)
        {
            string assetUrl = $"{BaseUrl}/asset/?id={assetId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = true;
            renderRcc.StartInfo.CreateNoWindow = true;
            //renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = false;
            renderRcc.Start();

            string originalScript = File.ReadAllText($"{LuaScriptPath}Clothing.lua");
            string finalScript = originalScript.Replace
                ("%assetUrl%", $@"""{assetUrl}""").Replace
                ("%fileExtension%", $@"""png""").Replace
                ("%x%", $@"""{1680}""").Replace
                ("%y%", $@"""{1680}""").Replace
                ("%baseUrl%", $@"""{BaseUrl}/""").Replace
                ("%mannequinId%", $@"""{1785197}""");
            
            Console.WriteLine();
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }

        public static async Task<string> RequestHeadRender(long assetId, int JobExpiration)
        {
            string assetUrl = $"{BaseUrl}/asset/?id={assetId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = true;
            renderRcc.StartInfo.CreateNoWindow = true;
            //renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = false;
            renderRcc.Start();

            string originalScript = File.ReadAllText($"{LuaScriptPath}Head.lua");
            string finalScript = originalScript.Replace
                ("%assetUrl%", $@"""{assetUrl}""").Replace
                ("%fileExtension%", $@"""png""").Replace
                ("%x%", $@"""{1680}""").Replace
                ("%y%", $@"""{1680}""").Replace
                ("%baseUrl%", $@"""{BaseUrl}/""").Replace
                ("%mannequinId%", $@"""{1785197}""");
            
            Console.WriteLine();
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }

        public static async Task<string> RequestPlayerThumbnail(long userId, int JobExpiration)
        {
            string characterAppearanceUrl = $"{BaseUrl}/Asset/CharacterFetch.ashx?userId={userId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.Start();

            string originalScript = File.ReadAllText($"{LuaScriptPath}Avatar.lua");
            string finalScript = originalScript.Replace
                ("%baseUrl%", $@"""{BaseUrl}""").Replace
                ("%characterAppearanceUrl%", $@"""{characterAppearanceUrl}""").Replace
                ("%fileExtension%", @"""png""").Replace
                ("%x%", "720").Replace
                ("%y%", "720");
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }
        
        public static async Task<string> RequestHeadshotThumbnail(long userId, int JobExpiration)
        {
            string characterAppearanceUrl = $"{BaseUrl}/Asset/CharacterFetch.ashx?userId={userId}";
            int RCCPort = RandomComponent.Next(10000, 25000);
            Process renderRcc = new Process();
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.StartInfo.WindowStyle = ProcessWindowStyle.Hidden;
            renderRcc.StartInfo.FileName = $"{RccServicePath}RCCService.exe";
            renderRcc.StartInfo.Arguments = string.Format($@"-console -port {RCCPort}");
            renderRcc.StartInfo.RedirectStandardError = false;
            renderRcc.StartInfo.RedirectStandardOutput = false;
            renderRcc.StartInfo.UseShellExecute = false;
            renderRcc.StartInfo.CreateNoWindow = true;
            renderRcc.Start();

            string originalScript = File.ReadAllText($"{LuaScriptPath}Closeup.lua");
            string finalScript = originalScript.Replace
                ("%baseUrl%", $@"""{BaseUrl}""").Replace
                ("%characterAppearanceUrl%", $@"""{characterAppearanceUrl}""").Replace
                ("%fileExtension%", @"""png""").Replace
                ("%x%", "720").Replace
                ("%y%", "720").Replace
                ("%quadratic%", "true").Replace
                ("%baseHatZoom%", "30").Replace
                ("%maxHatZoom%", "100").Replace
                ("%cameraOffsetX%", "0").Replace
                ("%cameraOffsetY%", "0");
            
            string XML = $@"<?xml version=""1.0"" encoding=""utf-8""?>
            <soap:Envelope xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""
               xmlns:xsd=""http://www.w3.org/2001/XMLSchema""
               xmlns:soap=""http://schemas.xmlsoap.org/soap/envelope/"">
                <soap:Body>
                    <BatchJobEx xmlns=""http://economysimulator.com/"">
                        <job>
                            <id>{Guid.NewGuid().ToString()}</id>
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
                    </BatchJobEx>
                </soap:Body>
            </soap:Envelope>";
            
            string result = await SendRequestToRcc($"http://127.0.0.1:{RCCPort}", XML, "BatchJobEx");
            renderRcc.Kill();
            return result;
        }
    }
}