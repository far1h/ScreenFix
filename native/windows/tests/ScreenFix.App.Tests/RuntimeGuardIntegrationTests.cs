using ScreenFix.App.Guard;
using ScreenFix.App.Runtime;
using ScreenFix.Core.Configuration;
using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;
using ScreenFix.Core.Menu;

namespace ScreenFix.App.Tests;

public sealed class RuntimeGuardIntegrationTests
{
    [Fact]
    public void Start_CommitsMasksBeforeStartingGuardWithSameNativeFrames()
    {
        var configuration = DefaultConfiguration.Create(
            new DisplayIdentity("display-path", "Ultrawide", 3440, 1440));
        var display = new ConnectedDisplay(
            configuration.Display.StableId,
            configuration.Display.Name,
            3440,
            1440,
            new RectD(0, 0, 3440, 1440),
            new RectD(0, 0, 3440, 1400));
        var order = new List<string>();
        var overlays = new FakeOverlayHost(order);
        var guard = new FakeWindowGuard(order);
        var controller = new RuntimeController(
            new FakeConfigStore(configuration),
            new FakeTopology(display, new nint(77)),
            overlays,
            guard,
            new FakeCalibrationHost(),
            new FakePickerHost(),
            new FakeMenuHost(),
            new FakeUiThread(),
            new FakeNoticeSink(),
            new FakeClock());

        controller.Start();

        Assert.Equal(["masks", "guard"], order);
        var replacement = Assert.Single(overlays.Replacements);
        var start = Assert.Single(guard.Starts);
        Assert.Equal(new nint(77), start.Monitor.Handle);
        Assert.Equal(display.FullBounds, start.Monitor.FullBounds);
        Assert.Equal(display.WorkArea, start.Monitor.WorkArea);
        Assert.Equal(replacement, start.MaskBands);
    }

    [Fact]
    public void Calibrate_PausesGuardAndPreservesCommittedMasks()
    {
        var harness = new Harness();
        harness.Controller.Start();

        harness.Controller.Calibrate();

        Assert.True(harness.Calibration.IsEditing);
        Assert.Equal(1, harness.Guard.PauseCount);
        Assert.Equal(0, harness.Overlays.ClearCount);
    }

    [Fact]
    public void CalibrationCancel_ReconcilesMasksBeforeRestartingGuard()
    {
        var harness = new Harness();
        harness.Controller.Start();
        harness.Controller.Calibrate();

        harness.Calibration.Cancel();

        Assert.False(harness.Calibration.IsEditing);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
        Assert.Equal(2, harness.Guard.Starts.Count);
        Assert.Equal(
            harness.Overlays.Replacements[^1],
            harness.Guard.Starts[^1].MaskBands);
    }

    [Fact]
    public void CalibrationSave_CommitsMasksBeforeRestartingGuard()
    {
        var harness = new Harness();
        harness.Controller.Start();
        harness.Controller.Calibrate();
        var current = harness.Controller.State.Configuration!;
        var changedBands = current.Bands.Select((band, index) =>
            index == 0 ? band with { X = band.X + 0.01 } : band).ToArray();
        harness.Order.Clear();

        harness.Calibration.Save(changedBands);

        Assert.False(harness.Calibration.IsEditing);
        Assert.Equal(["masks", "guard"], harness.Order);
        Assert.Equal(changedBands, harness.Controller.State.Configuration!.Bands);
        Assert.Equal(
            harness.Overlays.Replacements[^1],
            harness.Guard.Starts[^1].MaskBands);
    }

    [Fact]
    public void MaskFailure_PreservesMasksAndPausesGuard()
    {
        var harness = new Harness();
        harness.Controller.Start();
        harness.Overlays.NextResult = RuntimeOperationResult.Failure("render failed");

        harness.Controller.ReconcileDisplays();

        Assert.Equal(2, harness.Overlays.Replacements.Count);
        Assert.Equal(0, harness.Overlays.ClearCount);
        Assert.Equal(1, harness.Guard.PauseCount);
        Assert.Equal(0, harness.Guard.StopCount);
        Assert.Equal("Paused: Mask rendering failed", harness.StatusLabel);
    }

    [Fact]
    public void Disable_StopsGuardBeforeClearingMasks()
    {
        var harness = new Harness();
        harness.Controller.Start();
        harness.Order.Clear();

        harness.Controller.ToggleEnabled();

        Assert.Equal(["guard-stop", "masks-clear"], harness.Order);
        Assert.Null(harness.StatusLabel);
    }

    [Fact]
    public void Disconnect_StopsGuardBeforeClearingMasks()
    {
        var harness = new Harness();
        harness.Controller.Start();
        harness.Topology.Display = null;
        harness.Order.Clear();

        harness.Controller.ReconcileDisplays();

        Assert.Equal(["guard-stop", "masks-clear"], harness.Order);
        Assert.Equal("Paused: Selected display is disconnected", harness.StatusLabel);
    }

    [Fact]
    public void SuspendAndResume_StopThenRebuildWithoutDuplicates()
    {
        var harness = new Harness();
        harness.Controller.Start();
        harness.Order.Clear();

        harness.Controller.Suspend();
        harness.Controller.Suspend();

        Assert.Equal(["guard-stop", "masks-clear"], harness.Order);
        harness.Order.Clear();
        harness.Controller.Resume();
        harness.Controller.Resume();
        Assert.Equal(["masks", "guard"], harness.Order);
    }

    [Fact]
    public void Reconnect_RebuildsMasksThenStartsOneGuardSession()
    {
        var harness = new Harness();
        harness.Controller.Start();
        var display = harness.Topology.Display;
        harness.Topology.Display = null;
        harness.Controller.ReconcileDisplays();
        harness.Topology.Display = display;
        harness.Order.Clear();

        harness.Controller.ReconcileDisplays();

        Assert.Equal(["masks", "guard"], harness.Order);
        Assert.Equal(2, harness.Guard.Starts.Count);
    }

    [Fact]
    public void GuardFailure_KeepsMasksAndReportsOncePerRecoveryEpisode()
    {
        var harness = new Harness();
        harness.Guard.NextResult =
            RuntimeOperationResult.Failure("hooks unavailable");

        harness.Controller.Start();
        harness.Controller.ReconcileDisplays();

        Assert.Equal(0, harness.Overlays.ClearCount);
        Assert.Equal("Paused: Window correction unavailable", harness.StatusLabel);
        Assert.Single(harness.Notices.Messages);
        harness.Guard.NextResult = RuntimeOperationResult.Success();
        harness.Controller.ReconcileDisplays();
        Assert.Null(harness.StatusLabel);
        harness.Guard.NextResult =
            RuntimeOperationResult.Failure("hooks unavailable again");
        harness.Controller.ReconcileDisplays();
        Assert.Equal(2, harness.Notices.Messages.Count);
    }

    [Fact]
    public void InvalidReload_PreservesCommittedRuntimeAndPausesGuard()
    {
        var harness = new Harness();
        harness.Controller.Start();
        var committed = harness.Controller.State.Configuration;
        harness.Config.LoadResult = new ConfigLoadResult(null, false, "bad settings");
        harness.Order.Clear();

        harness.Controller.Reload();

        Assert.Equal(committed, harness.Controller.State.Configuration);
        Assert.True(harness.Controller.State.InvalidConfiguration);
        Assert.Single(harness.Overlays.Replacements);
        Assert.Equal(0, harness.Overlays.ClearCount);
        Assert.Equal(["guard-pause"], harness.Order);
        Assert.Equal("Paused: Invalid configuration", harness.StatusLabel);
    }

    [Fact]
    public void ReloadMaskFailure_PreservesPreviousConfigurationAndVisibleMasks()
    {
        var harness = new Harness();
        harness.Controller.Start();
        var committed = harness.Controller.State.Configuration!;
        var candidate = committed with
        {
            Bands = committed.Bands.Select((band, index) =>
                index == 0 ? band with { X = band.X + 0.01 } : band).ToArray(),
        };
        harness.Config.LoadResult = new ConfigLoadResult(candidate, false, null);
        harness.Overlays.NextResult = RuntimeOperationResult.Failure("render failed");

        harness.Controller.Reload();

        Assert.Equal(committed, harness.Controller.State.Configuration);
        Assert.True(harness.Controller.State.MaskRenderingFailed);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
        Assert.Equal(0, harness.Overlays.ClearCount);
        Assert.Equal(1, harness.Guard.PauseCount);
        Assert.Equal("Paused: Mask rendering failed", harness.StatusLabel);
    }

    [Fact]
    public void InvalidReload_ReportsOnlyOnceUntilValidRecovery()
    {
        var harness = new Harness();
        harness.Controller.Start();
        harness.Config.LoadResult = new ConfigLoadResult(null, false, "bad settings");

        harness.Controller.Reload();
        harness.Controller.Reload();

        Assert.Equal(["bad settings"], harness.Notices.Messages);
        var valid = harness.Controller.State.Configuration!;
        harness.Config.LoadResult = new ConfigLoadResult(valid, false, null);
        harness.Controller.Reload();
        harness.Config.LoadResult = new ConfigLoadResult(null, false, "bad again");
        harness.Controller.Reload();
        Assert.Equal(["bad settings", "bad again"], harness.Notices.Messages);
    }

    [Fact]
    public void GuardStartException_IsContainedWithMasksStillActive()
    {
        var harness = new Harness();
        harness.Guard.ThrowOnStart = true;

        var error = Record.Exception(harness.Controller.Start);

        Assert.Null(error);
        Assert.Single(harness.Overlays.Replacements);
        Assert.Equal(0, harness.Overlays.ClearCount);
        Assert.Equal(1, harness.Guard.PauseCount);
        Assert.Equal("Paused: Window correction unavailable", harness.StatusLabel);
    }

    [Fact]
    public void ValidReload_PausesThenCommitsMasksBeforeRestartingGuard()
    {
        var harness = new Harness();
        harness.Controller.Start();
        var current = harness.Controller.State.Configuration!;
        var changed = current with
        {
            Bands = current.Bands.Select((band, index) =>
                index == 0 ? band with { X = band.X + 0.01 } : band).ToArray(),
        };
        harness.Config.LoadResult = new ConfigLoadResult(changed, false, null);
        harness.Order.Clear();

        harness.Controller.Reload();

        Assert.Equal(["guard-pause", "masks", "guard"], harness.Order);
        Assert.Equal(changed, harness.Controller.State.Configuration);
        Assert.Equal(
            harness.Overlays.Replacements[^1],
            harness.Guard.Starts[^1].MaskBands);
    }

    private sealed class Harness
    {
        public Harness()
        {
            var configuration = DefaultConfiguration.Create(
                new DisplayIdentity("display-path", "Ultrawide", 3440, 1440));
            var display = new ConnectedDisplay(
                configuration.Display.StableId,
                configuration.Display.Name,
                3440,
                1440,
                new RectD(0, 0, 3440, 1440),
                new RectD(0, 0, 3440, 1400));
            Order = [];
            Overlays = new FakeOverlayHost(Order);
            Guard = new FakeWindowGuard(Order);
            Calibration = new FakeCalibrationHost();
            Menu = new FakeMenuHost();
            Topology = new FakeTopology(display, new nint(77));
            Notices = new FakeNoticeSink();
            Config = new FakeConfigStore(configuration);
            Controller = new RuntimeController(
                Config,
                Topology,
                Overlays,
                Guard,
                Calibration,
                new FakePickerHost(),
                Menu,
                new FakeUiThread(),
                Notices,
                new FakeClock());
        }

        public FakeOverlayHost Overlays { get; }

        public FakeConfigStore Config { get; }

        public List<string> Order { get; }

        public FakeTopology Topology { get; }

        public FakeWindowGuard Guard { get; }

        public FakeCalibrationHost Calibration { get; }

        public FakeMenuHost Menu { get; }

        public FakeNoticeSink Notices { get; }

        public RuntimeController Controller { get; }

        public string? StatusLabel => Menu.Rows.SingleOrDefault(row =>
            row.Label.StartsWith("Paused:", StringComparison.Ordinal))?.Label;
    }

    private sealed class FakeConfigStore(ScreenFixConfig configuration) : IRuntimeConfigStore
    {
        public ConfigLoadResult LoadResult { get; set; } =
            new(configuration, false, null);

        public ConfigLoadResult Load() => LoadResult;

        public void Save(ScreenFixConfig value)
        {
        }
    }

    private sealed class FakeTopology(
        ConnectedDisplay display,
        nint monitorHandle) : IDisplayTopology
    {
        public ConnectedDisplay? Display { get; set; } = display;

        public IReadOnlyList<ConnectedDisplay> Enumerate() =>
            Display is null ? [] : [Display];

        public bool TryGetMonitorHandle(
            ConnectedDisplay candidate,
            out nint handle)
        {
            handle = monitorHandle;
            return candidate == Display;
        }
    }

    private sealed class FakeOverlayHost(List<string> order) : IMaskOverlayHost
    {
        public List<IReadOnlyList<RectD>> Replacements { get; } = [];

        public int ClearCount { get; private set; }

        public RuntimeOperationResult NextResult { get; set; } =
            RuntimeOperationResult.Success();

        public RuntimeOperationResult Replace(IReadOnlyList<RectD> frames)
        {
            order.Add("masks");
            Replacements.Add(frames);
            return NextResult;
        }

        public void Clear()
        {
            ClearCount++;
            order.Add("masks-clear");
        }
    }

    private sealed class FakeWindowGuard(List<string> order) : IWindowGuard
    {
        public List<GuardStart> Starts { get; } = [];

        public int PauseCount { get; private set; }

        public int StopCount { get; private set; }

        public RuntimeOperationResult NextResult { get; set; } =
            RuntimeOperationResult.Success();

        public bool ThrowOnStart { get; set; }

        public RuntimeOperationResult Start(
            SelectedMonitor selectedMonitor,
            IReadOnlyList<RectD> maskBands)
        {
            if (ThrowOnStart)
            {
                throw new InvalidOperationException("hook exception");
            }

            order.Add("guard");
            Starts.Add(new GuardStart(selectedMonitor, maskBands));
            return NextResult;
        }

        public void Pause()
        {
            PauseCount++;
            order.Add("guard-pause");
        }

        public void Stop()
        {
            StopCount++;
            order.Add("guard-stop");
        }

        public void Dispose()
        {
        }
    }

    private sealed class FakeCalibrationHost : ICalibrationHost
    {
        private CalibrationHostCallbacks? callbacks;
        private long generation;

        public bool IsEditing { get; private set; }

        public RuntimeOperationResult Start(
            CalibrationStartRequest request,
            CalibrationHostCallbacks callbacks)
        {
            generation = request.Generation;
            this.callbacks = callbacks;
            IsEditing = true;
            return RuntimeOperationResult.Success();
        }

        public void Stop()
        {
            IsEditing = false;
        }

        public void Save(IReadOnlyList<RectD> bands) =>
            callbacks!.Save(generation, bands);

        public void Cancel() => callbacks!.Cancel(generation);
    }

    private sealed class FakePickerHost : IMonitorPickerHost
    {
        public RuntimeOperationResult Start(
            long generation,
            IReadOnlyList<ConnectedDisplay> displays,
            Action<long, ConnectedDisplay> selected,
            Action<long> cancelled) =>
            RuntimeOperationResult.Success();

        public void Stop()
        {
        }
    }

    private sealed class FakeMenuHost : IMenuHost
    {
        public IReadOnlyList<MenuRow> Rows { get; private set; } = [];

        public void Refresh(IReadOnlyList<MenuRow> rows)
        {
            Rows = rows;
        }
    }

    private sealed class FakeUiThread : IUiThread
    {
        public void VerifyAccess()
        {
        }
    }

    private sealed class FakeNoticeSink : INoticeSink
    {
        public List<string> Messages { get; } = [];

        public void Show(string message)
        {
            Messages.Add(message);
        }
    }

    private sealed class FakeClock : IClock
    {
        public DateTimeOffset UtcNow => DateTimeOffset.UnixEpoch;
    }

    private sealed record GuardStart(
        SelectedMonitor Monitor,
        IReadOnlyList<RectD> MaskBands);
}
