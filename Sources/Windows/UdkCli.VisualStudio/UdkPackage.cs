using System;
using System.Threading;
using System.Threading.Tasks;

using Microsoft.VisualStudio.Shell;

namespace UniversalDevKit.UdkCli.VisualStudio {
    public sealed partial class UdkPackage : AsyncPackage {
        protected override Task InitializeAsync(CancellationToken cancellationToken, IProgress<ServiceProgressData> progress) {
            return Commands.CommandRegistration.RegisterAsync(this, cancellationToken);
        }
    }
}