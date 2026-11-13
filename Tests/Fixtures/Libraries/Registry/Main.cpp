int CommonValue();
extern "C" int RunPluginA();
extern "C" int RunPluginB();

int main() {
    // Three modules must update one counter in Service.Dynamic in sequence.
    const int applicationValue = CommonValue();
    const int pluginAValue = RunPluginA();
    const int pluginBValue = RunPluginB();
    return applicationValue == 1 && pluginAValue == 2 && pluginBValue == 3 ? 0 : 1;
}