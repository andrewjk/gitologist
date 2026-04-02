using System.Text;

namespace Gitologist;

public static class Init
{
    private const string HEAD_FILE = "ref: refs/heads/master\n";
    private const string CONFIG_FILE = "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\n\tlogallrefupdates = true\n";

    public static async Task InitRepo(string path)
    {
        var gitDir = Path.Combine(path, ".git");

        if (Directory.Exists(gitDir))
        {
            return;
        }

        Directory.CreateDirectory(Path.Combine(gitDir, "objects"));
        Directory.CreateDirectory(Path.Combine(gitDir, "refs", "heads"));
        Directory.CreateDirectory(Path.Combine(gitDir, "refs", "tags"));
        Directory.CreateDirectory(Path.Combine(gitDir, "info"));

        await File.WriteAllTextAsync(Path.Combine(gitDir, "HEAD"), HEAD_FILE);
        await File.WriteAllTextAsync(Path.Combine(gitDir, "config"), CONFIG_FILE);
        await File.WriteAllTextAsync(
            Path.Combine(gitDir, "description"),
            "Unnamed repository; edit this file 'description' to name the repository.\n"
        );
    }
}
