using Microsoft.AspNetCore.Mvc;
using System.Security.Cryptography;
using System.Text;
using Newtonsoft.Json;

namespace Roblox.Website.Controllers.Internal
{
    public class SignatureController : ControllerBase
    {
        private static RSACryptoServiceProvider? _rsaCsp;
        private static SHA1? _shaCsp;
        
        public static void Setup()
        {
            try
            {
                byte[] privateKeyBlob = Convert.FromBase64String(System.IO.File.ReadAllText("PrivateKeyBlob.txt"));
                
                _shaCsp = SHA1.Create();
                _rsaCsp = new RSACryptoServiceProvider();
                
                _rsaCsp.ImportCspBlob(privateKeyBlob);
            }
            catch (Exception ex)
            {
                throw new Exception("Error setting up SignatureController: " + ex.Message);
            }
        }

        public static string SignJsonResponseForClientFromPrivateKey(dynamic JSONToSign)
        {
            string format = "--rbxsig%{0}%{1}";

            string json = JsonConvert.SerializeObject(JSONToSign);
            string script = Environment.NewLine + json;
            byte[] signature = _rsaCsp!.SignData(Encoding.Default.GetBytes(script), _shaCsp!);

            return String.Format(format, Convert.ToBase64String(signature), script);
        }

        public static string SignStringResponseForClientFromPrivateKey(string stringToSign, bool bUseRbxSig = false)
        {
            if (bUseRbxSig)
            {
                string format = "--rbxsig%{0}%{1}";

                byte[] signature = _rsaCsp!.SignData(Encoding.Default.GetBytes(stringToSign), _shaCsp!);
                string script = Environment.NewLine + stringToSign;

                return String.Format(format, Convert.ToBase64String(signature), script);
            }
            else
            {
                byte[] signature = _rsaCsp!.SignData(Encoding.Default.GetBytes(stringToSign), _shaCsp!);
                return Convert.ToBase64String(signature);
            }
        }
    }
}