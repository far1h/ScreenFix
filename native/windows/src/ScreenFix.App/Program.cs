using System.Windows.Forms;
namespace ScreenFix.App;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();

        var gate = ScreenFixApplicationIdentity.TryAcquire();
        if (gate is null)
        {
            return;
        }

        using var context = new ScreenFixApplicationContext(gate);
        Application.Run(context);
    }
}
