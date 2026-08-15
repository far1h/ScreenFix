using ScreenFix.App.Notifications;
using ScreenFix.Core.Configuration;
using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;
using ScreenFix.Core.Menu;

namespace ScreenFix.App.Runtime;

public sealed class RuntimeController : ISystemMessageTarget
{
    private readonly IRuntimeConfigStore configStore;
    private readonly IDisplayTopology topology;
    private readonly IMaskOverlayHost overlays;
    private readonly ICalibrationHost calibration;
    private readonly IMonitorPickerHost picker;
    private readonly IMenuHost menu;
    private readonly IUiThread uiThread;
    private readonly INoticeSink notices;
    private ScreenFixConfig? configuration;
    private ScreenFixConfig? pendingConfiguration;
    private ConnectedDisplay? connectedDisplay;
    private bool invalidConfiguration;
    private bool maskRenderingFailed;
    private bool disconnectedFailureEpisode;
    private bool maskFailureEpisode;
    private bool stopped;
    private bool suspended;
    private long generation;

    public RuntimeController(
        IRuntimeConfigStore configStore,
        IDisplayTopology topology,
        IMaskOverlayHost overlays,
        ICalibrationHost calibration,
        IMonitorPickerHost picker,
        IMenuHost menu,
        IUiThread uiThread,
        INoticeSink notices,
        IClock clock)
    {
        this.configStore = configStore ?? throw new ArgumentNullException(nameof(configStore));
        this.topology = topology ?? throw new ArgumentNullException(nameof(topology));
        this.overlays = overlays ?? throw new ArgumentNullException(nameof(overlays));
        this.calibration = calibration ?? throw new ArgumentNullException(nameof(calibration));
        this.picker = picker ?? throw new ArgumentNullException(nameof(picker));
        this.menu = menu ?? throw new ArgumentNullException(nameof(menu));
        this.uiThread = uiThread ?? throw new ArgumentNullException(nameof(uiThread));
        this.notices = notices ?? throw new ArgumentNullException(nameof(notices));
        ArgumentNullException.ThrowIfNull(clock);
        stopped = false;
        generation = 0;
    }

    public RuntimeState State
    {
        get
        {
            uiThread.VerifyAccess();
            return new RuntimeState(
                configuration,
                connectedDisplay,
                invalidConfiguration,
                maskRenderingFailed,
                calibration.IsEditing,
                stopped,
                generation);
        }
    }

    public void Start()
    {
        VerifyActive();
        if (stopped)
        {
            return;
        }

        var loaded = configStore.Load();
        if (loaded.IsMissing)
        {
            configuration = null;
            connectedDisplay = null;
            invalidConfiguration = false;
            overlays.Clear();
            RefreshMenu();
            return;
        }

        if (loaded.Value is null)
        {
            invalidConfiguration = true;
            overlays.Clear();
            RefreshMenu();
            return;
        }

        configuration = loaded.Value;
        invalidConfiguration = false;
        Reconcile();
    }

    public void ReconcileDisplays()
    {
        VerifyActive();
        if (stopped || suspended)
        {
            return;
        }

        if (calibration.IsEditing)
        {
            EndEditing();
        }

        Reconcile();
    }

    public void Suspend()
    {
        VerifyActive();
        if (stopped || suspended)
        {
            return;
        }

        suspended = true;
        generation++;
        pendingConfiguration = null;
        picker.Stop();
        calibration.Stop();
        overlays.Clear();
    }

    public void Resume()
    {
        VerifyActive();
        if (stopped || !suspended)
        {
            return;
        }

        suspended = false;
        generation++;
        Reconcile();
    }

    public void CancelEditorForDpiChange()
    {
        CancelEditorForDpiChange(generation);
    }

    public void CancelEditorForDpiChange(long editorGeneration)
    {
        VerifyActive();
        if (stopped || suspended)
        {
            return;
        }

        OnCalibrationDpiChanged(editorGeneration);
    }

    public void SelectMonitor()
    {
        VerifyActive();
        if (stopped)
        {
            return;
        }

        if (calibration.IsEditing)
        {
            EndEditing();
            Reconcile();
        }

        generation++;
        var pickerGeneration = generation;
        var result = picker.Start(
            pickerGeneration,
            topology.Enumerate(),
            OnMonitorSelected,
            OnMonitorSelectionCancelled);
        if (!result.IsSuccess)
        {
            notices.Show(result.Error ?? "Monitor selection failed");
        }

        RefreshMenu();
    }

    public void Calibrate()
    {
        VerifyActive();
        if (stopped)
        {
            return;
        }

        if (calibration.IsEditing)
        {
            EndEditing();
            Reconcile();
            return;
        }

        if (configuration is null || connectedDisplay is null)
        {
            return;
        }

        BeginEditing(configuration with { Bands = configuration.Bands.ToArray() });
    }

    public void ToggleEnabled()
    {
        VerifyActive();
        if (stopped)
        {
            return;
        }

        if (configuration is null)
        {
            SelectMonitor();
            return;
        }

        var candidate = configuration with { Enabled = !configuration.Enabled };
        if (!TrySave(candidate))
        {
            return;
        }

        configuration = candidate;
        invalidConfiguration = false;
        generation++;
        pendingConfiguration = null;
        picker.Stop();
        calibration.Stop();
        Reconcile();
    }

    public void ResetDefaults()
    {
        VerifyActive();
        if (stopped || configuration is null)
        {
            return;
        }

        connectedDisplay = DisplayMatcher.Find(configuration.Display, topology.Enumerate());
        if (connectedDisplay is null)
        {
            Reconcile();
            return;
        }

        var identity = new DisplayIdentity(
            connectedDisplay.StableId ?? configuration.Display.StableId,
            connectedDisplay.Name,
            connectedDisplay.Width,
            connectedDisplay.Height);
        var candidate = DefaultConfiguration.Create(identity) with
        {
            Enabled = configuration.Enabled,
        };
        if (!TrySave(candidate))
        {
            return;
        }

        configuration = candidate;
        invalidConfiguration = false;
        generation++;
        pendingConfiguration = null;
        picker.Stop();
        calibration.Stop();
        Reconcile();
    }

    public void Reload()
    {
        VerifyActive();
        if (stopped)
        {
            return;
        }

        var loaded = configStore.Load();
        if (loaded.IsMissing || loaded.Value is null)
        {
            invalidConfiguration = true;
            RefreshMenu();
            return;
        }

        generation++;
        pendingConfiguration = null;
        picker.Stop();
        calibration.Stop();
        configuration = loaded.Value;
        invalidConfiguration = false;
        Reconcile();
    }

    public void Stop()
    {
        uiThread.VerifyAccess();
        var wasStopped = stopped;
        RevokeCallbacks();
        if (wasStopped)
        {
            return;
        }

        calibration.Stop();
        overlays.Clear();
    }

    public void RevokeCallbacks()
    {
        uiThread.VerifyAccess();
        if (stopped)
        {
            return;
        }

        stopped = true;
        generation++;
        pendingConfiguration = null;
        picker.Stop();
    }

    private void OnMonitorSelected(long callbackGeneration, ConnectedDisplay display)
    {
        uiThread.VerifyAccess();
        if (!IsCurrent(callbackGeneration) || string.IsNullOrWhiteSpace(display.StableId))
        {
            return;
        }

        picker.Stop();
        var identity = new DisplayIdentity(
            display.StableId,
            display.Name,
            display.Width,
            display.Height);
        BeginEditing(DefaultConfiguration.Create(identity), requireExactStableId: true);
    }

    private void OnMonitorSelectionCancelled(long callbackGeneration)
    {
        uiThread.VerifyAccess();
        if (!IsCurrent(callbackGeneration))
        {
            return;
        }

        generation++;
        picker.Stop();
        RefreshMenu();
    }

    private void BeginEditing(
        ScreenFixConfig candidateConfiguration,
        bool requireExactStableId = false)
    {
        var connected = topology.Enumerate();
        var display = requireExactStableId
            ? FindUniqueStableId(candidateConfiguration.Display.StableId, connected)
            : DisplayMatcher.Find(candidateConfiguration.Display, connected);
        if (display is null)
        {
            notices.Show("Selected display is disconnected or ambiguous");
            Reconcile();
            return;
        }

        generation++;
        var editorGeneration = generation;
        var result = calibration.Start(
            new CalibrationStartRequest(
                editorGeneration,
                display,
                candidateConfiguration.Bands.ToArray()),
            new CalibrationHostCallbacks(
                OnCalibrationSaved,
                OnCalibrationCancelled,
                OnCalibrationDpiChanged));
        if (!result.IsSuccess)
        {
            notices.Show(result.Error ?? "Calibration failed");
            RefreshMenu();
            return;
        }

        pendingConfiguration = candidateConfiguration;
        overlays.Clear();
        RefreshMenu();
    }

    private static ConnectedDisplay? FindUniqueStableId(
        string stableId,
        IReadOnlyList<ConnectedDisplay> connected)
    {
        var matches = connected.Where(display =>
            display.StableId is not null &&
            StringComparer.OrdinalIgnoreCase.Equals(display.StableId, stableId)).ToArray();
        return matches.Length == 1 ? matches[0] : null;
    }

    private void OnCalibrationSaved(
        long callbackGeneration,
        IReadOnlyList<RectD> bands)
    {
        uiThread.VerifyAccess();
        if (!IsCurrent(callbackGeneration) || pendingConfiguration is null)
        {
            return;
        }

        var candidate = pendingConfiguration with { Bands = bands.ToArray() };
        var validation = ConfigValidator.Validate(candidate);
        if (!validation.IsValid)
        {
            notices.Show(validation.Error ?? "Calibration is invalid");
            return;
        }

        if (!TrySave(candidate))
        {
            return;
        }

        configuration = candidate;
        invalidConfiguration = false;
        EndEditing();
        Reconcile();
    }

    private void OnCalibrationCancelled(long callbackGeneration)
    {
        uiThread.VerifyAccess();
        if (!IsCurrent(callbackGeneration))
        {
            return;
        }

        EndEditing();
        Reconcile();
    }

    private void OnCalibrationDpiChanged(long callbackGeneration)
    {
        uiThread.VerifyAccess();
        if (!IsCurrent(callbackGeneration))
        {
            return;
        }

        EndEditing();
        Reconcile();
    }

    private void EndEditing()
    {
        generation++;
        pendingConfiguration = null;
        calibration.Stop();
    }

    private bool TrySave(ScreenFixConfig candidate)
    {
        try
        {
            configStore.Save(candidate);
            return true;
        }
        catch (Exception error)
        {
            notices.Show(error.Message);
            return false;
        }
    }

    private void Reconcile()
    {
        if (configuration is null)
        {
            connectedDisplay = null;
            maskRenderingFailed = false;
            overlays.Clear();
            RefreshMenu();
            return;
        }

        connectedDisplay = DisplayMatcher.Find(configuration.Display, topology.Enumerate());
        if (calibration.IsEditing)
        {
            RefreshMenu();
            return;
        }

        if (!configuration.Enabled)
        {
            overlays.Clear();
            maskRenderingFailed = false;
            disconnectedFailureEpisode = false;
            maskFailureEpisode = false;
            RefreshMenu();
            return;
        }

        if (connectedDisplay is null)
        {
            overlays.Clear();
            maskRenderingFailed = false;
            maskFailureEpisode = false;
            if (!disconnectedFailureEpisode)
            {
                notices.Show("Selected display is disconnected");
                disconnectedFailureEpisode = true;
            }

            RefreshMenu();
            return;
        }

        disconnectedFailureEpisode = false;
        var frames = NativePixelGeometry.ToNativeBands(
            connectedDisplay.FullBounds,
            configuration.Bands);
        var replacement = overlays.Replace(frames);
        maskRenderingFailed = !replacement.IsSuccess;
        if (replacement.IsSuccess)
        {
            maskFailureEpisode = false;
        }
        else if (!maskFailureEpisode)
        {
            notices.Show(replacement.Error ?? "Mask rendering failed");
            maskFailureEpisode = true;
        }

        RefreshMenu();
    }

    private void RefreshMenu()
    {
        menu.Refresh(MenuState.Build(new MenuStateInput(
            Enabled: configuration?.Enabled ?? false,
            HasSavedDisplay: configuration is not null,
            DisplayConnected: connectedDisplay is not null,
            Calibrating: calibration.IsEditing,
            InvalidConfiguration: invalidConfiguration,
            MaskRenderingFailed: maskRenderingFailed)));
    }

    private bool IsCurrent(long callbackGeneration) =>
        !stopped && callbackGeneration == generation;

    private void VerifyActive() => uiThread.VerifyAccess();
}
