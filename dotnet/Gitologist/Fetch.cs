using System.Text;
using System.Text.RegularExpressions;
using Gitologist.Types;

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
    public static async Task<FetchResult> FetchOrigin(string path, string? remote = null, RemoteOptions? options = null)
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

        var refs = await DiscoverRefs(remoteUrl, options);
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
            var objects = await FetchPackfile(remoteUrl, wants, haves, options);
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

    private static async Task<List<DiscoveredRef>> DiscoverRefs(string remoteUrl, RemoteOptions? options = null)
    {
        var url = new Uri($"{remoteUrl.TrimEnd('/')}/git-upload-pack");

        var requestBody = BuildLsRefsRequest();

        using var client = new HttpClient();
        using var content = new ByteArrayContent(requestBody);
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/x-git-upload-pack-request");
        client.DefaultRequestHeaders.Add("Accept", "application/x-git-upload-pack-result");
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
            throw new InvalidOperationException($"Failed to discover refs: {(int)response.StatusCode} {response.ReasonPhrase}");
        }

        var data = await response.Content.ReadAsByteArrayAsync();
        var lines = Packfile.DecodePktLines(data);

        var refs = new List<DiscoveredRef>();

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            if (string.IsNullOrEmpty(trimmed)) continue;

            var parts = trimmed.Split(new[] { ' ' }, 2);
            if (parts.Length >= 2)
            {
                var sha = parts[0];
                if (sha.Length == 40 && sha.All(c => char.IsLetterOrDigit(c)))
                {
                    var refName = parts[1].Trim().Split('\0')[0];
                    refs.Add(new DiscoveredRef { Sha = sha, Ref = refName });
                }
            }
        }

        return refs;
    }

    private static byte[] BuildLsRefsRequest()
    {
        var lines = new List<byte[]>();

        lines.Add(Packfile.EncodePktLine("command=ls-refs\n"));
        lines.Add(Encoding.UTF8.GetBytes("0001"));
        lines.Add(Packfile.EncodePktLine("symrefs\n"));
        lines.Add(Packfile.EncodePktLine("peel\n"));
        lines.Add(Packfile.EncodePktLine("ref-prefix refs/heads/\n"));
        lines.Add(Packfile.EncodePktLine(null));

        return lines.SelectMany(x => x).ToArray();
    }

    private static byte[] ExtractPackfileFromSideband(byte[] data)
    {
        var offset = 0;
        var packfileData = new List<byte>();

        while (offset < data.Length)
        {
            if (offset + 4 > data.Length)
            {
                break;
            }

            var hexLength = Encoding.ASCII.GetString(data, offset, 4);

            if (hexLength == "0000")
            {
                offset += 4;
                continue;
            }

            if (hexLength == "0001")
            {
                offset += 4;
                continue;
            }

            if (!int.TryParse(hexLength, System.Globalization.NumberStyles.HexNumber, null, out var length))
            {
                break;
            }

            if (length <= 0 || offset + length > data.Length)
            {
                break;
            }

            var payload = new byte[length - 4];
            Array.Copy(data, offset + 4, payload, 0, length - 4);

            if (payload.Length > 0)
            {
                var channel = payload[0];
                if (channel == 1)
                {
                    packfileData.AddRange(payload.Skip(1));
                }
                else if (channel == 3)
                {
                    var errorMsg = Encoding.UTF8.GetString(payload, 1, payload.Length - 1);
                    Console.Error.WriteLine($"Git error: {errorMsg}");
                }
            }

            offset += length;
        }

        return packfileData.ToArray();
    }

    private static async Task<List<PackObject>> FetchPackfile(string remoteUrl, List<string> wants, List<string> haves, RemoteOptions? options = null)
    {
        var url = new Uri($"{remoteUrl.TrimEnd('/')}/git-upload-pack");

        var requestBody = BuildFetchRequest(wants, haves);

        using var client = new HttpClient();
        using var content = new ByteArrayContent(requestBody);
        content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/x-git-upload-pack-request");
        client.DefaultRequestHeaders.Add("Accept", "application/x-git-upload-pack-result");
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
            throw new InvalidOperationException($"Failed to fetch packfile: {(int)response.StatusCode} {response.ReasonPhrase}");
        }

        var data = await response.Content.ReadAsByteArrayAsync();
        var packfileData = ExtractPackfileFromSideband(data);

        if (packfileData.Length == 0)
        {
            return new List<PackObject>();
        }

        return Packfile.ParsePackfile(packfileData);
    }

    private static byte[] BuildFetchRequest(List<string> wants, List<string> haves)
    {
        var lines = new List<byte[]>();

        lines.Add(Packfile.EncodePktLine("command=fetch\n"));
        lines.Add(Encoding.UTF8.GetBytes("0001"));

        foreach (var want in wants)
        {
            lines.Add(Packfile.EncodePktLine($"want {want}\n"));
        }

        foreach (var have in haves)
        {
            lines.Add(Packfile.EncodePktLine($"have {have}\n"));
        }

        lines.Add(Packfile.EncodePktLine("done\n"));
        lines.Add(Packfile.EncodePktLine(null));

        return lines.SelectMany(x => x).ToArray();
    }
}
