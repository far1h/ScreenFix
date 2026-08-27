using System.Globalization;
using System.Runtime.ExceptionServices;
using Xunit.Abstractions;

namespace ScreenFix.Windows.Tests.Startup;

public sealed class StartupMeasurementMathTests
{
    [Fact]
    public void MedianReturnsTheMiddleOddSampleAfterSorting()
    {
        var samples = new[]
        {
            TimeSpan.FromMilliseconds(30),
            TimeSpan.FromMilliseconds(10),
            TimeSpan.FromMilliseconds(20),
        };

        Assert.Equal(TimeSpan.FromMilliseconds(20), StartupMeasurementMath.Median(samples));
    }

    [Fact]
    public void MedianAveragesTheTwoMiddleEvenSamplesWithoutOverflow()
    {
        var samples = new[]
        {
            TimeSpan.MaxValue,
            TimeSpan.MaxValue - TimeSpan.FromTicks(2),
        };

        Assert.Equal(
            TimeSpan.MaxValue - TimeSpan.FromTicks(1),
            StartupMeasurementMath.Median(samples));
    }

    [Fact]
    public void FirstStartUsesRelativeAndStrictAbsoluteLimits()
    {
        var baseline = TimeSpan.FromSeconds(1);
        var passing = StartupMeasurementMath.Evaluate(
            StartupMeasurementPhase.First,
            baseline,
            TimeSpan.FromMilliseconds(1_750));
        var absoluteFailure = StartupMeasurementMath.Evaluate(
            StartupMeasurementPhase.First,
            baseline,
            TimeSpan.FromSeconds(5));

        Assert.Equal(TimeSpan.FromMilliseconds(1_750), passing.RelativeLimit);
        Assert.Equal(TimeSpan.FromSeconds(5), passing.AbsoluteLimit);
        Assert.True(passing.Passed);
        Assert.False(absoluteFailure.Passed);
    }

    [Fact]
    public void FirstStartUsesSeventyFivePercentWhenItExceedsTheFloor()
    {
        var result = StartupMeasurementMath.Evaluate(
            StartupMeasurementPhase.First,
            TimeSpan.FromSeconds(2),
            TimeSpan.FromSeconds(3.5));

        Assert.Equal(TimeSpan.FromSeconds(3.5), result.RelativeLimit);
        Assert.True(result.Passed);
    }

    [Fact]
    public void WarmStartUsesRelativeAndStrictAbsoluteLimits()
    {
        var baseline = TimeSpan.FromMilliseconds(400);
        var relativeFailure = StartupMeasurementMath.Evaluate(
            StartupMeasurementPhase.Warm,
            baseline,
            TimeSpan.FromMilliseconds(651));
        var absoluteFailure = StartupMeasurementMath.Evaluate(
            StartupMeasurementPhase.Warm,
            baseline,
            TimeSpan.FromSeconds(2));

        Assert.Equal(TimeSpan.FromMilliseconds(650), relativeFailure.RelativeLimit);
        Assert.Equal(TimeSpan.FromSeconds(2), relativeFailure.AbsoluteLimit);
        Assert.False(relativeFailure.Passed);
        Assert.False(absoluteFailure.Passed);
    }

    [Fact]
    public void WarmStartUsesFiftyPercentWhenItExceedsTheFloor()
    {
        var result = StartupMeasurementMath.Evaluate(
            StartupMeasurementPhase.Warm,
            TimeSpan.FromSeconds(1),
            TimeSpan.FromMilliseconds(1_499));

        Assert.Equal(TimeSpan.FromMilliseconds(1_500), result.RelativeLimit);
        Assert.True(result.Passed);
    }

    [Theory]
    [InlineData(StartupMeasurementPhase.First)]
    [InlineData(StartupMeasurementPhase.Warm)]
    public void RelativeLimitSaturatesInsteadOfOverflowing(StartupMeasurementPhase phase)
    {
        var result = StartupMeasurementMath.Evaluate(
            phase,
            TimeSpan.MaxValue - TimeSpan.FromTicks(1),
            TimeSpan.Zero);

        Assert.Equal(TimeSpan.MaxValue, result.RelativeLimit);
    }
}

public sealed class StartupMeasurementPlanTests
{
    [Fact]
    public void FirstStartsAlternateAndUseTenFreshVariantPaths()
    {
        var launches = new List<(string Variant, string Path)>();

        var samples = StartupMeasurementPlan.MeasureFirst(
            (variant, path) =>
            {
                launches.Add((variant, path));
                return TimeSpan.FromMilliseconds(launches.Count);
            },
            (variant, index) => $"first-{variant}-{index}");

        Assert.Equal(
            new[]
            {
                "uncompressed", "compressed",
                "compressed", "uncompressed",
                "uncompressed", "compressed",
                "compressed", "uncompressed",
                "uncompressed", "compressed",
            },
            launches.Select(item => item.Variant));
        Assert.Equal(10, launches.Select(item => item.Path).Distinct().Count());
        Assert.Equal(5, samples.Baseline.Count);
        Assert.Equal(5, samples.Candidate.Count);
    }

    [Fact]
    public void WarmStartsSeedOnceThenAlternateFiveMeasurementsPerVariant()
    {
        var launches = new List<(string Variant, string Path)>();

        var samples = StartupMeasurementPlan.MeasureWarm(
            (variant, path) =>
            {
                launches.Add((variant, path));
                return TimeSpan.FromMilliseconds(launches.Count);
            },
            variant => "warm-" + variant);

        Assert.Equal(12, launches.Count);
        Assert.Equal(new[] { "uncompressed", "compressed" }, launches.Take(2).Select(item => item.Variant));
        Assert.Equal(
            new[]
            {
                "uncompressed", "compressed",
                "compressed", "uncompressed",
                "uncompressed", "compressed",
                "compressed", "uncompressed",
                "uncompressed", "compressed",
            },
            launches.Skip(2).Select(item => item.Variant));
        Assert.All(
            launches.GroupBy(item => item.Variant),
            group => Assert.Single(group.Select(item => item.Path).Distinct()));
        Assert.Equal(5, samples.Baseline.Count);
        Assert.Equal(5, samples.Candidate.Count);
    }

}

public enum StartupMeasurementPhase
{
    First,
    Warm,
}

internal readonly record struct StartupMeasurementEvaluation(
    TimeSpan RelativeLimit,
    TimeSpan AbsoluteLimit,
    bool Passed);

internal static class StartupMeasurementMath
{
    internal static TimeSpan Median(IReadOnlyCollection<TimeSpan> samples)
    {
        ArgumentNullException.ThrowIfNull(samples);
        if (samples.Count == 0)
        {
            throw new ArgumentException("At least one startup sample is required.", nameof(samples));
        }

        var ticks = samples.Select(sample => sample.Ticks).Order().ToArray();
        if (ticks[0] < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(samples));
        }

        var upper = ticks[ticks.Length / 2];
        if (ticks.Length % 2 != 0)
        {
            return TimeSpan.FromTicks(upper);
        }

        var lower = ticks[(ticks.Length / 2) - 1];
        return TimeSpan.FromTicks(lower + ((upper - lower) / 2));
    }

    internal static StartupMeasurementEvaluation Evaluate(
        StartupMeasurementPhase phase,
        TimeSpan baseline,
        TimeSpan candidate)
    {
        if (baseline < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(baseline));
        }

        if (candidate < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(candidate));
        }

        var settings = phase switch
        {
            StartupMeasurementPhase.First => (
                Floor: TimeSpan.FromMilliseconds(750),
                Numerator: 3,
                Denominator: 4,
                Absolute: TimeSpan.FromSeconds(5)),
            StartupMeasurementPhase.Warm => (
                Floor: TimeSpan.FromMilliseconds(250),
                Numerator: 1,
                Denominator: 2,
                Absolute: TimeSpan.FromSeconds(2)),
            _ => throw new ArgumentOutOfRangeException(nameof(phase)),
        };
        var scaledTicks = (long)Math.Min(
            TimeSpan.MaxValue.Ticks,
            decimal.Ceiling(
                (decimal)baseline.Ticks * settings.Numerator / settings.Denominator));
        var marginTicks = Math.Max(settings.Floor.Ticks, scaledTicks);
        var relativeTicks = baseline.Ticks > TimeSpan.MaxValue.Ticks - marginTicks
            ? TimeSpan.MaxValue.Ticks
            : baseline.Ticks + marginTicks;
        var relative = TimeSpan.FromTicks(relativeTicks);

        return new StartupMeasurementEvaluation(
            relative,
            settings.Absolute,
            candidate <= relative && candidate < settings.Absolute);
    }
}

internal sealed record StartupSamples(
    IReadOnlyList<TimeSpan> Baseline,
    IReadOnlyList<TimeSpan> Candidate);

internal static class StartupMeasurementPlan
{
    internal const string Baseline = "uncompressed";
    internal const string Candidate = "compressed";

    internal static StartupSamples MeasureFirst(
        Func<string, string, TimeSpan> launch,
        Func<string, int, string> createExtractionPath)
    {
        var baseline = new List<TimeSpan>(5);
        var candidate = new List<TimeSpan>(5);
        for (var index = 0; index < 5; index++)
        {
            var order = index % 2 == 0
                ? new[] { Baseline, Candidate }
                : new[] { Candidate, Baseline };
            foreach (var variant in order)
            {
                AddSample(
                    variant,
                    launch(variant, createExtractionPath(variant, index)),
                    baseline,
                    candidate);
            }
        }

        return new StartupSamples(baseline, candidate);
    }

    internal static StartupSamples MeasureWarm(
        Func<string, string, TimeSpan> launch,
        Func<string, string> createExtractionPath)
    {
        var paths = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [Baseline] = createExtractionPath(Baseline),
            [Candidate] = createExtractionPath(Candidate),
        };
        _ = launch(Baseline, paths[Baseline]);
        _ = launch(Candidate, paths[Candidate]);

        var baseline = new List<TimeSpan>(5);
        var candidate = new List<TimeSpan>(5);
        for (var index = 0; index < 5; index++)
        {
            var order = index % 2 == 0
                ? new[] { Baseline, Candidate }
                : new[] { Candidate, Baseline };
            foreach (var variant in order)
            {
                AddSample(
                    variant,
                    launch(variant, paths[variant]),
                    baseline,
                    candidate);
            }
        }

        return new StartupSamples(baseline, candidate);
    }

    private static void AddSample(
        string variant,
        TimeSpan elapsed,
        List<TimeSpan> baseline,
        List<TimeSpan> candidate)
    {
        (variant == Baseline ? baseline : candidate).Add(elapsed);
    }
}

internal sealed class StartupLaunchCoordinator
{
    private readonly ScreenFixConfigurationTransaction configuration;
    private readonly BundleExtractionTransaction extraction;

    internal StartupLaunchCoordinator(
        ScreenFixConfigurationTransaction configuration,
        BundleExtractionTransaction extraction)
    {
        this.configuration = configuration
            ?? throw new ArgumentNullException(nameof(configuration));
        this.extraction = extraction
            ?? throw new ArgumentNullException(nameof(extraction));
    }

    internal TimeSpan Run(
        string executable,
        string extractionPath,
        TimeSpan timeout)
    {
        var request = new ConfigurationLaunchRequest(executable, extractionPath);
        extraction.RecordChildStarted();
        TimeSpan elapsed;
        try
        {
            elapsed = configuration.RunLaunch(request, timeout);
        }
        catch (Exception error)
        {
            if (configuration.CanCleanExternalState)
            {
                extraction.RecordChildExitProven();
            }
            else
            {
                extraction.RecordRecoveryFailure(error);
            }

            throw;
        }

        extraction.RecordChildExitProven();
        return elapsed;
    }
}

internal static class StartupTransactionCleanup
{
    internal static Exception? DisposeAndCombine(
        IDisposable? transaction,
        Exception? failure)
    {
        if (transaction is null)
        {
            return failure;
        }

        try
        {
            transaction.Dispose();
            return failure;
        }
        catch (Exception cleanupError)
        {
            return failure is null
                ? cleanupError
                : new AggregateException(failure, cleanupError);
        }
    }
}

[Collection(ProductionMutexCollection.Name)]
[Trait("ScreenFixCategory", "DisposableAccount")]
[Trait("ScreenFixStartup", "Measurement")]
public sealed class PublishedExecutableStartupTests
{
    private static readonly TimeSpan LaunchTimeout = TimeSpan.FromSeconds(10);

    private readonly ITestOutputHelper output;

    public PublishedExecutableStartupTests(ITestOutputHelper output)
    {
        this.output = output;
    }

    [Fact]
    public void StagedExecutablesMeetFirstAndWarmStartupLimits()
    {
        var inputs = StartupMeasurementInputs.FromEnvironment();
        var configuration = new ScreenFixConfigurationTransaction(
            allowDisposableAccountMutation: true);
        BundleExtractionTransaction? extraction = null;
        Exception? failure = null;
        try
        {
            extraction = new BundleExtractionTransaction(
                allowDisposableAccountMutation: true,
                inputs.RunnerTemp);
            Measure(configuration, extraction, inputs);
        }
        catch (Exception error)
        {
            failure = error;
        }
        finally
        {
            failure = StartupTransactionCleanup.DisposeAndCombine(extraction, failure);
            failure = StartupTransactionCleanup.DisposeAndCombine(configuration, failure);
        }

        if (failure is not null)
        {
            ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }

    private void Measure(
        ScreenFixConfigurationTransaction configuration,
        BundleExtractionTransaction extraction,
        StartupMeasurementInputs inputs)
    {
        var coordinator = new StartupLaunchCoordinator(configuration, extraction);
        var first = StartupMeasurementPlan.MeasureFirst(
            (variant, extractionPath) => coordinator.Run(
                inputs.ExecutableFor(variant),
                extractionPath,
                LaunchTimeout),
            extraction.CreateFirstExtractionPath);
        var warm = StartupMeasurementPlan.MeasureWarm(
            (variant, extractionPath) => coordinator.Run(
                inputs.ExecutableFor(variant),
                extractionPath,
                LaunchTimeout),
            extraction.CreateWarmExtractionPath);

        var firstEvaluation = WriteReport(StartupMeasurementPhase.First, first);
        var warmEvaluation = WriteReport(StartupMeasurementPhase.Warm, warm);
        Assert.True(firstEvaluation.Passed, FailureMessage(
            StartupMeasurementPhase.First,
            first,
            firstEvaluation));
        Assert.True(warmEvaluation.Passed, FailureMessage(
            StartupMeasurementPhase.Warm,
            warm,
            warmEvaluation));
    }

    private StartupMeasurementEvaluation WriteReport(
        StartupMeasurementPhase phase,
        StartupSamples samples)
    {
        var baselineMedian = StartupMeasurementMath.Median(samples.Baseline);
        var candidateMedian = StartupMeasurementMath.Median(samples.Candidate);
        var evaluation = StartupMeasurementMath.Evaluate(
            phase,
            baselineMedian,
            candidateMedian);
        var delta = candidateMedian - baselineMedian;
        var percent = baselineMedian == TimeSpan.Zero
            ? "undefined"
            : (delta.TotalMilliseconds / baselineMedian.TotalMilliseconds)
                .ToString("P2", CultureInfo.InvariantCulture);
        output.WriteLine(
            $"{phase} baseline samples ms: {FormatSamples(samples.Baseline)}");
        output.WriteLine(
            $"{phase} candidate samples ms: {FormatSamples(samples.Candidate)}");
        output.WriteLine(
            $"{phase} baseline median ms: {FormatMilliseconds(baselineMedian)}");
        output.WriteLine(
            $"{phase} candidate median ms: {FormatMilliseconds(candidateMedian)}");
        output.WriteLine(
            $"{phase} delta ms: {FormatMilliseconds(delta)} ({percent})");
        output.WriteLine(
            $"{phase} relative limit ms: {FormatMilliseconds(evaluation.RelativeLimit)}");
        output.WriteLine(
            $"{phase} absolute limit ms: {FormatMilliseconds(evaluation.AbsoluteLimit)} (strict)");
        return evaluation;
    }

    private static string FailureMessage(
        StartupMeasurementPhase phase,
        StartupSamples samples,
        StartupMeasurementEvaluation evaluation)
    {
        var baseline = StartupMeasurementMath.Median(samples.Baseline);
        var candidate = StartupMeasurementMath.Median(samples.Candidate);
        return
            $"{phase} startup failed: candidate {FormatMilliseconds(candidate)} ms; " +
            $"baseline {FormatMilliseconds(baseline)} ms; relative limit " +
            $"{FormatMilliseconds(evaluation.RelativeLimit)} ms; absolute limit " +
            $"{FormatMilliseconds(evaluation.AbsoluteLimit)} ms is strict.";
    }

    private static string FormatSamples(IEnumerable<TimeSpan> samples) =>
        "[" + string.Join(", ", samples.Select(FormatMilliseconds)) + "]";

    private static string FormatMilliseconds(TimeSpan value) =>
        value.TotalMilliseconds.ToString("F3", CultureInfo.InvariantCulture);
}

internal sealed record StartupMeasurementInputs(
    string RunnerTemp,
    string CompressedExecutable,
    string UncompressedExecutable)
{
    private const string CompressedName = "ScreenFix-Windows-x64.exe";
    private const string UncompressedName = "ScreenFix-Windows-x64-uncompressed.exe";

    internal static StartupMeasurementInputs FromEnvironment()
    {
        RequireExactEnvironment("SCREENFIX_ALLOW_DISPOSABLE_ACCOUNT_MUTATION", "true");
        RequireExactEnvironment("CI", "true");
        RequireExactEnvironment("GITHUB_ACTIONS", "true");
        RequireExactEnvironment("SCREENFIX_RUNNER_ENVIRONMENT", "github-hosted");

        var runnerTemp = BundleExtractionTransaction.ValidateRunnerTemp(
            RequireAbsoluteDirectory("RUNNER_TEMP"));
        var compressed = RequireExecutable(
            "SCREENFIX_STARTUP_COMPRESSED_EXE",
            CompressedName);
        var uncompressed = RequireExecutable(
            "SCREENFIX_STARTUP_UNCOMPRESSED_EXE",
            UncompressedName);
        return new StartupMeasurementInputs(runnerTemp, compressed, uncompressed);
    }

    internal string ExecutableFor(string variant) => variant switch
    {
        StartupMeasurementPlan.Baseline => UncompressedExecutable,
        StartupMeasurementPlan.Candidate => CompressedExecutable,
        _ => throw new ArgumentOutOfRangeException(nameof(variant)),
    };

    private static void RequireExactEnvironment(string name, string expected)
    {
        if (!string.Equals(
                Environment.GetEnvironmentVariable(name),
                expected,
                StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Startup measurement requires {name}={expected}.");
        }
    }

    private static string RequireAbsoluteDirectory(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrWhiteSpace(value) || !Path.IsPathFullyQualified(value))
        {
            throw new InvalidOperationException(
                $"Startup measurement requires an absolute {name}.");
        }

        var path = Path.GetFullPath(value);
        var attributes = File.GetAttributes(path);
        if ((attributes & FileAttributes.Directory) == 0
            || (attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new InvalidOperationException(
                $"Startup measurement requires a regular non-reparse {name} directory.");
        }

        return path;
    }

    private static string RequireExecutable(string variable, string expectedName)
    {
        var value = Environment.GetEnvironmentVariable(variable);
        if (string.IsNullOrWhiteSpace(value) || !Path.IsPathFullyQualified(value))
        {
            throw new InvalidOperationException(
                $"Startup measurement requires an absolute {variable}.");
        }

        var path = Path.GetFullPath(value);
        if (!string.Equals(Path.GetFileName(path), expectedName, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                $"Startup measurement requires exact staged filename {expectedName}.");
        }

        var file = new FileInfo(path);
        file.Refresh();
        if (!file.Exists
            || file.Length <= 0
            || (file.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
        {
            throw new InvalidOperationException(
                $"Startup measurement requires a regular nonempty non-reparse {expectedName}.");
        }

        return path;
    }
}
