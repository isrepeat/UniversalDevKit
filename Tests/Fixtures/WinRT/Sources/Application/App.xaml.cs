using System;
using System.IO;

using Microsoft.UI.Xaml;

namespace HelloWorld;

public partial class App : Application
{
    private Window? window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var arguments = Environment.GetCommandLineArgs();
        if (arguments.Length == 3 && arguments[1] == "--udk-verify")
        {
            File.WriteAllText(arguments[2], new global::HelloWorld.WinRT.Greeter().GetMessage());
            Exit();
            return;
        }

        window = new MainWindow();
        window.Activate();
    }
}