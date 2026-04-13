using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class GitCompatTests
{
    private string _baseDir = null!;
    private string _remoteDir = null!;
    private string _defaultBranch = "main";

    [TestInitialize]
    public void Setup()
    {
        _baseDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-compat-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
        );
        Directory.CreateDirectory(_baseDir);

        // Detect git default branch
        _defaultBranch = "main";

        try
        {
            var testDir = Path.Combine(_baseDir, "branch-test");
            Directory.CreateDirectory(testDir);

            var psiInit = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = testDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiInit))
            {
                process?.WaitForExit();
            }

            var psiBranch = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "branch --show-current",
                WorkingDirectory = testDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiBranch))
            {
                var output = process?.StandardOutput.ReadToEnd().Trim();
                process?.WaitForExit();
                if (!string.IsNullOrEmpty(output))
                {
                    _defaultBranch = output;
                }
            }

            Directory.Delete(testDir, true);
        }
        catch
        {
            // Use default main
        }

        // Create a bare remote repository
        _remoteDir = Path.Combine(_baseDir, "remote.git");
        Directory.CreateDirectory(_remoteDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init --bare",
                WorkingDirectory = _remoteDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        // Create initial content in the remote using a temporary clone
        var tempClone = Path.Combine(_baseDir, "temp-clone");
        try
        {
            var psiClone = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = $"clone {_remoteDir} temp-clone",
                WorkingDirectory = _baseDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiClone))
            {
                process?.WaitForExit();
            }

            File.WriteAllText(Path.Combine(tempClone, "README.md"), "# Initial");

            var psiAdd = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "add .",
                WorkingDirectory = tempClone,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiAdd))
            {
                process?.WaitForExit();
            }

            var psiCommit = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "commit -m \"Initial commit\"",
                WorkingDirectory = tempClone,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiCommit))
            {
                process?.WaitForExit();
            }

            var psiPush = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = $"push origin {_defaultBranch}",
                WorkingDirectory = tempClone,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiPush))
            {
                process?.WaitForExit();
            }
        }
        finally
        {
            if (Directory.Exists(tempClone))
            {
                try
                {
                    Directory.Delete(tempClone, true);
                }
                catch
                {
                }
            }
        }
    }

    [TestCleanup]
    public void Cleanup()
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
        var ourDir = Path.Combine(_baseDir, "our-init");
        var theirDir = Path.Combine(_baseDir, "their-init");

        Directory.CreateDirectory(ourDir);
        Directory.CreateDirectory(theirDir);

        await Init.InitRepo(ourDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = theirDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        var ourGitDir = Path.Combine(ourDir, ".git");
        var theirGitDir = Path.Combine(theirDir, ".git");

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
    public async Task ShouldCreateHeadPointingToSameRefFormatAsGitInit()
    {
        var ourDir = Path.Combine(_baseDir, "our-init2");
        var theirDir = Path.Combine(_baseDir, "their-init2");

        Directory.CreateDirectory(ourDir);
        Directory.CreateDirectory(theirDir);

        await Init.InitRepo(ourDir);

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = theirDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            process?.WaitForExit();
        }
        catch
        {
        }

        var ourHead = await File.ReadAllTextAsync(Path.Combine(ourDir, ".git", "HEAD"));
        var theirHeadPath = Path.Combine(theirDir, ".git", "HEAD");

        string theirHead;
        if (File.Exists(theirHeadPath))
        {
            theirHead = await File.ReadAllTextAsync(theirHeadPath);
        }
        else
        {
            theirHead = "";
        }

        // Both should point to a branch
        StringAssert.Matches(ourHead, new Regex(@"^ref: refs/heads/"));
        if (!string.IsNullOrEmpty(theirHead))
        {
            StringAssert.Matches(theirHead, new Regex(@"^ref: refs/heads/"));
        }
    }

    [TestMethod]
    public async Task ShouldCreateAnIndexThatGitCanRead()
    {
        var ourDir = Path.Combine(_baseDir, "our-add");
        Directory.CreateDirectory(ourDir);
        await Init.InitRepo(ourDir);

        await File.WriteAllTextAsync(Path.Combine(ourDir, "test.txt"), "test content");
        await File.WriteAllTextAsync(Path.Combine(ourDir, "test 2.txt"), "test content 2");
        await Add.AddFiles(ourDir, new[] { "test.txt", "test 2.txt" });

        string? gitStatus = null;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "status",
                WorkingDirectory = ourDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            gitStatus = process?.StandardOutput.ReadToEnd();
            process?.WaitForExit();
        }
        catch
        {
        }

        Assert.IsNotNull(gitStatus);
        Assert.IsTrue(gitStatus.Contains("new file:   test.txt"));
        Assert.IsTrue(gitStatus.Contains("new file:   test 2.txt"));
    }

    [TestMethod]
    public async Task ShouldCreateCommitsThatGitCanRead()
    {
        var ourDir = Path.Combine(_baseDir, "our-commit");
        Directory.CreateDirectory(ourDir);
        await Init.InitRepo(ourDir);

        await File.WriteAllTextAsync(Path.Combine(ourDir, "test.txt"), "test content");
        await Add.AddFiles(ourDir, new[] { "test.txt" });
        await Commit.CreateCommit(ourDir, "Test commit");

        // Verify our commit can be read by git log
        string? gitLog = null;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "log --oneline",
                WorkingDirectory = ourDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            gitLog = process?.StandardOutput.ReadToEnd();
            process?.WaitForExit();
        }
        catch
        {
        }

        Assert.IsNotNull(gitLog);
        Assert.IsTrue(gitLog.Contains("Test commit"));

        // Check `git status`
        string? gitStatus = null;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "status",
                WorkingDirectory = ourDir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            gitStatus = process?.StandardOutput.ReadToEnd();
            process?.WaitForExit();
        }
        catch
        {
        }

        Assert.IsNotNull(gitStatus);
        Assert.IsTrue(gitStatus.Contains("nothing to commit, working tree clean"));
    }

    [TestMethod]
    public async Task ShouldProduceSameCommitStructureAsGit()
    {
        var ourDir = Path.Combine(_baseDir, "our-commit2");
        var theirDir = Path.Combine(_baseDir, "their-commit2");

        Directory.CreateDirectory(ourDir);
        Directory.CreateDirectory(theirDir);

        // Our implementation
        await Init.InitRepo(ourDir);
        await File.WriteAllTextAsync(Path.Combine(ourDir, "file.txt"), "content");
        await Add.AddFiles(ourDir, new[] { "file.txt" });
        var ourSha = await Commit.CreateCommit(ourDir, "Same message");

        // Real git
        try
        {
            var psiInit = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "init",
                WorkingDirectory = theirDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiInit))
            {
                process?.WaitForExit();
            }

            await File.WriteAllTextAsync(Path.Combine(theirDir, "file.txt"), "content");

            var psiAdd = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "add .",
                WorkingDirectory = theirDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiAdd))
            {
                process?.WaitForExit();
            }

            var psiCommit = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "commit -m \"Same message\"",
                WorkingDirectory = theirDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using (var process = Process.Start(psiCommit))
            {
                process?.WaitForExit();
            }
        }
        catch
        {
        }

        // Both should have valid commit SHAs
        StringAssert.Matches(ourSha, new Regex(@"^[a-f0-9]{40}$"));

        // Both should have 1 commit in log
        var ourLog = await Log.GetLog(ourDir);

        string? theirLog = null;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "log --oneline",
                WorkingDirectory = theirDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            theirLog = process?.StandardOutput.ReadToEnd();
            process?.WaitForExit();
        }
        catch
        {
        }

        Assert.AreEqual(1, ourLog.Count);
        if (!string.IsNullOrEmpty(theirLog))
        {
            var theirLogLines = theirLog.Trim().Split('\n');
            Assert.AreEqual(1, theirLogLines.Length);
        }
    }

    [TestMethod]
    public async Task ShouldShowSameCommitOrderAsGitLog()
    {
        var ourDir = Path.Combine(_baseDir, "our-log");
        Directory.CreateDirectory(ourDir);
        await Init.InitRepo(ourDir);

        // Create multiple commits
        await File.WriteAllTextAsync(Path.Combine(ourDir, "file1.txt"), "content1");
        await Add.AddFiles(ourDir, new[] { "file1.txt" });
        await Commit.CreateCommit(ourDir, "First commit");

        await File.WriteAllTextAsync(Path.Combine(ourDir, "file2.txt"), "content2");
        await Add.AddFiles(ourDir, new[] { "file2.txt" });
        await Commit.CreateCommit(ourDir, "Second commit");

        await File.WriteAllTextAsync(Path.Combine(ourDir, "file3.txt"), "content3");
        await Add.AddFiles(ourDir, new[] { "file3.txt" });
        await Commit.CreateCommit(ourDir, "Third commit");

        var ourLog = await Log.GetLog(ourDir);

        string? gitLog = null;
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "git",
                Arguments = "log --oneline",
                WorkingDirectory = ourDir,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            gitLog = process?.StandardOutput.ReadToEnd();
            process?.WaitForExit();
        }
        catch
        {
        }

        // Both should have 3 commits
        Assert.AreEqual(3, ourLog.Count);
        if (!string.IsNullOrEmpty(gitLog))
        {
            var gitLogLines = gitLog.Trim().Split('\n');
            Assert.AreEqual(3, gitLogLines.Length);
        }

        // Both should show commits in reverse chronological order
        Assert.AreEqual("Third commit", ourLog[0].Message);
        Assert.AreEqual("Second commit", ourLog[1].Message);
        Assert.AreEqual("First commit", ourLog[2].Message);

        if (!string.IsNullOrEmpty(gitLog))
        {
            Assert.IsTrue(gitLog.Contains("Third commit"));
            Assert.IsTrue(gitLog.Contains("Second commit"));
            Assert.IsTrue(gitLog.Contains("First commit"));
        }
    }

    [TestMethod]
    public async Task ShouldCreateRepoStructureLikeGitClone()
    {
        var ourClone = Path.Combine(_baseDir, "our-clone");

        // Our implementation (simplified - just sets up repo and remote)
        await Clone.CloneRepo(_remoteDir, ourClone);

        // Verify our clone exists with proper structure
        Assert.IsTrue(Directory.Exists(Path.Combine(ourClone, ".git")));
        Assert.IsTrue(Directory.Exists(Path.Combine(ourClone, ".git", "objects")));
        Assert.IsTrue(Directory.Exists(Path.Combine(ourClone, ".git", "refs", "heads")));

        // Verify remote is configured
        var config = await File.ReadAllTextAsync(Path.Combine(ourClone, ".git", "config"));
        StringAssert.Contains(config, "[remote \"origin\"]");
        StringAssert.Contains(config, $"url = {_remoteDir}");
    }
}
