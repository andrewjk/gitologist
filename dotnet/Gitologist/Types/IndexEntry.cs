namespace Gitologist.Types;

public record class IndexEntry
{
    public required string Path { get; init; }
    public required string Sha { get; init; }
    public required string Mode { get; init; }
    public required uint Size { get; init; }
    public required uint CtimeSeconds { get; init; }
    public required uint CtimeNanos { get; init; }
    public required uint MtimeSeconds { get; init; }
    public required uint MtimeNanos { get; init; }
    public required uint Dev { get; init; }
    public required uint Ino { get; init; }
    public required uint Uid { get; init; }
    public required uint Gid { get; init; }
}
