namespace Gitologist.Types;

public record class LogEntry
{
    public required string Sha { get; init; }
    public required string AbbreviatedSha { get; init; }
    public required string Tree { get; init; }
    public string? Parent { get; init; }
    public required string Author { get; init; }
    public required string Committer { get; init; }
    public required DateTime Date { get; init; }
    public required string Message { get; init; }
}
