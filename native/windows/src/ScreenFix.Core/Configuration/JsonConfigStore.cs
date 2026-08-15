using System.Text.Json;

namespace ScreenFix.Core.Configuration;

public sealed record ConfigLoadResult(ScreenFixConfig? Value, bool IsMissing, string? Error);

public sealed class JsonConfigStore(string path)
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public ConfigLoadResult Load()
    {
        if (!File.Exists(path))
        {
            return new ConfigLoadResult(null, true, null);
        }

        try
        {
            using var stream = File.OpenRead(path);
            var value = JsonSerializer.Deserialize<ScreenFixConfig>(stream, SerializerOptions);
            var validation = ConfigValidator.Validate(value);
            return validation.IsValid
                ? new ConfigLoadResult(value, false, null)
                : new ConfigLoadResult(null, false, validation.Error);
        }
        catch (JsonException)
        {
            return new ConfigLoadResult(null, false, "configuration JSON is invalid");
        }
    }

    public void Save(ScreenFixConfig value)
    {
        var validation = ConfigValidator.Validate(value);
        if (!validation.IsValid)
        {
            throw new ArgumentException(validation.Error, nameof(value));
        }

        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        var temporaryPath = path + ".tmp";
        try
        {
            using (var stream = new FileStream(
                temporaryPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None))
            {
                JsonSerializer.Serialize(stream, value, SerializerOptions);
                stream.Flush(flushToDisk: true);
            }

            File.Move(temporaryPath, path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }
}
