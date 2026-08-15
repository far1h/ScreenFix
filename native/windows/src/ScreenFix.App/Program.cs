using System.Windows.Forms;
using ScreenFix.App.Lifecycle;

namespace ScreenFix.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();

        var gate = SingleInstanceGate.TryAcquire(@"Local\ScreenFix.Native");
        if (gate is null)
        {
            return;
        }

        using var context = new ScreenFixApplicationContext(gate);
        Application.Run(context);
    }
}
