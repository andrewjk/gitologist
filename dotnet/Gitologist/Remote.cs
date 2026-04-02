using System.Text.RegularExpressions;

namespace Gitologist;

public static class Remote
{
    public static async Task AddRemote(string path, string name, string url)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var configPath = Path.Combine(gitDir, "config");
        string configContent = "";

        if (File.Exists(configPath))
        {
            configContent = await File.ReadAllTextAsync(configPath);
        }

        var remotePattern = new Regex(
            $@"\[remote\s+""{name}""\]",
            RegexOptions.Multiline
        );

        if (remotePattern.IsMatch(configContent))
        {
            throw new InvalidOperationException($"Remote '{name}' already exists");
        }

        var remoteConfig =
            $"[remote \"{name}\"]\n\turl = {url}\n\tfetch = +refs/heads/*:refs/remotes/{name}/*";

        configContent = configContent.Trim() + "\n\n" + remoteConfig.Trim() + "\n";

        await File.WriteAllTextAsync(configPath, configContent);
    }
}
