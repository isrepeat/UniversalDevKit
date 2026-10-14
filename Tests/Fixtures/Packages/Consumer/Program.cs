if (UniversalDevKit.TestPackages.Probe.Value() != 42 || GeneratedProbe.Value() != 42) {
    return 1;
}
System.Console.WriteLine("Managed and build tool packages passed");
return 0;