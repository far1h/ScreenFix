using System.Windows.Forms;

namespace ScreenFix.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
    }
}
