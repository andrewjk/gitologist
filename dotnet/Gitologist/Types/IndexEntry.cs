namespace Gitologist.Types;

public record class IndexEntry
{
    public required string Path { get; init; }
    public required string Sha { get; init; }
    public required string Mode { get; init; }
}
