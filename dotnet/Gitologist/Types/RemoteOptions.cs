namespace Gitologist.Types;

public class Credentials
{
    public string Username { get; set; } = null!;
    public string Token { get; set; } = null!;
}

public class RemoteOptions
{
    public Credentials? Credentials { get; set; }
}
