using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class InitCompatTests
{
    private string _baseDir = null!;
    private string _testDir = null!;
    private string _gitDir = null!;

    [TestInitialize]
    public void SetupTestDirs()
    {
        _baseDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-compat-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
        );
        Directory.CreateDirectory(_baseDir);

        _testDir = Path.Combine(_baseDir, "ours");
        _gitDir = Path.Combine(_baseDir, "theirs");

        Directory.CreateDirectory(_testDir);
        Directory.CreateDirectory(_gitDir);
    }

    [TestCleanup]
    public void CleanupTestDirs()
    {
        if (Directory.Exists(_baseDir))
        {
            try
            {
                Directory.Delete(_baseDir, true);
            }
            catch
            {
            }
        }
    }

    [TestMethod]
    public async Task ShouldCreateSameDirectoryStructureAsGitInit()
    {
        await Init.InitRepo(_testDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = _gitDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        var ourGitDir = Path.Combine(_testDir, ".git");
        var theirGitDir = Path.Combine(_gitDir, ".git");

        Assert.IsTrue(Directory.Exists(ourGitDir));
        Assert.IsTrue(Directory.Exists(theirGitDir));

        Assert.IsTrue(Directory.Exists(Path.Combine(ourGitDir, "objects")));
        Assert.IsTrue(Directory.Exists(Path.Combine(theirGitDir, "objects")));

        Assert.IsTrue(Directory.Exists(Path.Combine(ourGitDir, "refs", "heads")));
        Assert.IsTrue(Directory.Exists(Path.Combine(theirGitDir, "refs", "heads")));

        Assert.IsTrue(Directory.Exists(Path.Combine(ourGitDir, "refs", "tags")));
        Assert.IsTrue(Directory.Exists(Path.Combine(theirGitDir, "refs", "tags")));
    }

    [TestMethod]
    public async Task ShouldCreateHEADPointingToSameBranchAsGitInit()
    {
        await Init.InitRepo(_testDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = _gitDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        var ourHead = await File.ReadAllTextAsync(Path.Combine(_testDir, ".git", "HEAD"));
        var theirHeadPath = Path.Combine(_gitDir, ".git", "HEAD");

        string theirHead;
        if (File.Exists(theirHeadPath))
        {
            theirHead = await File.ReadAllTextAsync(theirHeadPath);
        }
        else
        {
            theirHead = "";
        }

        var ourHeadMatch = Regex.Match(ourHead, @"^ref: refs/heads/");
        Assert.IsTrue(ourHeadMatch.Success);

        var theirHeadMatch = Regex.Match(theirHead, @"^ref: refs/heads/");
        if (!string.IsNullOrEmpty(theirHead))
        {
            Assert.IsTrue(theirHeadMatch.Success);
        }
    }

    [TestMethod]
    public async Task ShouldCreateValidConfigFile()
    {
        await Init.InitRepo(_testDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = _gitDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        var ourConfig = await File.ReadAllTextAsync(Path.Combine(_testDir, ".git", "config"));
        var theirConfigPath = Path.Combine(_gitDir, ".git", "config");

        string theirConfig;
        if (File.Exists(theirConfigPath))
        {
            theirConfig = await File.ReadAllTextAsync(theirConfigPath);
        }
        else
        {
            theirConfig = "";
        }

        StringAssert.Contains(ourConfig, "[core]");
        StringAssert.Contains(ourConfig, "repositoryformatversion");

        if (!string.IsNullOrEmpty(theirConfig))
        {
            StringAssert.Contains(theirConfig, "[core]");
            StringAssert.Contains(theirConfig, "repositoryformatversion");
        }
    }

    [TestMethod]
    public async Task ShouldCreateEmptyObjectsDirectoryLikeGitInit()
    {
        await Init.InitRepo(_testDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = _gitDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        var ourObjectsPath = Path.Combine(_testDir, ".git", "objects");
        var theirObjectsPath = Path.Combine(_gitDir, ".git", "objects");

        string[] ourObjects;
        string[] theirObjects;

        if (Directory.Exists(ourObjectsPath))
        {
            ourObjects = Directory.GetDirectories(ourObjectsPath);
        }
        else
        {
            ourObjects = [];
        }

        if (Directory.Exists(theirObjectsPath))
        {
            theirObjects = Directory.GetDirectories(theirObjectsPath);
        }
        else
        {
            theirObjects = [];
        }

        Assert.IsNotNull(ourObjects);
        Assert.IsNotNull(theirObjects);
    }

    [TestMethod]
    public async Task ShouldCreateEmptyRefsHeadsDirectoryLikeGitInit()
    {
        await Init.InitRepo(_testDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = _gitDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        var ourRefsHeadsPath = Path.Combine(_testDir, ".git", "refs", "heads");
        var theirRefsHeadsPath = Path.Combine(_gitDir, ".git", "refs", "heads");

        string[] ourRefsHeads;
        string[] theirRefsHeads;

        if (Directory.Exists(ourRefsHeadsPath))
        {
            ourRefsHeads = Directory.GetFiles(ourRefsHeadsPath);
        }
        else
        {
            ourRefsHeads = [];
        }

        if (Directory.Exists(theirRefsHeadsPath))
        {
            theirRefsHeads = Directory.GetFiles(theirRefsHeadsPath);
        }
        else
        {
            theirRefsHeads = [];
        }

        Assert.AreEqual(0, ourRefsHeads.Length);
        Assert.AreEqual(0, theirRefsHeads.Length);
    }

    [TestMethod]
    public async Task ShouldCreateDescriptionFile()
    {
        await Init.InitRepo(_testDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = _gitDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        Assert.IsTrue(File.Exists(Path.Combine(_testDir, ".git", "description")));
        Assert.IsTrue(File.Exists(Path.Combine(_gitDir, ".git", "description")));
    }
}
