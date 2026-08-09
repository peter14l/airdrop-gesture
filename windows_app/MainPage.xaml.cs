using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using System.Text;

namespace windows_app
{
    public sealed partial class MainPage : Page
    {
        private readonly StringBuilder _logBuilder = new();

        public MainPage()
        {
            InitializeComponent();
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);
            
            if (App.MainWindowInstance != null)
            {
                App.MainWindowInstance.OnLogAdded = AddLogMessage;
            }
        }

        private void AddLogMessage(string message)
        {
            _logBuilder.AppendLine($"[{System.DateTime.Now:HH:mm:ss}] {message}");
            LogTextBox.Text = _logBuilder.ToString();
            LogScrollViewer.ChangeView(null, LogScrollViewer.ScrollableHeight, null);
        }
    }
}
