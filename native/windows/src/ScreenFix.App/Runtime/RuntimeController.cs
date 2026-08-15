using ScreenFix.App.Notifications;
using ScreenFix.App.Guard;
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
    private readonly IWindowGuard guard;
    private readonly ICalibrationHost calibration;
    private readonly IMonitorPickerHost picker;
    private readonly IMenuHost menu;
    private readonly IUiThread uiThread;
    private readonly INoticeSink notices;
    private ScreenFixConfig? configuration;
    private ScreenFixConfig? pendingConfiguration;
    private ConnectedDisplay? connectedDisplay;
    private bool invalidConfiguration;
    private bool invalidFailureEpisode;
    private bool maskRenderingFailed;
    private bool disconnectedFailureEpisode;
    private bool maskFailureEpisode;
    private bool guardUnavailable;
    private bool guardFailureEpisode;
    private bool stopped;
    private bool suspended;
    private long generation;

    public RuntimeController(
        IRuntimeConfigStore configStore,
        IDisplayTopology topology,
        IMaskOverlayHost overlays,
        IWindowGuard guard,
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
        this.guard = guard ?? throw new ArgumentNullException(nameof(guard));
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
                guardUnavailable,
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
            invalidFailureEpisode = false;
            StopGuard();
            overlays.Clear();
            RefreshMenu();
            return;
        }

        if (loaded.Value is null)
        {
            invalidConfiguration = true;
            guard.Pause();
            overlays.Clear();
            ReportInvalidConfiguration(loaded.Error);
            RefreshMenu();
            return;
        }

        configuration = loaded.Value;
        invalidConfiguration = false;
        invalidFailureEpisode = false;
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
        StopGuard();
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
            guard.Pause();
            ReportInvalidConfiguration(loaded.Error);
            RefreshMenu();
            return;
        }

        invalidFailureEpisode = false;

        generation++;
        pendingConfiguration = null;
        picker.Stop();
        calibration.Stop();
        guard.Pause();
        var candidate = loaded.Value;
        var candidateDisplay = DisplayMatcher.Find(
            candidate.Display,
            topology.Enumerate());
        if (!candidate.Enabled || candidateDisplay is null)
        {
            configuration = candidate;
            invalidConfiguration = false;
            Reconcile();
            return;
        }

        var frames = NativePixelGeometry.ToNativeBands(
            candidateDisplay.FullBounds,
            candidate.Bands);
        var replacement = overlays.Replace(frames);
        if (!replacement.IsSuccess)
        {
            invalidConfiguration = false;
            maskRenderingFailed = true;
            guardUnavailable = false;
            if (!maskFailureEpisode)
            {
                notices.Show(replacement.Error ?? "Mask rendering failed");
                maskFailureEpisode = true;
            }

            RefreshMenu();
            return;
        }

        configuration = candidate;
        connectedDisplay = candidateDisplay;
        invalidConfiguration = false;
        maskRenderingFailed = false;
        maskFailureEpisode = false;
        disconnectedFailureEpisode = false;
        StartGuard(frames);
        RefreshMenu();
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
        StopGuard();
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
        var liveDisplay = FindUniqueStableId(display.StableId, topology.Enumerate());
        if (liveDisplay is null)
        {
            notices.Show("Selected display is disconnected or ambiguous");
            Reconcile();
            return;
        }

        var identity = new DisplayIdentity(
            liveDisplay.StableId!,
            liveDisplay.Name,
            liveDisplay.Width,
            liveDisplay.Height);
        BeginEditing(DefaultConfiguration.Create(identity), liveDisplay);
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
        ConnectedDisplay? resolvedDisplay = null)
    {
        var display = resolvedDisplay ??
            DisplayMatcher.Find(candidateConfiguration.Display, topology.Enumerate());
        if (display is null)
        {
            notices.Show("Selected display is disconnected or ambiguous");
            Reconcile();
            return;
        }

        generation++;
        var editorGeneration = generation;
        guard.Pause();
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
            Reconcile();
            return;
        }

        pendingConfiguration = candidateConfiguration;
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
            StopGuard();
            overlays.Clear();
            RefreshMenu();
            return;
        }

        connectedDisplay = DisplayMatcher.Find(configuration.Display, topology.Enumerate());
        if (calibration.IsEditing)
        {
            guard.Pause();
            RefreshMenu();
            return;
        }

        if (!configuration.Enabled)
        {
            StopGuard();
            overlays.Clear();
            maskRenderingFailed = false;
            disconnectedFailureEpisode = false;
            maskFailureEpisode = false;
            RefreshMenu();
            return;
        }

        if (connectedDisplay is null)
        {
            StopGuard();
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
            StartGuard(frames);
        }
        else if (!maskFailureEpisode)
        {
            notices.Show(replacement.Error ?? "Mask rendering failed");
            maskFailureEpisode = true;
        }

        if (!replacement.IsSuccess)
        {
            guard.Pause();
            guardUnavailable = false;
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
            MaskRenderingFailed: maskRenderingFailed,
            WindowCorrectionUnavailable: guardUnavailable)));
    }

    private bool IsCurrent(long callbackGeneration) =>
        !stopped && callbackGeneration == generation;

    private void VerifyActive() => uiThread.VerifyAccess();

    private void StartGuard(IReadOnlyList<RectD> frames)
    {
        RuntimeOperationResult result;
        if (connectedDisplay is null ||
            !topology.TryGetMonitorHandle(connectedDisplay, out var monitorHandle))
        {
            guard.Pause();
            result = RuntimeOperationResult.Failure("Monitor handle is unavailable");
        }
        else
        {
            try
            {
                result = guard.Start(
                    new SelectedMonitor(
                        monitorHandle,
                        connectedDisplay.FullBounds,
                        connectedDisplay.WorkArea),
                    frames);
            }
            catch (Exception error)
            {
                guard.Pause();
                result = RuntimeOperationResult.Failure(error.Message);
            }
        }

        guardUnavailable = !result.IsSuccess;
        if (result.IsSuccess)
        {
            guardFailureEpisode = false;
        }
        else if (!guardFailureEpisode)
        {
            notices.Show(result.Error ?? "Window correction unavailable");
            guardFailureEpisode = true;
        }
    }

    private void StopGuard()
    {
        guard.Stop();
        guardUnavailable = false;
        guardFailureEpisode = false;
    }

    private void ReportInvalidConfiguration(string? error)
    {
        if (invalidFailureEpisode)
        {
            return;
        }

        notices.Show(error ?? "Invalid configuration");
        invalidFailureEpisode = true;
    }

}
