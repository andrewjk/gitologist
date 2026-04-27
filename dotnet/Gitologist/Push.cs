using System.Text;
using System.Text.RegularExpressions;
using Gitologist.Types;

namespace Gitologist;

public static class Push
{
public static async Task PushToRemote(
    string path,
    string? remote = null,
    string? branch = null,
    RemoteOptions? options = null
)
{
    var gitDir = Path.Combine(path, ".git");

    if (!Directory.Exists(gitDir))
    {
        throw new InvalidOperationException("Not a git repository");
    }

    var remoteName = remote ?? "origin";
    var branchName = branch ?? await Utils.GetCurrentBranch(gitDir);

    var localBranchPath = Path.Combine(gitDir, "refs", "heads", branchName);
    if (!File.Exists(localBranchPath))
    {
        throw new InvalidOperationException(
            $"Local branch '{branchName}' does not exist"
        );
    }

    var currentStatus = await Status.GetStatus(path);

    if (
        currentStatus.Modified.Length > 0 ||
        currentStatus.Untracked.Length > 0 ||
        currentStatus.Deleted.Length > 0
    )
    {
        throw new InvalidOperationException(
            "You have uncommitted changes. Commit or stash them before pushing."
        );
    }

    var commitSha = (await File.ReadAllTextAsync(localBranchPath)).Trim();

    var remoteUrl = await Remote.GetRemoteUrl(gitDir, remoteName);

    if (remoteUrl != null && (remoteUrl.StartsWith("http://") || remoteUrl.StartsWith("https://")))
    {
        await PushToRemoteInternal(remoteUrl, commitSha, branchName, gitDir, options);
    }

    var remoteBranchPath = Path.Combine(
        gitDir,
        "refs",
        "remotes",
        remoteName,
        branchName
    );
    Directory.CreateDirectory(
        Path.GetDirectoryName(remoteBranchPath)!
    );
    await File.WriteAllTextAsync(remoteBranchPath, commitSha + "\n");
}

private static async Task PushToRemoteInternal(
    string remoteUrl,
    string commitSha,
    string branchName,
    string gitDir,
    RemoteOptions? options = null
)
{
    var oldSha = new string('0', 40);

    try
    {
        var remoteRefs = await DiscoverRefsForPush(remoteUrl, options);
        var remoteRef = remoteRefs.FirstOrDefault(r => r.Ref == $"refs/heads/{branchName}");
        if (remoteRef != null)
        {
            oldSha = remoteRef.Sha;
        }
    }
    catch
    {
        // If we can't discover refs, assume it's a new branch
    }

    var objects = await Objects.EnumerateObjects(gitDir, commitSha);

    var packfile = Packfile.CreatePackfile(objects);

    await SendPush(remoteUrl, oldSha, commitSha, branchName, packfile, options);
}

private static async Task<List<DiscoveredRef>> DiscoverRefsForPush(string remoteUrl, RemoteOptions? options = null)
{
    var url = new Uri(new Uri(remoteUrl), "info/refs?service=git-receive-pack");

    using var client = new HttpClient();
    client.DefaultRequestHeaders.Add("Accept", "application/x-git-receive-pack-advertisement");
    client.DefaultRequestHeaders.Add("Git-Protocol", "version=2");

    if (options?.Credentials != null)
    {
        var authString = $"{options.Credentials.Username}:{options.Credentials.Token}";
        var authBytes = Encoding.UTF8.GetBytes(authString);
        var base64Auth = Convert.ToBase64String(authBytes);
        client.DefaultRequestHeaders.Add("Authorization", $"Basic {base64Auth}");
    }

    var response = await client.GetAsync(url);
    if (response.StatusCode != System.Net.HttpStatusCode.OK)
    {
        return new List<DiscoveredRef>();
    }

    var data = await response.Content.ReadAsByteArrayAsync();
    var lines = Packfile.DecodePktLines(data);

    var refs = new List<DiscoveredRef>();
    var started = false;

    foreach (var line in lines)
    {
        if (line.Contains("# service=git-receive-pack"))
        {
            started = true;
            continue;
        }

        if (!started) continue;
        if (string.IsNullOrEmpty(line)) continue;

        var parts = line.Split(new[] { ' ' }, 2);
        if (parts.Length >= 2)
        {
            var sha = parts[0];
            if (sha.Length == 40 && sha.All(c => char.IsLetterOrDigit(c)))
            {
                var refName = parts[1].Split('\0')[0];
                refs.Add(new DiscoveredRef { Sha = sha, Ref = refName });
            }
        }
    }

    return refs;
}

private static async Task SendPush(
    string remoteUrl,
    string oldSha,
    string newSha,
    string branchName,
    byte[] packfile,
    RemoteOptions? options = null
)
{
    var url = new Uri(new Uri(remoteUrl), "git-receive-pack");

    var requestBody = BuildPushRequest(oldSha, newSha, branchName, packfile);

    using var client = new HttpClient();
    using var content = new ByteArrayContent(requestBody);
    content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/x-git-receive-pack-request");
    client.DefaultRequestHeaders.Add("Accept", "application/x-git-receive-pack-result");
    client.DefaultRequestHeaders.Add("Git-Protocol", "version=2");

    if (options?.Credentials != null)
    {
        var authString = $"{options.Credentials.Username}:{options.Credentials.Token}";
        var authBytes = Encoding.UTF8.GetBytes(authString);
        var base64Auth = Convert.ToBase64String(authBytes);
        client.DefaultRequestHeaders.Add("Authorization", $"Basic {base64Auth}");
    }

    var response = await client.PostAsync(url, content);
    if (!response.IsSuccessStatusCode)
    {
        var errorText = await response.Content.ReadAsStringAsync();
        throw new InvalidOperationException($"Push failed: {(int)response.StatusCode} {errorText ?? response.ReasonPhrase}");
    }

    var data = await response.Content.ReadAsByteArrayAsync();
    var lines = Packfile.DecodePktLines(data);

    foreach (var line in lines)
    {
        if (line.StartsWith("ng "))
        {
            var reason = line.Substring(3);
            throw new InvalidOperationException($"Push rejected: {reason}");
        }
    }
}

    private static byte[] BuildPushRequest(string oldSha, string newSha, string branchName, byte[] packfile)
    {
        var lines = new List<byte[]>();

        lines.Add(Packfile.EncodePktLine($"{oldSha} {newSha} refs/heads/{branchName}\0report-status agent=gitologist/1.0"));
        lines.Add(Packfile.EncodePktLine(null));
        lines.Add(packfile);

        return lines.SelectMany(x => x).ToArray();
    }

    public static async Task SetUpstreamBranch(string path, string remoteName, string branchName)
    {
        var configPath = Path.Combine(path, ".git", "config");

        string configContent = "";
        if (File.Exists(configPath))
        {
            configContent = await File.ReadAllTextAsync(configPath);
        }

        var lines = configContent.Split('\n').ToList();
        var inBranchSection = false;
        var foundBranchSection = false;
        var insertIndex = -1;

        for (var i = 0; i < lines.Count; i++)
        {
            var line = lines[i];
            var trimmed = line.Trim();

            var sectionMatch = Regex.Match(trimmed, @"^\[branch\s+""([^""]+)""\]$");
            if (sectionMatch.Success)
            {
                if (sectionMatch.Groups[1].Value == branchName)
                {
                    inBranchSection = true;
                    foundBranchSection = true;
                }
                else
                {
                    inBranchSection = false;
                }
                continue;
            }

            if (inBranchSection)
            {
                if (trimmed.StartsWith("remote =") || trimmed.StartsWith("merge ="))
                {
                    continue;
                }
                if (insertIndex == -1)
                {
                    insertIndex = i;
                }
            }
            else
            {
                if (trimmed.StartsWith("[") && insertIndex == -1)
                {
                    insertIndex = i;
                }
            }
        }

        if (!foundBranchSection)
        {
            lines.Add("");
            lines.Add($"[branch \"{branchName}\"]");
            lines.Add($"\tremote = {remoteName}");
            lines.Add($"\tmerge = refs/heads/{branchName}");
        }
        else
        {
            if (insertIndex == -1)
            {
                insertIndex = lines.Count;
            }
            lines.Insert(insertIndex, $"\tmerge = refs/heads/{branchName}");
            lines.Insert(insertIndex, $"\tremote = {remoteName}");
        }

        await File.WriteAllTextAsync(configPath, string.Join('\n', lines));
    }
}
