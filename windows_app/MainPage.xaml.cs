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

        protected override async void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            
            if (App.MainWindowInstance != null)
            {
                App.MainWindowInstance.OnLogAdded = AddLogMessage;
            }

            _previewSource = new SoftwareBitmapSource();
            CameraPreviewImage.Source = _previewSource;

            // Start webcam preview and tracking
            await InitializeCameraAsync();
        }

        private async Task InitializeCameraAsync()
        {
            try
            {
                var frameSourceGroups = await MediaFrameSourceGroup.FindAllAsync();
                var selectedGroup = frameSourceGroups.FirstOrDefault(g => g.SourceInfos.Any(s => s.MediaStreamType == MediaStreamType.VideoPreview || s.MediaStreamType == MediaStreamType.VideoRecord));

                if (selectedGroup == null)
                {
                    AddLogMessage("No webcam found on this device.");
                    CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
                    return;
                }

                _mediaCapture = new MediaCapture();
                var settings = new MediaCaptureInitializationSettings
                {
                    SourceGroup = selectedGroup,
                    SharingMode = MediaCaptureSharingMode.SharedReadOnly,
                    MemoryPreference = MediaCaptureMemoryPreference.Cpu,
                    StreamingCaptureMode = StreamingCaptureMode.Video
                };

                await _mediaCapture.InitializeAsync(settings);
                AddLogMessage("Camera initialized successfully.");

                // Find a suitable video preview source
                var sourceInfo = selectedGroup.SourceInfos.FirstOrDefault(s => s.MediaStreamType == MediaStreamType.VideoPreview) 
                                 ?? selectedGroup.SourceInfos.FirstOrDefault(s => s.MediaStreamType == MediaStreamType.VideoRecord);

                if (sourceInfo != null)
                {
                    var frameSource = _mediaCapture.FrameSources[sourceInfo.Id];
                    // Request format compatibility for direct conversion
                    _frameReader = await _mediaCapture.CreateFrameReaderAsync(frameSource, MediaEncodingSubtypes.Bgra8);
                    _frameReader.FrameArrived += OnFrameArrived;
                    await _frameReader.StartAsync();

                    CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
                    AddLogMessage("Camera tracking started.");
                }
            }
            catch (Exception ex)
            {
                AddLogMessage($"Camera initialization failed: {ex.Message}");
                CameraFallbackPanel.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
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

                    // Render preview to screen
                    DispatcherQueue.TryEnqueue(async () =>
                    {
                        try
                        {
                            await _previewSource!.SetBitmapAsync(softwareBitmap);
                        }
                        catch
                        {
                            // Ignore rendering errors on app close
                        }
                        finally
                        {
                            softwareBitmap.Dispose();
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
