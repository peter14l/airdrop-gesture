using System;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Makaretu.Dns;
using Windows.ApplicationModel.DataTransfer;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace windows_app
{
    public class WebSocketListenerService
    {
        private HttpListener? _listener;
        private CancellationTokenSource? _cts;
        private readonly Action<string> _onLogReceived;

        private MulticastService? _mdns;
        private ServiceDiscovery? _sd;
        private ServiceProfile? _serviceProfile;

        private const string MdnsServiceType = "_airdropgesture._tcp";
        private const int Port = 8080;

        public WebSocketListenerService(Action<string> onLogReceived)
        {
            _onLogReceived = onLogReceived;
        }

        public void Start(int port = Port)
        {
            _cts = new CancellationTokenSource();
            _listener = new HttpListener();

            // Bind to all interfaces so Android on the same WiFi can connect.
            // Requires the URL reservation: netsh http add urlacl url=http://+:8080/ user=Everyone
            // For packaged apps with runFullTrust capability this is auto-granted.
            _listener.Prefixes.Add($"http://+:{port}/");

            try
            {
                _listener.Start();
                var localIp = GetLocalIpAddress();
                _onLogReceived($"WebSocket Listener started on ws://{localIp}:{port}/");
                Task.Run(() => ListenLoopAsync(_cts.Token));
                AdvertiseMdns(port);
            }
            catch (HttpListenerException ex) when (ex.ErrorCode == 5) // Access Denied
            {
                // Fall back to localhost-only if wildcard registration fails
                _listener = new HttpListener();
                _listener.Prefixes.Add($"http://localhost:{port}/");
                _listener.Start();
                _onLogReceived($"[Warning] Could not bind to all interfaces. Listening on localhost only.");
                Task.Run(() => ListenLoopAsync(_cts.Token));
            }
            catch (Exception ex)
            {
                _onLogReceived($"Error starting HTTP listener: {ex.Message}");
            }
        }

        public void Stop()
        {
            _cts?.Cancel();
            _listener?.Stop();
            _listener?.Close();

            try
            {
                if (_serviceProfile != null) _sd?.Unadvertise(_serviceProfile);
                _sd?.Dispose();
                _mdns?.Stop();
            }
            catch { /* ignore cleanup errors */ }

            _onLogReceived("WebSocket Listener service stopped.");
        }

        private void AdvertiseMdns(int port)
        {
            try
            {
                _mdns = new MulticastService();
                _sd = new ServiceDiscovery(_mdns);

                _serviceProfile = new ServiceProfile("AirDropGesture", MdnsServiceType, (ushort)port);
                _serviceProfile.AddProperty("version", "1");

                _sd.Advertise(_serviceProfile);
                _mdns.Start();
                _onLogReceived($"mDNS: advertising {MdnsServiceType} on port {port}");
            }
            catch (Exception ex)
            {
                _onLogReceived($"mDNS advertisement failed: {ex.Message}");
            }
        }

        private static string GetLocalIpAddress()
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var addr in ni.GetIPProperties().UnicastAddresses)
                {
                    if (addr.Address.AddressFamily == AddressFamily.InterNetwork)
                        return addr.Address.ToString();
                }
            }
            return "localhost";
        }

        private async Task ListenLoopAsync(CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                try
                {
                    var context = await _listener!.GetContextAsync();
                    if (context.Request.IsWebSocketRequest)
                    {
                        _onLogReceived($"Incoming WebSocket connection from {context.Request.RemoteEndPoint}...");
                        var wsContext = await context.AcceptWebSocketAsync(subProtocol: null);
                        _onLogReceived("WebSocket connection established!");
                        _ = Task.Run(() => HandleConnectionAsync(wsContext.WebSocket, token));
                    }
                    else
                    {
                        context.Response.StatusCode = 400;
                        context.Response.Close();
                    }
                }
                catch (Exception ex) when (!(ex is HttpListenerException || ex is TaskCanceledException))
                {
                    _onLogReceived($"Error in listen loop: {ex.Message}");
                }
            }
        }

        private async Task HandleConnectionAsync(WebSocket socket, CancellationToken token)
        {
            var buffer = new byte[8192];
            try
            {
                while (socket.State == WebSocketState.Open && !token.IsCancellationRequested)
                {
                    var result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), token);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closed by client", token);
                        _onLogReceived("WebSocket connection closed by client.");
                        break;
                    }

                    if (result.MessageType == WebSocketMessageType.Text)
                    {
                        var jsonString = Encoding.UTF8.GetString(buffer, 0, result.Count);
                        ProcessPayload(jsonString);
                    }
                }
            }
            catch (Exception ex)
            {
                _onLogReceived($"Connection error: {ex.Message}");
            }
            finally
            {
                socket.Dispose();
            }
        }

        public static string? LastReceivedPayload { get; set; }

        public static void PasteCachedPayload(Action<string> logCallback)
        {
            if (string.IsNullOrEmpty(LastReceivedPayload))
            {
                logCallback("No payload cached. Grab something on Android first.");
                return;
            }

            App.MainWindowInstance?.DispatcherQueue.TryEnqueue(() =>
            {
                try
                {
                    var dataPackage = new DataPackage();
                    dataPackage.SetText(LastReceivedPayload);
                    Clipboard.SetContent(dataPackage);
                    Clipboard.Flush();
                    logCallback($"[Local Gesture] Clipboard synced! Pasted: {LastReceivedPayload}");

                    // Clear the cache after drop to prevent double paste
                    LastReceivedPayload = null;

                    // Trigger toast notification
                    var toastXml = new AppNotificationBuilder()
                        .AddText("AirDrop Sync Complete")
                        .AddText("Payload dropped and pasted to system clipboard via gesture.")
                        .BuildNotification();
                    AppNotificationManager.Default.Show(toastXml);
                }
                catch (Exception ex)
                {
                    logCallback($"Clipboard error: {ex.Message}");
                }
            });
        }

        private void ProcessPayload(string jsonString)
        {
            try
            {
                using var doc = JsonDocument.Parse(jsonString);
                var root = doc.RootElement;
                var type = root.GetProperty("type").GetString();
                var content = root.GetProperty("content").GetString();

                _onLogReceived($"Received payload type [{type}]: {content}");

                if (type == "text" && !string.IsNullOrEmpty(content))
                {
                    LastReceivedPayload = content;
                    _onLogReceived("Payload cached! Open your palm in front of the laptop camera to paste it.");
                }
            }
            catch (Exception ex)
            {
                _onLogReceived($"Error processing payload JSON: {ex.Message}");
            }
        }

        private void ShowToastNotification(string title, string body)
        {
            try
            {
                var toastXml = new AppNotificationBuilder()
                    .AddText(title)
                    .AddText(body)
                    .BuildNotification();

                AppNotificationManager.Default.Show(toastXml);
            }
            catch (Exception ex)
            {
                _onLogReceived($"Failed to trigger toast notification: {ex.Message}");
            }
        }
    }
}
