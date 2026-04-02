namespace Gitologist.Types;

public record class TreeEntry
{
    public required string Path { get; init; }
    public required string Sha { get; init; }
    public required string Mode { get; init; }
    public required string Type { get; init; }
}
