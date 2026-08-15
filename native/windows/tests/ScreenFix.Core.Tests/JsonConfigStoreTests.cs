using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using ScreenFix.Core.Configuration;

namespace ScreenFix.Core.Tests;

public sealed class JsonConfigStoreTests : IDisposable
{
    private readonly string directory;
    private readonly string path;

    public JsonConfigStoreTests()
    {
        directory = Path.Combine(Path.GetTempPath(), "ScreenFix.Tests", Guid.NewGuid().ToString("N"));
        path = Path.Combine(directory, "config.json");
        Directory.CreateDirectory(directory);
    }

    [Fact]
    public void Load_ReturnsMissingWithoutCreatingFile()
    {
        var result = new JsonConfigStore(path).Load();

        Assert.True(result.IsMissing);
        Assert.Null(result.Value);
        Assert.Null(result.Error);
        Assert.False(File.Exists(path));
    }

    [Fact]
    public void SaveThenLoad_RoundTripsCamelCaseJson()
    {
        var expected = ValidConfiguration();
        var store = new JsonConfigStore(path);

        store.Save(expected);
        var result = store.Load();

        Assert.False(result.IsMissing);
        Assert.Null(result.Error);
        Assert.NotNull(result.Value);
        Assert.Equal(expected.SchemaVersion, result.Value.SchemaVersion);
        Assert.Equal(expected.Enabled, result.Value.Enabled);
        Assert.Equal(expected.Display, result.Value.Display);
        Assert.Equal(expected.Bands, result.Value.Bands);

        var json = File.ReadAllText(path, Encoding.UTF8);
        Assert.Contains("\"schemaVersion\"", json, StringComparison.Ordinal);
        Assert.Contains("\"stableId\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("\"SchemaVersion\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public void Save_UsesExactBandPropertyNames()
    {
        new JsonConfigStore(path).Save(ValidConfiguration());

        using var document = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
        var band = document.RootElement.GetProperty("bands")[0];

        Assert.Equal(["x", "y", "w", "h"], band.EnumerateObject().Select(item => item.Name));
    }

    [Fact]
    public void Save_LeavesNoTemporaryFile()
    {
        new JsonConfigStore(path).Save(ValidConfiguration());

        Assert.False(File.Exists(path + ".tmp"));
    }

    [Fact]
    public void Load_InvalidJsonReturnsErrorWithoutChangingBytes()
    {
        byte[] original = "{ definitely-not-json"u8.ToArray();
        File.WriteAllBytes(path, original);

        var result = new JsonConfigStore(path).Load();

        Assert.False(result.IsMissing);
        Assert.Null(result.Value);
        Assert.Equal("configuration JSON is invalid", result.Error);
        Assert.Equal(original, File.ReadAllBytes(path));
    }

    [Fact]
    public void Load_StructurallyInvalidJsonReturnsValidatorErrorWithoutChangingBytes()
    {
        var store = new JsonConfigStore(path);
        store.Save(ValidConfiguration());
        var invalidJson = File.ReadAllText(path, Encoding.UTF8)
            .Replace("\"schemaVersion\": 1", "\"schemaVersion\": 2", StringComparison.Ordinal);
        File.WriteAllText(path, invalidJson, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        var original = File.ReadAllBytes(path);

        var result = store.Load();

        Assert.False(result.IsMissing);
        Assert.Null(result.Value);
        Assert.Equal("schema version must be 1", result.Error);
        Assert.Equal(original, File.ReadAllBytes(path));
    }

    [Theory]
    [InlineData("enabled")]
    [InlineData("band-x")]
    public void Load_RejectsMissingRequiredFields(string field)
    {
        var store = new JsonConfigStore(path);
        store.Save(ValidConfiguration());
        var root = JsonNode.Parse(File.ReadAllText(path, Encoding.UTF8))!.AsObject();
        if (field == "enabled")
        {
            root.Remove("enabled");
        }
        else
        {
            root["bands"]!.AsArray()[0]!.AsObject().Remove("x");
        }

        File.WriteAllText(
            path,
            root.ToJsonString(),
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

        var result = store.Load();

        Assert.False(result.IsMissing);
        Assert.Null(result.Value);
        Assert.Equal("configuration JSON is invalid", result.Error);
    }

    [Fact]
    public void Save_RejectsInvalidConfigurationBeforeCreatingOrReplacingFile()
    {
        var store = new JsonConfigStore(path);
        var invalid = ValidConfiguration() with { SchemaVersion = 2 };

        var createError = Assert.Throws<ArgumentException>(() => store.Save(invalid));
        Assert.Contains("schema version must be 1", createError.Message, StringComparison.Ordinal);
        Assert.False(File.Exists(path));

        store.Save(ValidConfiguration());
        var original = File.ReadAllBytes(path);
        Assert.Throws<ArgumentException>(() => store.Save(invalid));
        Assert.Equal(original, File.ReadAllBytes(path));
        Assert.False(File.Exists(path + ".tmp"));
    }

    public void Dispose()
    {
        Directory.Delete(directory, recursive: true);
    }

    private static ScreenFixConfig ValidConfiguration() => DefaultConfiguration.Create(
        new DisplayIdentity("display-1", "Ultrawide", 3440, 1440));
}
