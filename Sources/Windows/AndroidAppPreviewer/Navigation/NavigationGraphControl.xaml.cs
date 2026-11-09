using System.Windows;
using System.Windows.Input;
using System.Windows.Controls;

namespace AndroidAppPreviewer {
    public partial class NavigationGraphControl : UserControl {
        public event Action? GraphBackgroundPressed;
        public event Action<object, int>? PathCandidatePressed;

        public NavigationGraphControl() {
            InitializeComponent();
        }

        public Canvas Graph => this.GraphCanvas;

        public ControlTemplate NavigationNodeButtonTemplate => (ControlTemplate)this.FindResource("NavigationNodeButtonTemplate");

        public void SetPathCandidates(IEnumerable<object> pathCandidates) {
            var candidates = pathCandidates.ToArray();
            this.PathCandidates.ItemsSource = candidates;
            this.PathCandidatesPlaceholder.Visibility = candidates.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        private void GraphCanvasMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs) {
            this.GraphBackgroundPressed?.Invoke();
            eventArgs.Handled = true;
        }

        private void PathCardMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs) {
            if (sender is FrameworkElement { DataContext: not null } pathCard) {
                this.PathCandidatePressed?.Invoke(pathCard.DataContext, eventArgs.ClickCount);
                eventArgs.Handled = true;
            }
        }
    }
}