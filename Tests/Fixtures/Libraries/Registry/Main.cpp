int CommonValue();
extern "C" int RunPluginA();
extern "C" int RunPluginB();

int main() {
    // Три модуля должны последовательно изменять один счётчик внутри Service.Dynamic.
    const int applicationValue = CommonValue();
    const int pluginAValue = RunPluginA();
    const int pluginBValue = RunPluginB();
    return applicationValue == 1 && pluginAValue == 2 && pluginBValue == 3 ? 0 : 1;
}