namespace Gitologist.Types;

public class LogOptions
{
    public int? Limit { get; set; }
    public bool Oneline { get; set; }
    public string? Branch { get; set; }
    public string? File { get; set; }
}
