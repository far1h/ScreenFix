using ScreenFix.App.Runtime;
using ScreenFix.Core.Displays;

namespace ScreenFix.App.Calibration;

internal sealed class WinFormsMonitorPickerHost : IMonitorPickerHost
{
    private MonitorPickerForm? picker;
    private FormClosedEventHandler? closedHandler;

    public RuntimeOperationResult Start(
        long generation,
        IReadOnlyList<ConnectedDisplay> displays,
        Action<long, ConnectedDisplay> selected,
        Action<long> cancelled)
    {
        ArgumentNullException.ThrowIfNull(displays);
        ArgumentNullException.ThrowIfNull(selected);
        ArgumentNullException.ThrowIfNull(cancelled);

        if (displays.Count == 0)
        {
            return RuntimeOperationResult.Failure("No connected monitors were found");
        }

        Stop();
        MonitorPickerForm? candidate = null;
        try
        {
            candidate = new MonitorPickerForm(displays);
            closedHandler = (_, _) => Complete(candidate, generation, selected, cancelled);
            candidate.FormClosed += closedHandler;
            picker = candidate;
            candidate.Show();
            candidate.Activate();
            return RuntimeOperationResult.Success();
        }
        catch (Exception error)
        {
            if (candidate is not null && closedHandler is not null)
            {
                candidate.FormClosed -= closedHandler;
            }

            candidate?.Dispose();
            picker = null;
            closedHandler = null;
            return RuntimeOperationResult.Failure(error.Message);
        }
    }

    public void Stop()
    {
        var retired = picker;
        picker = null;
        if (retired is null)
        {
            return;
        }

        if (closedHandler is not null)
        {
            retired.FormClosed -= closedHandler;
        }

        closedHandler = null;
        retired.Dispose();
    }

    private void Complete(
        MonitorPickerForm completed,
        long generation,
        Action<long, ConnectedDisplay> selected,
        Action<long> cancelled)
    {
        if (!ReferenceEquals(picker, completed))
        {
            return;
        }

        if (closedHandler is not null)
        {
            completed.FormClosed -= closedHandler;
        }

        picker = null;
        closedHandler = null;
        var selectedDisplay = completed.DialogResult == DialogResult.OK
            ? completed.SelectedDisplay
            : null;
        completed.Dispose();
        if (selectedDisplay is null)
        {
            cancelled(generation);
        }
        else
        {
            selected(generation, selectedDisplay);
        }
    }
}
