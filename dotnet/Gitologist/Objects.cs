using Gitologist.Types;
using System.Text;

namespace Gitologist;

public static class Objects
{
    public static async Task<List<PackObject>> EnumerateObjects(string gitDir, string sha, HashSet<string>? visited = null)
    {
        var newVisited = visited ?? new HashSet<string>();
        if (newVisited.Contains(sha))
        {
            return new List<PackObject>();
        }
        newVisited.Add(sha);

        var objectData = await Utils.ReadObject(gitDir, sha);
        var headerEnd = objectData.IndexOf('\n');
        if (headerEnd == -1)
        {
            return new List<PackObject>();
        }

        var header = objectData.Substring(0, headerEnd);
        var spaceIndex = header.IndexOf(' ');
        if (spaceIndex == -1)
        {
            return new List<PackObject>();
        }

        var type = header.Substring(0, spaceIndex);
        var content = objectData.Substring(headerEnd + 1);

        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = type,
                Sha = sha,
                Content = Encoding.UTF8.GetBytes(content)
            }
        };

        if (type == "commit")
        {
            var lines = content.Split('\n');
            foreach (var line in lines)
            {
                if (line.StartsWith("parent "))
                {
                    var parentSha = line.Substring(7);
                    var parentObjects = await EnumerateObjects(gitDir, parentSha, newVisited);
                    objects.AddRange(parentObjects);
                }
                else if (line.StartsWith("tree "))
                {
                    var treeSha = line.Substring(5);
                    var treeObjects = await EnumerateObjects(gitDir, treeSha, newVisited);
                    objects.AddRange(treeObjects);
                }
            }
        }
        else if (type == "tree")
        {
            var entries = Utils.ParseTreeEntries(objectData);
            foreach (var entry in entries)
            {
                var entryObjects = await EnumerateObjects(gitDir, entry.Sha, newVisited);
                objects.AddRange(entryObjects);
            }
        }

        return objects;
    }

    public static async Task<List<PackObject>> GetAllObjects(string gitDir)
    {
        var objectsDir = Path.Combine(gitDir, "objects");
        var objects = new List<PackObject>();

        if (!Directory.Exists(objectsDir))
        {
            return objects;
        }

        var dirs = Directory.GetDirectories(objectsDir);

        foreach (var dir in dirs)
        {
            var dirName = Path.GetFileName(dir);
            if (dirName.Length != 2)
            {
                continue;
            }

            var files = Directory.GetFiles(dir);

            foreach (var file in files)
            {
                var fileName = Path.GetFileName(file);
                var sha = dirName + fileName;

                try
                {
                    var objectData = await Utils.ReadObject(gitDir, sha);
                    var headerEnd = objectData.IndexOf('\n');
                    if (headerEnd == -1)
                    {
                        continue;
                    }

                    var header = objectData.Substring(0, headerEnd);
                    var spaceIndex = header.IndexOf(' ');
                    if (spaceIndex == -1)
                    {
                        continue;
                    }

                    var type = header.Substring(0, spaceIndex);
                    var content = objectData.Substring(headerEnd + 1);

                    objects.Add(new PackObject
                    {
                        Type = type,
                        Sha = sha,
                        Content = Encoding.UTF8.GetBytes(content)
                    });
                }
                catch
                {
                    // Skip invalid objects
                }
            }
        }

        return objects;
    }
}
