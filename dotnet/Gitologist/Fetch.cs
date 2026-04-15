using System.Text;
using System.Text.RegularExpressions;

namespace Gitologist;

public class FetchResult
{
    public string Remote { get; set; } = null!;
    public List<RefInfo> Refs { get; set; } = new();
}

public class RefInfo
{
    public string Name { get; set; } = null!;
    public string Sha { get; set; } = null!;
}

public class DiscoveredRef
{
    public string Sha { get; set; } = null!;
    public string Ref { get; set; } = null!;
}

public static class Fetch
{
    public static async Task<FetchResult> FetchFromRemote(string path, string? remote = null)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var remoteName = remote ?? "origin";
        var remoteUrl = await Remote.GetRemoteUrl(gitDir, remoteName);

        if (remoteUrl == null)
        {
            return new FetchResult { Remote = remoteName, Refs = new List<RefInfo>() };
        }

        var refs = await DiscoverRefs(remoteUrl);
        if (refs.Count == 0)
        {
            refs = await DiscoverRefsV2(remoteUrl);
        }
        var result = new FetchResult { Remote = remoteName, Refs = new List<RefInfo>() };

        var wants = new List<string>();
        var haves = new List<string>();

        foreach (var discoveredRef in refs)
        {
            if (discoveredRef.Ref.StartsWith("refs/heads/"))
            {
                var branchName = discoveredRef.Ref.Substring("refs/heads/".Length);
                var localRefPath = Path.Combine(gitDir, "refs", "heads", branchName);

                if (File.Exists(localRefPath))
                {
                    var localSha = (await File.ReadAllTextAsync(localRefPath)).Trim();
                    haves.Add(localSha);
                }

                wants.Add(discoveredRef.Sha);
                result.Refs.Add(new RefInfo { Name = branchName, Sha = discoveredRef.Sha });
            }
        }

        if (wants.Count > 0)
        {
            var objects = await FetchPackfile(remoteUrl, wants, haves);
            await StoreObjects(gitDir, objects);
        }

        foreach (var refInfo in result.Refs)
        {
            var remoteRefPath = Path.Combine(gitDir, "refs", "remotes", remoteName, refInfo.Name);
            Directory.CreateDirectory(Path.GetDirectoryName(remoteRefPath)!);
            await File.WriteAllTextAsync(remoteRefPath, refInfo.Sha + "\n");
        }

        return result;
    }

    private static async Task StoreObjects(string gitDir, List<PackObject> objects)
    {
        foreach (var obj in objects)
        {
            await Utils.HashObject(gitDir, obj.Content, obj.Type);
        }
    }

    private static async Task<List<DiscoveredRef>> DiscoverRefs(string remoteUrl)
    {
        var url = new Uri(new Uri(remoteUrl), "info/refs?service=git-upload-pack");

        using var client = new HttpClient();
        client.DefaultRequestHeaders.Add("Accept", "application/x-git-upload-pack-advertisement");
        client.DefaultRequestHeaders.Add("Git-Protocol", "version=2");

        var response = await client.GetAsync(url);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Failed to discover refs: {(int)response.StatusCode} {response.ReasonPhrase}");
        }

        var data = await response.Content.ReadAsByteArrayAsync();
        var lines = Packfile.DecodePktLines(data);

        var refs = new List<DiscoveredRef>();
        var started = false;

        foreach (var line in lines)
        {
            if (line.Contains("# service=git-upload-pack"))
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

    private static async Task<List<DiscoveredRef>> DiscoverRefsV2(string remoteUrl)
    {
        var url = new Uri(new Uri(remoteUrl), "git-upload-pack");

        var requestBody = BuildLsRefsRequest();

        using var client = new HttpClient();
        using var content = new ByteArrayContent(requestBody);
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/x-git-upload-pack-request");
        client.DefaultRequestHeaders.Add("Accept", "application/x-git-upload-pack-result");
        client.DefaultRequestHeaders.Add("Git-Protocol", "version=2");

        var response = await client.PostAsync(url, content);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Failed to discover refs v2: {(int)response.StatusCode} {response.ReasonPhrase}");
        }

        var data = await response.Content.ReadAsByteArrayAsync();
        var lines = Packfile.DecodePktLines(data);

        var refs = new List<DiscoveredRef>();

        foreach (var line in lines)
        {
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

    private static byte[] BuildLsRefsRequest()
    {
        var lines = new List<byte[]>();

        lines.Add(Packfile.EncodePktLine("command=ls-refs\0peel\0symrefs"));
        lines.Add(Packfile.EncodePktLine("0001"));
        lines.Add(Packfile.EncodePktLine("refs/heads/*"));
        lines.Add(Packfile.EncodePktLine(null));

        return lines.SelectMany(x => x).ToArray();
    }

    private static async Task<List<PackObject>> FetchPackfile(string remoteUrl, List<string> wants, List<string> haves)
    {
        var url = new Uri(new Uri(remoteUrl), "git-upload-pack");

        var requestBody = BuildFetchRequest(wants, haves);

        using var client = new HttpClient();
        using var content = new ByteArrayContent(requestBody);
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/x-git-upload-pack-request");
        client.DefaultRequestHeaders.Add("Accept", "application/x-git-upload-pack-result");
        client.DefaultRequestHeaders.Add("Git-Protocol", "version=2");

        var response = await client.PostAsync(url, content);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"Failed to fetch packfile: {(int)response.StatusCode} {response.ReasonPhrase}");
        }

        var data = await response.Content.ReadAsByteArrayAsync();
        var packfileOffset = FindPackfileStart(data);

        if (packfileOffset == -1)
        {
            return new List<PackObject>();
        }

        var packfileData = data.Skip(packfileOffset).ToArray();
        return Packfile.ParsePackfile(packfileData);
    }

    private static byte[] BuildFetchRequest(List<string> wants, List<string> haves)
    {
        var lines = new List<byte[]>();

        lines.Add(Packfile.EncodePktLine("command=fetch"));

        foreach (var want in wants)
        {
            lines.Add(Packfile.EncodePktLine($"want {want}"));
        }

        foreach (var have in haves)
        {
            lines.Add(Packfile.EncodePktLine($"have {have}"));
        }

        lines.Add(Packfile.EncodePktLine("done"));
        lines.Add(Packfile.EncodePktLine("0001"));
        lines.Add(Packfile.EncodePktLine(null));

        return lines.SelectMany(x => x).ToArray();
    }

    private static int FindPackfileStart(byte[] data)
    {
        var signature = Encoding.ASCII.GetBytes("PACK");
        for (var i = 0; i < data.Length - 4; i++)
        {
            if (data.Skip(i).Take(4).SequenceEqual(signature))
            {
                return i;
            }
        }
        return -1;
    }
}
