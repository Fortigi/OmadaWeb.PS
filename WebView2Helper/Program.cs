using System;
using System.Threading.Tasks;
using System.IO;
using System.Text.Json;
using System.Threading;
using Microsoft.Web.WebView2.Core;
using System.Collections.Generic;
using System.Diagnostics;

namespace OmadaWebView2Helper
{
    /// <summary>
    /// WebView2 Helper Application for OmadaWeb.PS
    /// Provides reliable WebView2 functionality with proper STA threading
    /// </summary>
    class Program
    {
        private static CoreWebView2Environment _environment;
        private static CoreWebView2Controller _controller;
        private static CoreWebView2 _webView;
        private static string _userDataFolder;
        private static bool _isInitialized = false;

        static async Task Main(string[] args)
        {
            try
            {
                // Set STA apartment state for WebView2 compatibility
                Thread.CurrentThread.SetApartmentState(ApartmentState.STA);

                Console.WriteLine(JsonSerializer.Serialize(new { status = "ready", message = "WebView2 Helper started" }));

                // Process commands from stdin
                string line;
                while ((line = Console.ReadLine()) != null)
                {
                    try
                    {
                        var command = JsonSerializer.Deserialize<CommandMessage>(line);
                        var response = await ProcessCommand(command);
                        Console.WriteLine(JsonSerializer.Serialize(response));
                    }
                    catch (Exception ex)
                    {
                        var errorResponse = new ResponseMessage
                        {
                            Success = false,
                            Error = ex.Message,
                            Data = null
                        };
                        Console.WriteLine(JsonSerializer.Serialize(errorResponse));
                    }
                }
            }
            catch (Exception ex)
            {
                var errorResponse = new ResponseMessage
                {
                    Success = false,
                    Error = $"Fatal error: {ex.Message}",
                    Data = null
                };
                Console.WriteLine(JsonSerializer.Serialize(errorResponse));
                Environment.Exit(1);
            }
        }

        private static async Task<ResponseMessage> ProcessCommand(CommandMessage command)
        {
            switch (command.Action.ToLower())
            {
                case "initialize":
                    return await InitializeWebView2(command.Parameters);

                case "navigate":
                    return await Navigate(command.Parameters);

                case "waitfornavigation":
                    return await WaitForNavigation(command.Parameters);

                case "executescript":
                    return await ExecuteScript(command.Parameters);

                case "getcookies":
                    return await GetCookies(command.Parameters);

                case "getpageinfo":
                    return await GetPageInfo();

                case "close":
                    return await CloseWebView2();

                default:
                    return new ResponseMessage
                    {
                        Success = false,
                        Error = $"Unknown action: {command.Action}",
                        Data = null
                    };
            }
        }

        private static async Task<ResponseMessage> InitializeWebView2(Dictionary<string, object> parameters)
        {
            try
            {
                if (_isInitialized)
                {
                    return new ResponseMessage { Success = true, Data = "Already initialized" };
                }

                // Get parameters
                _userDataFolder = parameters.GetValueOrDefault("userDataFolder", Path.Combine(Path.GetTempPath(), "OmadaWebView2Helper")).ToString();
                var inPrivate = parameters.GetValueOrDefault("inPrivate", false).ToString().ToLower() == "true";
                var profile = parameters.GetValueOrDefault("profile", "").ToString();

                if (inPrivate)
                {
                    _userDataFolder = Path.Combine(Path.GetTempPath(), $"OmadaWebView2Helper_InPrivate_{Guid.NewGuid()}");
                }
                else if (!string.IsNullOrEmpty(profile))
                {
                    _userDataFolder = Path.Combine(_userDataFolder, "Profiles", profile);
                }

                Directory.CreateDirectory(_userDataFolder);

                // Create WebView2 environment
                _environment = await CoreWebView2Environment.CreateAsync(null, _userDataFolder);

                // Create a simple window for the controller
                var windowHandle = CreateMessageWindow();

                // Create controller
                _controller = await _environment.CreateCoreWebView2ControllerAsync(windowHandle);
                _webView = _controller.CoreWebView2;

                // Configure settings
                var settings = _webView.Settings;
                settings.IsGeneralAutofillEnabled = true;
                settings.IsPasswordAutosaveEnabled = true;
                settings.AreDefaultScriptDialogsEnabled = true;
                settings.AreDevToolsEnabled = false;
                settings.AreHostObjectsAllowed = false;
                settings.IsScriptEnabled = true;
                settings.IsWebMessageEnabled = false;
                settings.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebView2 OmadaWeb.PS";

                _isInitialized = true;

                return new ResponseMessage
                {
                    Success = true,
                    Data = new
                    {
                        initialized = true,
                        userDataFolder = _userDataFolder,
                        version = _environment.BrowserVersionString
                    }
                };
            }
            catch (Exception ex)
            {
                return new ResponseMessage
                {
                    Success = false,
                    Error = $"Initialization failed: {ex.Message}",
                    Data = null
                };
            }
        }

        private static async Task<ResponseMessage> Navigate(Dictionary<string, object> parameters)
        {
            try
            {
                if (!_isInitialized)
                {
                    return new ResponseMessage { Success = false, Error = "WebView2 not initialized" };
                }

                var url = parameters.GetValueOrDefault("url", "").ToString();
                if (string.IsNullOrEmpty(url))
                {
                    return new ResponseMessage { Success = false, Error = "URL parameter required" };
                }

                _webView.Navigate(url);

                return new ResponseMessage
                {
                    Success = true,
                    Data = new { navigated = true, url = url }
                };
            }
            catch (Exception ex)
            {
                return new ResponseMessage
                {
                    Success = false,
                    Error = $"Navigation failed: {ex.Message}",
                    Data = null
                };
            }
        }

        private static async Task<ResponseMessage> WaitForNavigation(Dictionary<string, object> parameters)
        {
            try
            {
                if (!_isInitialized)
                {
                    return new ResponseMessage { Success = false, Error = "WebView2 not initialized" };
                }

                var timeoutMs = int.Parse(parameters.GetValueOrDefault("timeout", "30000").ToString());
                var tcs = new TaskCompletionSource<bool>();

                EventHandler<CoreWebView2NavigationCompletedEventArgs> handler = null;
                handler = (sender, args) =>
                {
                    _webView.NavigationCompleted -= handler;
                    tcs.SetResult(args.IsSuccess);
                };

                _webView.NavigationCompleted += handler;

                var completed = await Task.WhenAny(tcs.Task, Task.Delay(timeoutMs));

                if (completed == tcs.Task)
                {
                    var success = await tcs.Task;
                    return new ResponseMessage
                    {
                        Success = success,
                        Data = new
                        {
                            navigationCompleted = success,
                            url = _webView.Source,
                            title = _webView.DocumentTitle
                        }
                    };
                }
                else
                {
                    _webView.NavigationCompleted -= handler;
                    return new ResponseMessage { Success = false, Error = "Navigation timeout" };
                }
            }
            catch (Exception ex)
            {
                return new ResponseMessage
                {
                    Success = false,
                    Error = $"Wait for navigation failed: {ex.Message}",
                    Data = null
                };
            }
        }

        private static async Task<ResponseMessage> ExecuteScript(Dictionary<string, object> parameters)
        {
            try
            {
                if (!_isInitialized)
                {
                    return new ResponseMessage { Success = false, Error = "WebView2 not initialized" };
                }

                var script = parameters.GetValueOrDefault("script", "").ToString();
                if (string.IsNullOrEmpty(script))
                {
                    return new ResponseMessage { Success = false, Error = "Script parameter required" };
                }

                var result = await _webView.ExecuteScriptAsync(script);

                return new ResponseMessage
                {
                    Success = true,
                    Data = new { result = result }
                };
            }
            catch (Exception ex)
            {
                return new ResponseMessage
                {
                    Success = false,
                    Error = $"Script execution failed: {ex.Message}",
                    Data = null
                };
            }
        }

        private static async Task<ResponseMessage> GetCookies(Dictionary<string, object> parameters)
        {
            try
            {
                if (!_isInitialized)
                {
                    return new ResponseMessage { Success = false, Error = "WebView2 not initialized" };
                }

                var url = parameters.GetValueOrDefault("url", _webView.Source).ToString();
                var cookies = await _webView.CookieManager.GetCookiesAsync(url);

                var cookieList = new List<object>();
                foreach (var cookie in cookies)
                {
                    cookieList.Add(new
                    {
                        name = cookie.Name,
                        value = cookie.Value,
                        domain = cookie.Domain,
                        path = cookie.Path,
                        expires = cookie.Expires,
                        httpOnly = cookie.IsHttpOnly,
                        secure = cookie.IsSecure,
                        sameSite = cookie.SameSite.ToString()
                    });
                }

                return new ResponseMessage
                {
                    Success = true,
                    Data = new { cookies = cookieList }
                };
            }
            catch (Exception ex)
            {
                return new ResponseMessage
                {
                    Success = false,
                    Error = $"Get cookies failed: {ex.Message}",
                    Data = null
                };
            }
        }

        private static async Task<ResponseMessage> GetPageInfo()
        {
            try
            {
                if (!_isInitialized)
                {
                    return new ResponseMessage { Success = false, Error = "WebView2 not initialized" };
                }

                return new ResponseMessage
                {
                    Success = true,
                    Data = new
                    {
                        url = _webView.Source,
                        title = _webView.DocumentTitle,
                        canGoBack = _webView.CanGoBack,
                        canGoForward = _webView.CanGoForward
                    }
                };
            }
            catch (Exception ex)
            {
                return new ResponseMessage
                {
                    Success = false,
                    Error = $"Get page info failed: {ex.Message}",
                    Data = null
                };
            }
        }

        private static async Task<ResponseMessage> CloseWebView2()
        {
            try
            {
                if (_controller != null)
                {
                    _controller.Close();
                    _controller = null;
                }

                _webView = null;
                _environment = null;
                _isInitialized = false;

                return new ResponseMessage
                {
                    Success = true,
                    Data = new { closed = true }
                };
            }
            catch (Exception ex)
            {
                return new ResponseMessage
                {
                    Success = false,
                    Error = $"Close failed: {ex.Message}",
                    Data = null
                };
            }
        }

        private static IntPtr CreateMessageWindow()
        {
            // Create a simple message-only window
            var process = Process.GetCurrentProcess();
            return process.MainWindowHandle != IntPtr.Zero ? process.MainWindowHandle : (IntPtr)1;
        }
    }

    public class CommandMessage
    {
        public string Action { get; set; }
        public Dictionary<string, object> Parameters { get; set; } = new Dictionary<string, object>();
    }

    public class ResponseMessage
    {
        public bool Success { get; set; }
        public string Error { get; set; }
        public object Data { get; set; }
    }
}