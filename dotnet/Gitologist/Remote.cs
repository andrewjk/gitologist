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

    public static bool HasRemote(string path, string name = "origin")
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            return false;
        }

        var configPath = Path.Combine(gitDir, "config");

        if (!File.Exists(configPath))
        {
            return false;
        }

        try
        {
            var configContent = File.ReadAllText(configPath);
            var remotePattern = new Regex(
                $@"\[remote\s+""{name}""\]",
                RegexOptions.Multiline
            );
            return remotePattern.IsMatch(configContent);
        }
        catch
        {
            return false;
        }
    }

    public static async Task<string?> GetRemoteUrl(string gitDir, string remoteName)
    {
        var configPath = Path.Combine(gitDir, "config");

        if (!File.Exists(configPath))
        {
            return null;
        }

        var configContent = await File.ReadAllTextAsync(configPath);
        var lines = configContent.Split('\n');

        var inRemoteSection = false;
        var currentRemote = "";

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            var sectionMatch = Regex.Match(trimmed, @"^\[remote\s+""([^""]+)""\]");
            if (sectionMatch.Success)
            {
                inRemoteSection = true;
                currentRemote = sectionMatch.Groups[1].Value;
                continue;
            }

            if (inRemoteSection && currentRemote == remoteName)
            {
                var urlMatch = Regex.Match(trimmed, @"^url\s*=\s*(.+)$");
                if (urlMatch.Success)
                {
                    return urlMatch.Groups[1].Value.Trim();
                }
            }

            if (trimmed.StartsWith("[") && !trimmed.StartsWith("[remote"))
            {
                inRemoteSection = false;
            }
        }

        return null;
    }
}
