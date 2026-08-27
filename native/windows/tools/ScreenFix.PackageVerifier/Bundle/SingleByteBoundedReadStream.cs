namespace ScreenFix.PackageVerifier.Bundle;

internal sealed class SingleByteBoundedReadStream : Stream
{
    private readonly Stream _source;
    private readonly bool _leaveOpen;
    private bool _disposed;

    internal SingleByteBoundedReadStream(
        Stream source,
        long offset,
        long length,
        bool leaveOpen)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (!source.CanRead || !source.CanSeek)
        {
            throw new ArgumentException(
                "The source stream must be readable and seekable.",
                nameof(source));
        }

        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        ArgumentOutOfRangeException.ThrowIfNegative(length);
        if (offset > source.Length || length > source.Length - offset)
        {
            throw new ArgumentOutOfRangeException(
                nameof(length),
                "The bounded span must be inside the source stream.");
        }

        _source = source;
        _leaveOpen = leaveOpen;
        Remaining = length;
        _source.Position = offset;
    }

    internal long Consumed { get; private set; }

    internal long Remaining { get; private set; }

    public override bool CanRead => !_disposed && _source.CanRead;

    public override bool CanSeek => false;

    public override bool CanWrite => false;

    public override long Length => throw new NotSupportedException();

    public override long Position
    {
        get => throw new NotSupportedException();
        set => throw new NotSupportedException();
    }

    public override void Flush()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    public override int Read(byte[] buffer, int offset, int count)
    {
        ValidateBuffer(buffer, offset, count);
        return Read(buffer.AsSpan(offset, count));
    }

    public override int Read(Span<byte> buffer)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (buffer.Length == 0 || Remaining == 0)
        {
            return 0;
        }

        var read = _source.Read(buffer[..1]);
        RecordRead(read);
        return read;
    }

    public override int ReadByte()
    {
        Span<byte> value = stackalloc byte[1];
        return Read(value) == 0 ? -1 : value[0];
    }

    public override Task<int> ReadAsync(
        byte[] buffer,
        int offset,
        int count,
        CancellationToken cancellationToken)
    {
        ValidateBuffer(buffer, offset, count);
        return ReadAsync(
            buffer.AsMemory(offset, count),
            cancellationToken).AsTask();
    }

    public override async ValueTask<int> ReadAsync(
        Memory<byte> buffer,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (buffer.Length == 0 || Remaining == 0)
        {
            return 0;
        }

        var read = await _source
            .ReadAsync(buffer[..1], cancellationToken)
            .ConfigureAwait(false);
        RecordRead(read);
        return read;
    }

    public override long Seek(long offset, SeekOrigin origin)
    {
        throw new NotSupportedException();
    }

    public override void SetLength(long value)
    {
        throw new NotSupportedException();
    }

    public override void Write(byte[] buffer, int offset, int count)
    {
        throw new NotSupportedException();
    }

    public override void Write(ReadOnlySpan<byte> buffer)
    {
        throw new NotSupportedException();
    }

    public override ValueTask WriteAsync(
        ReadOnlyMemory<byte> buffer,
        CancellationToken cancellationToken = default)
    {
        return ValueTask.FromException(new NotSupportedException());
    }

    protected override void Dispose(bool disposing)
    {
        if (!_disposed && disposing && !_leaveOpen)
        {
            _source.Dispose();
        }

        _disposed = true;
        base.Dispose(disposing);
    }

    private void RecordRead(int read)
    {
        if (read == 0)
        {
            return;
        }

        Consumed += read;
        Remaining -= read;
    }

    private static void ValidateBuffer(byte[] buffer, int offset, int count)
    {
        ArgumentNullException.ThrowIfNull(buffer);
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        ArgumentOutOfRangeException.ThrowIfNegative(count);
        if (offset > buffer.Length - count)
        {
            throw new ArgumentException("The buffer range is invalid.");
        }
    }
}
