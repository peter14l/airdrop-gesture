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
            // Initialize Toast Notification Manager (Disabled to prevent activation errors without appxmanifest COM registration)
            // AppNotificationManager.Default.NotificationInvoked += OnNotificationInvoked;
            // AppNotificationManager.Default.Register();

            try
            {
                MainWindowInstance = new MainWindow();
                MainWindowInstance.Activate();
            }
            catch (System.Exception ex)
            {
                var logPath = System.IO.Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.Desktop), "airdrop_startup_error.txt");
                System.IO.File.WriteAllText(logPath, ex.ToString());
                throw;
            }
        }

        private void OnNotificationInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
        {
            // Handle notification clicks here
        }
    }
}
