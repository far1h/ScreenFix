namespace ScreenFix.App;

internal static class ScreenFixPaths
{
    internal static string ConfigFile => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ScreenFix",
        "config.json");
}
