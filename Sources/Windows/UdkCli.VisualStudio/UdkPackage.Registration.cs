using System.Runtime.InteropServices;

using Microsoft.VisualStudio.Shell;

namespace UniversalDevKit.UdkCli.VisualStudio {
    [PackageRegistration(UseManagedResourcesOnly = true, AllowsBackgroundLoading = true)]
    [ProvideMenuResource("Menus.ctmenu", 1)]
    [Guid("111b8451-4b34-4d32-a917-da2c6d10e337")]
    public sealed partial class UdkPackage {
    }
}