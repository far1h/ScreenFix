using ScreenFix.App.Calibration;
using ScreenFix.App.Lifecycle;
using ScreenFix.App.Notifications;
using ScreenFix.App.Overlays;
using ScreenFix.App.Runtime;
using ScreenFix.Core.Menu;

namespace ScreenFix.App;

internal sealed class ScreenFixApplicationContext : ApplicationContext
{
    private readonly ApplicationLifetime lifetime = new();
    private RuntimeController? controller;
    private INoticeSink? notices;

    public ScreenFixApplicationContext(SingleInstanceGate gate)
    {
        ArgumentNullException.ThrowIfNull(gate);
        lifetime.OwnGate(gate.Dispose);

        try
        {
            InitializeTrayAndRuntime();
        }
        catch
        {
            lifetime.Dispose();
            throw;
        }
    }

    protected override void ExitThreadCore()
    {
        try
        {
            lifetime.Dispose();
        }
        finally
        {
            base.ExitThreadCore();
        }
    }

    protected override void Dispose(bool disposing)
    {
        try
        {
            if (disposing)
            {
                lifetime.Dispose();
            }
        }
        finally
        {
            base.Dispose(disposing);
        }
    }

    private void InitializeTrayAndRuntime()
    {
        var uiBridge = new WinFormsUiBridge();
        var icon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "ScreenFix",
        };
        lifetime.OwnTrayIcon(() =>
        {
            icon.Visible = false;
            icon.Dispose();
            uiBridge.Dispose();
        });

        notices = new NotifyIconNoticeSink(icon);
        var menu = new TrayMenuHost(icon, ExecuteCommand);
        lifetime.OwnMenu(menu.Dispose);
        var rows = MenuState.Build(new MenuStateInput(
            Enabled: false,
            HasSavedDisplay: false,
            DisplayConnected: false,
            Calibrating: false,
            InvalidConfiguration: false,
            MaskRenderingFailed: false));
        menu.Refresh(rows);
        icon.Visible = true;

        try
        {
            InitializeRuntime(uiBridge, menu);
        }
        catch (Exception error)
        {
            TryShowNotice(error.Message);
        }
    }

    private void InitializeRuntime(WinFormsUiBridge uiBridge, TrayMenuHost menu)
    {
        var overlaySet = new MaskOverlaySet(new MaskFormFactory());
        lifetime.OwnMasks(overlaySet.Dispose);

        var targetBridge = new SystemMessageTargetBridge();
        var messageCoordinator = new SystemMessageCoordinator(targetBridge, uiBridge, generation: 1);
        var messageWindow = new SystemMessageWindow(messageCoordinator);
        lifetime.OwnSystemMessages(messageWindow.Dispose);

        var calibration = new WinFormsCalibrationHost(editorGeneration =>
            messageCoordinator.HandleEditorDpiChanged(
                editorGeneration,
                messageCoordinator.Generation));
        lifetime.OwnEditor(calibration.Stop);

        var localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var configPath = Path.Combine(localData, "ScreenFix", "config.json");
        controller = new RuntimeController(
            new RuntimeConfigStore(configPath),
            new RuntimeDisplayTopology(),
            new RuntimeMaskOverlayHost(overlaySet),
            calibration,
            new WinFormsMonitorPickerHost(),
            menu,
            uiBridge,
            notices!,
            new SystemClock());
        targetBridge.Connect(controller);
        lifetime.OwnControllerCallbacks(() =>
        {
            controller.RevokeCallbacks();
            targetBridge.Disconnect();
        });
        controller.Start();
    }

    private void ExecuteCommand(MenuCommand command)
    {
        if (command == MenuCommand.Quit)
        {
            ExitThread();
            return;
        }

        if (controller is null)
        {
            return;
        }

        try
        {
            switch (command)
            {
                case MenuCommand.ToggleEnabled:
                    controller.ToggleEnabled();
                    break;
                case MenuCommand.Calibrate:
                    controller.Calibrate();
                    break;
                case MenuCommand.SelectMonitor:
                    controller.SelectMonitor();
                    break;
                case MenuCommand.ResetDefaults:
                    controller.ResetDefaults();
                    break;
                case MenuCommand.Reload:
                    controller.Reload();
                    break;
            }
        }
        catch (Exception error)
        {
            TryShowNotice(error.Message);
        }
    }

    private void TryShowNotice(string message)
    {
        try
        {
            notices?.Show(message);
        }
        catch
        {
        }
    }
}
