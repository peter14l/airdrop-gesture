using System;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Media.Capture;
using Windows.Media.Capture.Frames;
using Windows.Graphics.Imaging;
using Windows.Media.MediaProperties;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI;

namespace windows_app
{
    public sealed partial class MainPage : Page
    {
        private readonly StringBuilder _logBuilder = new();
        private MediaCapture? _mediaCapture;
        private MediaFrameReader? _frameReader;
        private SoftwareBitmapSource? _previewSource;

        // Simple motion/gesture variables
        private double _baselineBrightness = -1;
        private int _dropGestureFrames = 0;
        private const int DropGestureThresholdFrames = 15; // ~1 second of video frames covering the camera
        private bool _isGestureActive = false;

        public MainPage()
        {
            InitializeComponent();
        }

        private System.Collections.Generic.List<MediaFrameSourceGroup> _deviceList = new();
        private bool _isInitializingCamera = false;

        protected override async void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            
            if (App.MainWindowInstance != null)
            {
                App.MainWindowInstance.OnLogAdded = AddLogMessage;
            }

            _previewSource = new SoftwareBitmapSource();
            CameraPreviewImage.Source = _previewSource;

            // Load and populate camera selector list
            await PopulateCameraListAsync();
        }

        private async Task PopulateCameraListAsync()
        {
            try
            {
                var groups = await MediaFrameSourceGroup.FindAllAsync();
                _deviceList = groups.Where(g => g.SourceInfos.Any(s => s.MediaStreamType == MediaStreamType.VideoPreview || s.MediaStreamType == MediaStreamType.VideoRecord)).ToList();

                CameraSelectorComboBox.SelectionChanged -= CameraSelectorComboBox_SelectionChanged;
                CameraSelectorComboBox.Items.Clear();

                if (_deviceList.Count == 0)
                {
                    AddLogMessage("No webcams found on this system.");
                    CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
                    return;
                }

                foreach (var device in _deviceList)
                {
                    CameraSelectorComboBox.Items.Add(device.DisplayName);
                }

                CameraSelectorComboBox.SelectionChanged += CameraSelectorComboBox_SelectionChanged;

                // Auto-select the first camera (which is normally the integrated one)
                CameraSelectorComboBox.SelectedIndex = 0;
            }
            catch (Exception ex)
            {
                AddLogMessage($"Failed to query camera devices: {ex.Message}");
            }
        }

        private async void CameraSelectorComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            int index = CameraSelectorComboBox.SelectedIndex;
            if (index >= 0 && index < _deviceList.Count)
            {
                await InitializeCameraAsync(_deviceList[index]);
            }
        }

        private async Task CleanupCameraAsync()
        {
            if (_frameReader != null)
            {
                _frameReader.FrameArrived -= OnFrameArrived;
                try
                {
                    await _frameReader.StopAsync();
                }
                catch { }
                _frameReader.Dispose();
                _frameReader = null;
            }

            if (_mediaCapture != null)
            {
                _mediaCapture.Dispose();
                _mediaCapture = null;
            }

            CameraPreviewImage.Source = null;
            _previewSource = new SoftwareBitmapSource();
            CameraPreviewImage.Source = _previewSource;
            _baselineBrightness = -1;
        }

        private async Task InitializeCameraAsync(MediaFrameSourceGroup selectedGroup)
        {
            if (_isInitializingCamera) return;
            _isInitializingCamera = true;

            try
            {
                CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
                await CleanupCameraAsync();

                _mediaCapture = new MediaCapture();
                var settings = new MediaCaptureInitializationSettings
                {
                    SourceGroup = selectedGroup,
                    SharingMode = MediaCaptureSharingMode.ExclusiveControl,
                    MemoryPreference = MediaCaptureMemoryPreference.Cpu,
                    StreamingCaptureMode = StreamingCaptureMode.Video
                };

                await _mediaCapture.InitializeAsync(settings);
                AddLogMessage($"Initializing: {selectedGroup.DisplayName}");

                // Bind hardware preview stream directly to MediaPlayerElement
                var mediaSource = Windows.Media.Core.MediaSource.CreateFromMediaFrameSourceGroup(selectedGroup);
                var mediaPlayer = new Windows.Media.Playback.MediaPlayer
                {
                    Source = mediaSource,
                    AutoPlay = true,
                    IsMuted = true
                };
                CameraPreviewPlayer.SetMediaPlayer(mediaPlayer);

                // Find a suitable video preview source for real-time background gesture processing
                var sourceInfo = selectedGroup.SourceInfos.FirstOrDefault(s => s.MediaStreamType == MediaStreamType.VideoPreview) 
                                 ?? selectedGroup.SourceInfos.FirstOrDefault(s => s.MediaStreamType == MediaStreamType.VideoRecord)
                                 ?? selectedGroup.SourceInfos.FirstOrDefault();

                if (sourceInfo != null && _mediaCapture.FrameSources.ContainsKey(sourceInfo.Id))
                {
                    var frameSource = _mediaCapture.FrameSources[sourceInfo.Id];
                    _frameReader = await _mediaCapture.CreateFrameReaderAsync(frameSource, MediaEncodingSubtypes.Bgra8);
                    _frameReader.FrameArrived += OnFrameArrived;
                    var status = await _frameReader.StartAsync();

                    CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
                    AddLogMessage($"Active Camera Source: {selectedGroup.DisplayName} (Streaming Live)");
                }
                else
                {
                    CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
                    AddLogMessage($"Active Camera Source: {selectedGroup.DisplayName} (Direct Preview)");
                }
            }
            catch (Exception ex)
            {
                AddLogMessage($"Failed to start camera {selectedGroup.DisplayName}: {ex.Message}");
                CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
            }
            finally
            {
                _isInitializingCamera = false;
            }
        }

        private void OnFrameArrived(MediaFrameReader sender, MediaFrameArrivedEventArgs args)
        {
            using (var frameReference = sender.TryAcquireLatestFrame())
            {
                var videoFrame = frameReference?.VideoMediaFrame;
                var softwareBitmap = videoFrame?.SoftwareBitmap;

                if (softwareBitmap != null)
                {
                    // Ensure the bitmap format is compatible for rendering
                    if (softwareBitmap.BitmapPixelFormat != BitmapPixelFormat.Bgra8 ||
                        softwareBitmap.BitmapAlphaMode != BitmapAlphaMode.Premultiplied)
                    {
                        var converted = SoftwareBitmap.Convert(softwareBitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
                        softwareBitmap.Dispose();
                        softwareBitmap = converted;
                    }

                    // Run the custom light-level structural detector to verify if a hand is covering the lens (Drop gesture)
                    ProcessGestureAnalysis(softwareBitmap);

                    // Clone the bitmap for safe asynchronous rendering on the UI thread
                    var renderCopy = SoftwareBitmap.Copy(softwareBitmap);

                    // Render preview to screen
                    DispatcherQueue.TryEnqueue(async () =>
                    {
                        try
                        {
                            await _previewSource!.SetBitmapAsync(renderCopy);
                        }
                        catch
                        {
                            // Ignore rendering errors on app close
                        }
                        finally
                        {
                            renderCopy.Dispose();
                        }
                    });
                }
            }
        }

        private void ProcessGestureAnalysis(SoftwareBitmap bitmap)
        {
            // Lock and read raw bytes
            int width = bitmap.PixelWidth;
            int height = bitmap.PixelHeight;

            unsafe
            {
                using (var buffer = bitmap.LockBuffer(BitmapBufferAccessMode.Read))
                using (var reference = buffer.CreateReference())
                {
                    byte* data;
                    uint capacity;
                    ((IMemoryBufferByteAccess)reference).GetBuffer(out data, out capacity);

                    // Sample a small grid to calculate average brightness
                    double totalBrightness = 0;
                    int samplePoints = 0;

                    for (int y = 0; y < height; y += 16) // step 16 pixels
                    {
                        for (int x = 0; x < width; x += 16)
                        {
                            int index = (y * width + x) * 4; // BGRA format
                            if (index + 2 < capacity)
                            {
                                byte b = data[index];
                                byte g = data[index + 1];
                                byte r = data[index + 2];
                                // Standard luminance weights
                                double luminance = 0.299 * r + 0.587 * g + 0.114 * b;
                                totalBrightness += luminance;
                                samplePoints++;
                            }
                        }
                    }

                    double averageBrightness = samplePoints > 0 ? totalBrightness / samplePoints : 0;

                    if (_baselineBrightness < 0)
                    {
                        _baselineBrightness = averageBrightness;
                        return;
                    }

                    // Slowly adjust baseline brightness to room lighting changes
                    _baselineBrightness = (_baselineBrightness * 0.99) + (averageBrightness * 0.01);

                    // If average brightness drops significantly (>35%), a hand is covering the camera (open palm push close to lens)
                    bool isCovered = averageBrightness < (_baselineBrightness * 0.65);

                    if (isCovered)
                    {
                        _dropGestureFrames++;
                        if (_dropGestureFrames >= DropGestureThresholdFrames) // Held steady for threshold frames
                        {
                            if (!_isGestureActive)
                            {
                                _isGestureActive = true;
                                DispatcherQueue.TryEnqueue(() =>
                                {
                                    TriggerLocalDropAction();
                                });
                            }
                        }
                    }
                    else
                    {
                        _dropGestureFrames = 0;
                        _isGestureActive = false;
                        DispatcherQueue.TryEnqueue(() =>
                        {
                            GestureStatusBadge.Background = null;
                            GestureStatusText.Text = "Waiting for drop gesture...";
                        });
                    }
                }
            }
        }

        private void TriggerLocalDropAction()
        {
            GestureStatusBadge.Background = new SolidColorBrush(Colors.Green);
            GestureStatusText.Text = "Gesture DETECTED: Dropping clipboard!";
            
            AddLogMessage("Drop gesture detected on laptop webcam. Pasting payload...");

            // Trigger the clipboard write
            WebSocketListenerService.PasteCachedPayload(AddLogMessage);
        }

        private void AddLogMessage(string message)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                _logBuilder.AppendLine($"[{DateTime.Now:HH:mm:ss}] {message}");
                LogTextBox.Text = _logBuilder.ToString();
                LogScrollViewer.ChangeView(null, LogScrollViewer.ScrollableHeight, null);
            });
        }

        private void OpenFolderButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
        {
            OpenAirDropFolder();
        }

        public static void OpenAirDropFolder()
        {
            try
            {
                var folder = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    "Downloads",
                    "AirDrop"
                );
                System.IO.Directory.CreateDirectory(folder);
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
                {
                    FileName = folder,
                    UseShellExecute = true
                });
            }
            catch { }
        }
    }

    // Interop helper interface for raw buffer memory access
    [System.Runtime.InteropServices.ComImport]
    [System.Runtime.InteropServices.Guid("5B0D3235-4DB8-4D14-BB10-EC590A5D024C")]
    [System.Runtime.InteropServices.InterfaceType(System.Runtime.InteropServices.ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMemoryBufferByteAccess
    {
        unsafe void GetBuffer(out byte* buffer, out uint capacity);
    }
}
