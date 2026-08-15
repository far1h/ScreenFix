using ScreenFix.App.Notifications;
using ScreenFix.App.Runtime;
using ScreenFix.Core.Configuration;
using ScreenFix.Core.Displays;
using ScreenFix.Core.Geometry;
using ScreenFix.Core.Menu;

namespace ScreenFix.App.Tests;

public sealed class RuntimeControllerTests
{
    [Fact]
    public void Start_MissingConfigurationCreatesNothingAndRequestsMonitorSelectionInStatus()
    {
        var harness = new Harness(new ConfigLoadResult(null, true, null));

        harness.Controller.Start();

        Assert.Empty(harness.Overlays.Replacements);
        Assert.Equal(0, harness.Config.SaveCount);
        Assert.Equal("Paused: Select a monitor", harness.StatusLabel);
    }

    [Fact]
    public void Start_InvalidConfigurationPreservesBytesAndExposesStatus()
    {
        var harness = new Harness(new ConfigLoadResult(null, false, "bad settings"));

        harness.Controller.Start();

        Assert.Equal(0, harness.Config.SaveCount);
        Assert.Empty(harness.Overlays.Replacements);
        Assert.Equal("Paused: Invalid configuration", harness.StatusLabel);
    }

    [Fact]
    public void Start_EnabledConnectedConfigurationRendersThreeMasks()
    {
        var config = DefaultConfig();
        var display = Connected(config.Display);
        var harness = new Harness(new ConfigLoadResult(config, false, null), [display]);

        harness.Controller.Start();

        Assert.Equal(3, Assert.Single(harness.Overlays.Replacements).Count);
        Assert.Equal(
            "Paused: Window correction is not available in this build",
            harness.StatusLabel);
    }

    [Fact]
    public void Start_DisabledConfigurationCreatesNoMasksAndNoPausedStatus()
    {
        var config = DefaultConfig() with { Enabled = false };
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);

        harness.Controller.Start();

        Assert.Empty(harness.Overlays.Replacements);
        Assert.Null(harness.StatusLabel);
    }

    [Fact]
    public void Start_DisconnectedConfigurationReportsOnlyOneFailureEpisode()
    {
        var harness = new Harness(new ConfigLoadResult(DefaultConfig(), false, null));

        harness.Controller.Start();
        harness.Controller.ReconcileDisplays();

        Assert.Empty(harness.Overlays.Replacements);
        Assert.Equal("Paused: Selected display is disconnected", harness.StatusLabel);
        Assert.Single(harness.Notices.Messages);
    }

    [Fact]
    public void Start_UniqueNameAndDimensionFallbackReconnects()
    {
        var config = DefaultConfig();
        var fallback = Connected(config.Display) with { StableId = null };
        var harness = new Harness(new ConfigLoadResult(config, false, null), [fallback]);

        harness.Controller.Start();

        Assert.Single(harness.Overlays.Replacements);
    }

    [Fact]
    public void Start_AmbiguousFallbackDoesNotCreateMasks()
    {
        var config = DefaultConfig();
        var fallback = Connected(config.Display) with { StableId = null };
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [fallback, fallback with { FullBounds = new RectD(3440, 0, 3440, 1440) }]);

        harness.Controller.Start();

        Assert.Empty(harness.Overlays.Replacements);
        Assert.Equal("Paused: Selected display is disconnected", harness.StatusLabel);
    }

    [Fact]
    public void SelectMonitor_StartsExactDefaultsAndPersistsOnlyAfterSave()
    {
        var display = Connected(DefaultConfig().Display);
        var harness = new Harness(new ConfigLoadResult(null, true, null), [display]);
        harness.Controller.Start();

        harness.Controller.SelectMonitor();
        harness.Picker.Select(display);

        var request = Assert.IsType<CalibrationStartRequest>(harness.Calibration.Request);
        var defaults = DefaultConfiguration.Create(new DisplayIdentity(
            display.StableId!, display.Name, display.Width, display.Height));
        Assert.Equal(defaults.Bands, request.Bands);
        Assert.Equal(0, harness.Config.SaveCount);

        harness.Calibration.Save(request.Bands);

        Assert.Equal(1, harness.Config.SaveCount);
        Assert.Equal(defaults.Bands, harness.Config.LastSaved!.Bands);
    }

    [Fact]
    public void SelectMonitor_CancelRetainsPreviousDisplayAndRestoresMasks()
    {
        var config = DefaultConfig();
        var original = Connected(config.Display);
        var replacement = original with
        {
            StableId = "replacement",
            Name = "Replacement",
            FullBounds = new RectD(3440, 0, 1920, 1080),
            WorkArea = new RectD(3440, 0, 1920, 1040),
            Width = 1920,
            Height = 1080,
        };
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [original, replacement]);
        harness.Controller.Start();

        harness.Controller.SelectMonitor();
        harness.Picker.Select(replacement);
        harness.Calibration.Cancel();

        Assert.Equal(config.Display, harness.Controller.State.Configuration!.Display);
        Assert.Equal(0, harness.Config.SaveCount);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
    }

    [Fact]
    public void Calibrate_CheckedCommandCancelsAndRestoresProtection()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();

        harness.Controller.Calibrate();
        Assert.True(harness.Calibration.IsEditing);

        harness.Controller.Calibrate();

        Assert.False(harness.Calibration.IsEditing);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
    }

    [Fact]
    public void Calibration_SaveFailureKeepsEditorLive()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();
        harness.Config.ThrowOnSave = true;

        harness.Calibration.Save(config.Bands);

        Assert.True(harness.Calibration.IsEditing);
        Assert.Equal(config, harness.Controller.State.Configuration);
    }

    [Fact]
    public void Disable_PersistsBeforeClosingMasksAndCancelsEditing()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();

        harness.Controller.ToggleEnabled();

        Assert.False(harness.Config.LastSaved!.Enabled);
        Assert.False(harness.Calibration.IsEditing);
        Assert.True(harness.Overlays.ClearCount >= 2);
    }

    [Fact]
    public void EnableWithoutSavedDisplay_OpensMonitorSelection()
    {
        var harness = new Harness(new ConfigLoadResult(null, true, null));
        harness.Controller.Start();

        harness.Controller.ToggleEnabled();

        Assert.NotNull(harness.Picker.SelectedCallback);
        Assert.Equal(0, harness.Config.SaveCount);
    }

    [Fact]
    public void ResetDefaults_PreservesEnabledAndRestoresExactPermanentBands()
    {
        var config = DefaultConfig() with
        {
            Enabled = false,
            Bands =
            [
                new RectD(0.1, 0, 0.2, 0.3),
                new RectD(0.1, 0.3, 0.2, 0.4),
                new RectD(0.1, 0.7, 0.2, 0.3),
            ],
        };
        var display = Connected(config.Display);
        var harness = new Harness(new ConfigLoadResult(config, false, null), [display]);
        harness.Controller.Start();

        harness.Controller.ResetDefaults();

        var saved = Assert.IsType<ScreenFixConfig>(harness.Config.LastSaved);
        Assert.False(saved.Enabled);
        Assert.Equal(DefaultConfiguration.Create(config.Display).Bands, saved.Bands);
    }

    [Fact]
    public void ResetDefaults_DisconnectedDisplayCannotMutateStorage()
    {
        var harness = new Harness(new ConfigLoadResult(DefaultConfig(), false, null));
        harness.Controller.Start();

        harness.Controller.ResetDefaults();

        Assert.Equal(0, harness.Config.SaveCount);
    }

    [Fact]
    public void ResetDefaults_RereadsLiveDisconnectBeforePersisting()
    {
        var config = DefaultConfig();
        var original = Connected(config.Display);
        var harness = new Harness(new ConfigLoadResult(config, false, null), [original]);
        harness.Controller.Start();
        harness.Topology.Displays = [];

        harness.Controller.ResetDefaults();

        Assert.Equal(0, harness.Config.SaveCount);
        Assert.Null(harness.Controller.State.ConnectedDisplay);
    }

    [Fact]
    public void Reload_InvalidCandidateKeepsCommittedConfigurationAndMasks()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Config.LoadResult = new ConfigLoadResult(null, false, "invalid");

        harness.Controller.Reload();

        Assert.Equal(config, harness.Controller.State.Configuration);
        Assert.Single(harness.Overlays.Replacements);
        Assert.Equal("Paused: Invalid configuration", harness.StatusLabel);
    }

    [Fact]
    public void Reload_ValidCandidateReconcilesNewNormalizedBands()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        var changed = config with
        {
            Bands =
            [
                new RectD(0.1, 0, 0.2, 0.3),
                new RectD(0.1, 0.3, 0.2, 0.4),
                new RectD(0.1, 0.7, 0.2, 0.3),
            ],
        };
        harness.Config.LoadResult = new ConfigLoadResult(changed, false, null);

        harness.Controller.Reload();

        Assert.Equal(changed, harness.Controller.State.Configuration);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
        Assert.Equal(344, harness.Overlays.Replacements[1][0].X);
    }

    [Fact]
    public void MaskFailure_ReportsOncePerEpisodeAndRecoveryAllowsLaterNotice()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Overlays.NextResult = RuntimeOperationResult.Failure("render failed");

        harness.Controller.ReconcileDisplays();
        harness.Controller.ReconcileDisplays();

        Assert.Single(harness.Notices.Messages);
        Assert.Equal("Paused: Mask rendering failed", harness.StatusLabel);

        harness.Overlays.NextResult = RuntimeOperationResult.Success();
        harness.Controller.ReconcileDisplays();
        harness.Overlays.NextResult = RuntimeOperationResult.Failure("render failed again");
        harness.Controller.ReconcileDisplays();

        Assert.Equal(2, harness.Notices.Messages.Count);
    }

    [Fact]
    public void Calibration_InvalidSaveKeepsEditorAndStorageUntouched()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();

        harness.Calibration.Save(config.Bands.Take(2).ToArray());

        Assert.True(harness.Calibration.IsEditing);
        Assert.Equal(0, harness.Config.SaveCount);
        Assert.Single(harness.Notices.Messages);
    }

    [Fact]
    public void ReconcileDisplays_WhileEditingCancelsWorkingCopyAndRestoresMasks()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();

        harness.Controller.ReconcileDisplays();

        Assert.False(harness.Calibration.IsEditing);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
        Assert.Equal(0, harness.Config.SaveCount);
    }

    [Fact]
    public void ReconcileDisplays_DisconnectClearsMasksAndUniqueReconnectRestoresThem()
    {
        var config = DefaultConfig();
        var display = Connected(config.Display);
        var harness = new Harness(new ConfigLoadResult(config, false, null), [display]);
        harness.Controller.Start();

        harness.Topology.Displays = [];
        harness.Controller.ReconcileDisplays();
        harness.Topology.Displays = [display];
        harness.Controller.ReconcileDisplays();

        Assert.True(harness.Overlays.ClearCount >= 1);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
    }

    [Fact]
    public void CancelEditorForDpiChange_DiscardsWorkingCopyAndRestoresMasks()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();

        harness.Controller.CancelEditorForDpiChange();

        Assert.False(harness.Calibration.IsEditing);
        Assert.Equal(0, harness.Config.SaveCount);
        Assert.Equal(2, harness.Overlays.Replacements.Count);
    }

    [Fact]
    public void DeferredOldEditorDpiChange_CannotCancelReplacementEditor()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        var dispatcher = new DeferredDispatcher();
        var coordinator = new SystemMessageCoordinator(harness.Controller, dispatcher, generation: 1);
        harness.Controller.Start();
        harness.Controller.Calibrate();
        var oldEditorGeneration = harness.Calibration.Request!.Generation;
        coordinator.HandleEditorDpiChanged(oldEditorGeneration, callbackGeneration: 1);

        harness.Controller.Calibrate();
        harness.Controller.Calibrate();
        var replacementGeneration = harness.Calibration.Request!.Generation;
        dispatcher.RunAll();

        Assert.NotEqual(oldEditorGeneration, replacementGeneration);
        Assert.True(harness.Calibration.IsEditing);
        Assert.Equal(replacementGeneration, harness.Calibration.Request.Generation);
    }

    [Fact]
    public void SuspendAndResume_CloseTransientResourcesThenRestoreMasksOnce()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();

        harness.Controller.Suspend();
        harness.Controller.Suspend();

        Assert.False(harness.Calibration.IsEditing);
        Assert.Equal(0, harness.Config.SaveCount);
        Assert.True(harness.Overlays.ClearCount >= 2);

        harness.Controller.Resume();
        harness.Controller.Resume();

        Assert.Equal(2, harness.Overlays.Replacements.Count);
    }

    [Fact]
    public void StalePickerCallbackCannotStartCalibration()
    {
        var display = Connected(DefaultConfig().Display);
        var harness = new Harness(new ConfigLoadResult(null, true, null), [display]);
        harness.Controller.Start();
        harness.Controller.SelectMonitor();
        var staleCallback = harness.Picker.SelectedCallback!;
        var staleGeneration = harness.Picker.Generation;

        harness.Controller.SelectMonitor();
        staleCallback(staleGeneration, display);

        Assert.False(harness.Calibration.IsEditing);
        Assert.Equal(0, harness.Config.SaveCount);
    }

    [Fact]
    public void StaleEditorCallbackCannotAlterNewerGeneration()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();
        var staleSave = harness.Calibration.SaveCallback!;
        var staleGeneration = harness.Calibration.Request!.Generation;

        harness.Controller.Calibrate();
        staleSave(staleGeneration, config.Bands);

        Assert.Equal(0, harness.Config.SaveCount);
    }

    [Fact]
    public void Stop_IsIdempotentAndMakesLateCallbacksInert()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();
        var staleSave = harness.Calibration.SaveCallback!;
        var staleGeneration = harness.Calibration.Request!.Generation;

        harness.Controller.Stop();
        harness.Controller.Stop();
        staleSave(staleGeneration, config.Bands);

        Assert.True(harness.Controller.State.IsStopped);
        Assert.Equal(0, harness.Config.SaveCount);
        Assert.Equal(1, harness.Calibration.StopCount);
    }

    [Fact]
    public void RevokeCallbacks_InvalidatesLateCallbacksWithoutOwningEditorOrMasks()
    {
        var config = DefaultConfig();
        var harness = new Harness(
            new ConfigLoadResult(config, false, null),
            [Connected(config.Display)]);
        harness.Controller.Start();
        harness.Controller.Calibrate();
        var staleSave = harness.Calibration.SaveCallback!;
        var staleGeneration = harness.Calibration.Request!.Generation;

        harness.Controller.RevokeCallbacks();
        staleSave(staleGeneration, config.Bands);

        Assert.True(harness.Controller.State.IsStopped);
        Assert.True(harness.Calibration.IsEditing);
        Assert.Equal(0, harness.Config.SaveCount);
    }

    private static ScreenFixConfig DefaultConfig() => DefaultConfiguration.Create(
        new DisplayIdentity("display-path", "Ultrawide", 3440, 1440));

    private static ConnectedDisplay Connected(DisplayIdentity identity) => new(
        identity.StableId,
        identity.Name,
        checked((int)identity.Width),
        checked((int)identity.Height),
        new RectD(0, 0, identity.Width, identity.Height),
        new RectD(0, 0, identity.Width, identity.Height - 40));

    private sealed class Harness
    {
        public Harness(
            ConfigLoadResult loadResult,
            IReadOnlyList<ConnectedDisplay>? displays = null)
        {
            Config = new FakeConfigStore(loadResult);
            Topology = new FakeTopology(displays ?? []);
            Overlays = new FakeOverlayHost();
            Menu = new FakeMenuHost();
            Notices = new FakeNoticeSink();
            Calibration = new FakeCalibrationHost();
            Picker = new FakePickerHost();
            Controller = new RuntimeController(
                Config,
                Topology,
                Overlays,
                Calibration,
                Picker,
                Menu,
                new FakeUiThread(),
                Notices,
                new FakeClock());
        }

        public FakeConfigStore Config { get; }

        public FakeTopology Topology { get; }

        public FakeOverlayHost Overlays { get; }

        public FakeMenuHost Menu { get; }

        public FakeNoticeSink Notices { get; }

        public FakeCalibrationHost Calibration { get; }

        public FakePickerHost Picker { get; }

        public RuntimeController Controller { get; }

        public string? StatusLabel => Menu.Rows.SingleOrDefault(row =>
            row.Label.StartsWith("Paused:", StringComparison.Ordinal))?.Label;
    }

    private sealed class FakeConfigStore(ConfigLoadResult loadResult) : IRuntimeConfigStore
    {
        public ConfigLoadResult LoadResult { get; set; } = loadResult;

        public int SaveCount { get; private set; }

        public bool ThrowOnSave { get; set; }

        public ScreenFixConfig? LastSaved { get; private set; }

        public ConfigLoadResult Load() => LoadResult;

        public void Save(ScreenFixConfig value)
        {
            if (ThrowOnSave)
            {
                throw new IOException("save failed");
            }

            SaveCount++;
            LastSaved = value;
            LoadResult = new ConfigLoadResult(value, false, null);
        }
    }

    private sealed class FakeTopology(IReadOnlyList<ConnectedDisplay> displays) : IDisplayTopology
    {
        public IReadOnlyList<ConnectedDisplay> Displays { get; set; } = displays;

        public IReadOnlyList<ConnectedDisplay> Enumerate() => Displays;
    }

    private sealed class FakeOverlayHost : IMaskOverlayHost
    {
        public List<IReadOnlyList<RectD>> Replacements { get; } = [];

        public int ClearCount { get; private set; }

        public RuntimeOperationResult NextResult { get; set; } = RuntimeOperationResult.Success();

        public RuntimeOperationResult Replace(IReadOnlyList<RectD> frames)
        {
            Replacements.Add(frames);
            return NextResult;
        }

        public void Clear()
        {
            ClearCount++;
        }
    }

    private sealed class FakeCalibrationHost : ICalibrationHost
    {
        public bool IsEditing { get; private set; }

        public CalibrationStartRequest? Request { get; private set; }

        public Action<long, IReadOnlyList<RectD>>? SaveCallback { get; private set; }

        public Action<long>? CancelCallback { get; private set; }

        public int StopCount { get; private set; }

        public RuntimeOperationResult Start(
            CalibrationStartRequest request,
            CalibrationHostCallbacks callbacks)
        {
            Request = request;
            SaveCallback = callbacks.Save;
            CancelCallback = callbacks.Cancel;
            IsEditing = true;
            return RuntimeOperationResult.Success();
        }

        public void Stop()
        {
            if (!IsEditing)
            {
                return;
            }

            StopCount++;
            IsEditing = false;
        }

        public void Save(IReadOnlyList<RectD> bands) =>
            SaveCallback!(Request!.Generation, bands);

        public void Cancel() => CancelCallback!(Request!.Generation);
    }

    private sealed class FakePickerHost : IMonitorPickerHost
    {
        public long Generation { get; private set; }

        public Action<long, ConnectedDisplay>? SelectedCallback { get; private set; }

        public Action<long>? CancelledCallback { get; private set; }

        public RuntimeOperationResult Start(
            long generation,
            IReadOnlyList<ConnectedDisplay> displays,
            Action<long, ConnectedDisplay> selected,
            Action<long> cancelled)
        {
            Generation = generation;
            SelectedCallback = selected;
            CancelledCallback = cancelled;
            return RuntimeOperationResult.Success();
        }

        public void Stop()
        {
        }

        public void Select(ConnectedDisplay display) => SelectedCallback!(Generation, display);
    }

    private sealed class FakeMenuHost : IMenuHost
    {
        public IReadOnlyList<MenuRow> Rows { get; private set; } = [];

        public void Refresh(IReadOnlyList<MenuRow> rows) => Rows = rows;
    }

    private sealed class FakeUiThread : IUiThread
    {
        public void VerifyAccess()
        {
        }
    }

    private sealed class DeferredDispatcher : IUiDispatcher
    {
        private readonly List<Action> pending = [];

        public void Post(Action action) => pending.Add(action);

        public void RunAll()
        {
            var actions = pending.ToArray();
            pending.Clear();
            foreach (var action in actions)
            {
                action();
            }
        }
    }

    private sealed class FakeNoticeSink : INoticeSink
    {
        public List<string> Messages { get; } = [];

        public void Show(string message) => Messages.Add(message);
    }

    private sealed class FakeClock : IClock
    {
        public DateTimeOffset UtcNow => DateTimeOffset.UnixEpoch;
    }
}
