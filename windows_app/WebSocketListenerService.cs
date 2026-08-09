using System;
using System.IO;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
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

        public WebSocketListenerService(Action<string> onLogReceived)
        {
            _onLogReceived = onLogReceived;
        }

        public void Start(int port = 8080)
        {
            _cts = new CancellationTokenSource();
            _listener = new HttpListener();
            _listener.Prefixes.Add($"http://*:{port}/");
            
            try
            {
                _listener.Start();
                _onLogReceived($"WebSocket Listener started on ws://0.0.0.0:{port}/");
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
            _onLogReceived("WebSocket Listener service stopped.");
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
                        _onLogReceived("Incoming WebSocket connection request...");
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
                    // Copy to Windows System Clipboard (Runs on UI Thread context)
                    App.MainWindowInstance?.DispatcherQueue.TryEnqueue(() =>
                    {
                        try
                        {
                            var dataPackage = new DataPackage();
                            dataPackage.SetText(content);
                            Clipboard.SetContent(dataPackage);
                            Clipboard.Flush();
                            _onLogReceived("Copied text payload directly to Windows Clipboard!");
                            ShowToastNotification("Clipboard Synced", "Android payload written to system clipboard.");
                        }
                        catch (Exception ex)
                        {
                            _onLogReceived($"Clipboard error: {ex.Message}");
                        }
                    });
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
