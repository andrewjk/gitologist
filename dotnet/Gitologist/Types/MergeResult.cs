namespace Gitologist.Types;

public record class MergeResult
{
    public bool Success { get; init; }
    public bool FastForward { get; init; }
    public string? CommitSha { get; init; }
    public string? Message { get; init; }
}
