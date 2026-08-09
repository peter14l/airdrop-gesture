using System;
using Microsoft.UI.Xaml;
using H.NotifyIcon;

namespace windows_app
{
    public sealed partial class MainWindow : Window
    {
        private readonly WebSocketListenerService _service;
        public Action<string>? OnLogAdded;

        public MainWindow()
        {
            InitializeComponent();

            ExtendsContentIntoTitleBar = true;
            SetTitleBar(AppTitleBar);

            AppWindow.SetIcon("Assets/AppIcon.ico");

            // Setup minimize to tray behavior
            AppWindow.Closing += AppWindow_Closing;

            // Start WebSocket server
            _service = new WebSocketListenerService(LogMessage);
            _service.Start();

            // Navigate root frame
            RootFrame.Navigate(typeof(MainPage));
        }

        private void LogMessage(string message)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                OnLogAdded?.Invoke(message);
            });
        }

        private void AppWindow_Closing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
        {
            // Intercept close button and minimize to tray instead
            args.Cancel = true;
            HideWindow();
        }

        private void MyNotifyIcon_DoubleClick(object sender, RoutedEventArgs e)
        {
            ShowWindow();
        }

        private void MenuRestore_Click(object sender, RoutedEventArgs e)
        {
            ShowWindow();
        }

        private void MenuExit_Click(object sender, RoutedEventArgs e)
        {
            _service.Stop();
            MyNotifyIcon.Dispose();
            Application.Current.Exit();
        }

        private void ShowWindow()
        {
            AppWindow.Show();
        }

        private void HideWindow()
        {
            AppWindow.Hide();
        }
    }
}
