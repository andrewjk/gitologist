namespace Gitologist.Types;

public record class StatusInfo
{
    public required string Branch { get; init; }
    public required string UpToDate { get; init; }
    public required string[] Staged { get; init; }
    public required string[] Modified { get; init; }
    public required string[] Untracked { get; init; }
    public required string[] Deleted { get; init; }
}
