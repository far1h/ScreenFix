using System.Runtime.InteropServices;

namespace ScreenFix.App.Runtime;

internal static class TrayIconLoader
{
    internal const string ResourceName = "ScreenFix.App.Resources.ScreenFix.ico";

    internal static Icon Load() =>
        Load(ResourceName, SystemInformation.SmallIconSize);

    internal static Icon Load(string resourceName, Size requestedSize)
    {
        try
        {
            using var stream = typeof(TrayIconLoader).Assembly
                .GetManifestResourceStream(resourceName);
            if (stream is null)
            {
                return LoadFallback();
            }

            using var source = new Icon(stream, requestedSize);
            return (Icon)source.Clone();
        }
        catch (ArgumentException)
        {
            return LoadFallback();
        }
        catch (ExternalException)
        {
            return LoadFallback();
        }
        catch (IOException)
        {
            return LoadFallback();
        }
    }

    private static Icon LoadFallback() =>
        (Icon)SystemIcons.Application.Clone();
}
