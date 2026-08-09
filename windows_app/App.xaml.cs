using Microsoft.UI.Xaml;
using Microsoft.Windows.AppNotifications;

namespace windows_app
{
    public partial class App : Application
    {
        public static MainWindow? MainWindowInstance { get; private set; }

        public App()
        {
            InitializeComponent();
        }

        protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
        {
            // Initialize Toast Notification Manager
            AppNotificationManager.Default.NotificationInvoked += OnNotificationInvoked;
            AppNotificationManager.Default.Register();

            MainWindowInstance = new MainWindow();
            MainWindowInstance.Activate();
        }

        private void OnNotificationInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
        {
            // Handle notification clicks here
        }
    }
}
