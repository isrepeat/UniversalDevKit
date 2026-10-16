using System;

try {
    var probe = new UniversalDevKit.TestPackages.Probe();
    if (probe.GetValue() != 42) { return 1; }
    Console.WriteLine("C# CsWinRT activation passed");
    return 0;
}
catch (Exception error) {
    Console.Error.WriteLine(error);
    return 2;
}