using Microsoft.UI.Xaml;

namespace HelloWorld;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private void OnHelloClick(object sender, RoutedEventArgs args)
    {
        MessageText.Text = new global::HelloWorld.WinRT.Greeter().GetMessage();
    }
}