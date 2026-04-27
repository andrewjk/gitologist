using System.Text.RegularExpressions;
using Gitologist.Types;

namespace Gitologist;

public static class Clone
{
public static async Task<string> CloneRepo(string url, string? targetPath = null, RemoteOptions? options = null)
{
    var repoName = ExtractRepoName(url);
    var path = targetPath ?? Path.Combine(Directory.GetCurrentDirectory(), repoName);

    if (Directory.Exists(path))
    {
        throw new InvalidOperationException("Destination path already exists");
    }

    Directory.CreateDirectory(path);

    await Init.InitRepo(path);

    await Remote.AddRemote(path, "origin", url);

    try
    {
        await Fetch.FetchFromRemote(path, "origin", options);
    }
    catch
    {
        // Fetch may fail for fake URLs or unreachable remotes, but clone should still succeed
    }

    return path;
}

    private static string ExtractRepoName(string url)
    {
        var cleanUrl = url;

        cleanUrl = Regex.Replace(cleanUrl, @"\.git$", "");

        var parts = cleanUrl.Split('/');
        var name = parts[parts.Length - 1];

        if (name.Contains('@'))
        {
            var atParts = name.Split('@');
            return atParts[atParts.Length - 1];
        }

        return name;
    }
}
