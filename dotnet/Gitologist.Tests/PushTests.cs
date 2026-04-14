using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text.RegularExpressions;

namespace Gitologist.Tests;

[TestClass]
public class PushTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-push-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
        );
        Directory.CreateDirectory(_testDir);
    }

    [TestCleanup]
    public void CleanupTestDir()
    {
        if (Directory.Exists(_testDir))
        {
            try
            {
                Directory.Delete(_testDir, true);
            }
            catch
            {
            }
        }
    }

    [TestMethod]
    public async Task ShouldPushToDefaultRemoteAndBranch()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        var remoteBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "remotes",
            "origin",
            "main"
        );
        Assert.IsTrue(File.Exists(remoteBranchPath));

        var remoteBranchContent = await File.ReadAllTextAsync(remoteBranchPath);
        StringAssert.Matches(remoteBranchContent, new Regex(@"^[a-f0-9]{40}"));
    }

    [TestMethod]
    public async Task ShouldPushToSpecifiedRemote()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir, "upstream");

        var remoteBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "remotes",
            "upstream",
            "main"
        );
        Assert.IsTrue(File.Exists(remoteBranchPath));
    }

    [TestMethod]
    public async Task ShouldPushToSpecifiedBranch()
    {
        await Init.InitRepo(_testDir);
        var headPath = Path.Combine(_testDir, ".git", "HEAD");
        await File.WriteAllTextAsync(headPath, "ref: refs/heads/main");

        Directory.CreateDirectory(
            Path.Combine(_testDir, ".git", "refs", "heads")
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, ".git", "refs", "heads", "main"),
            "abc123"
        );

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir, "origin", "main");

        var remoteBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "remotes",
            "origin",
            "main"
        );
        Assert.IsTrue(File.Exists(remoteBranchPath));
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfNotAGitRepository()
    {
        var nonGitDir = Path.Combine(
            Path.GetTempPath(),
            $"not-a-repo-{DateTime.UtcNow.Ticks}"
        );
        Directory.CreateDirectory(nonGitDir);

        try
        {
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(
                () => Push.PushToRemote(nonGitDir)
            );
        }
        finally
        {
            try
            {
                Directory.Delete(nonGitDir, true);
            }
            catch
            {
            }
        }
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfThereAreUncommittedChanges()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "initial"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Push.PushToRemote(_testDir)
        );
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfThereAreUntrackedFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "initial"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test2.txt"),
            "untracked"
        );

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Push.PushToRemote(_testDir)
        );
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfLocalBranchDoesNotExist()
    {
        await Init.InitRepo(_testDir);
        var headPath = Path.Combine(_testDir, ".git", "HEAD");
        await File.WriteAllTextAsync(headPath, "ref: refs/heads/nonexistent");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Push.PushToRemote(_testDir)
        );
    }

    [TestMethod]
    public async Task ShouldUpdateExistingRemoteBranch()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "First commit");

        await Push.PushToRemote(_testDir);

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var secondSha = await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        var remoteBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "remotes",
            "origin",
            "main"
        );
        var remoteBranchContent = await File.ReadAllTextAsync(remoteBranchPath);

        Assert.AreEqual(secondSha, remoteBranchContent.Trim());
    }

    [TestMethod]
    public async Task ShouldCreateRemoteDirectoryIfItDoesNotExist()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir, "myremote");

        var remoteDir = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "remotes",
            "myremote"
        );
        Assert.IsTrue(Directory.Exists(remoteDir));

        var remoteBranchPath = Path.Combine(remoteDir, "main");
        Assert.IsTrue(File.Exists(remoteBranchPath));
    }

    [TestMethod]
    public async Task ShouldHandleMultiplePushesToSameBranch()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "First commit");

        await Push.PushToRemote(_testDir);

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        var remoteBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "remotes",
            "origin",
            "main"
        );
        var remoteBranchContent = await File.ReadAllTextAsync(remoteBranchPath);

        var remoteSha = remoteBranchContent.Trim();

        var localBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "heads",
            "main"
        );
        var localBranchContent = await File.ReadAllTextAsync(localBranchPath);

        var localSha = localBranchContent.Trim();

        Assert.AreEqual(localSha, remoteSha);
    }

    [TestMethod]
    public async Task ShouldCreateNewBranchSectionWithRemoteAndMergeSettings()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");

        await Push.SetUpstreamBranch(_testDir, "origin", "feature");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("[branch \"feature\"]"));
        Assert.IsTrue(configContent.Contains("remote = origin"));
        Assert.IsTrue(configContent.Contains("merge = refs/heads/feature"));
    }

    [TestMethod]
    public async Task ShouldAddRemoteAndMergeSettingsToExistingBranchSection()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");
        await File.WriteAllTextAsync(
            configPath,
            "[branch \"feature\"]\n\tdescription = test branch\n"
        );

        await Push.SetUpstreamBranch(_testDir, "upstream", "feature");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("[branch \"feature\"]"));
        Assert.IsTrue(configContent.Contains("description = test branch"));
        Assert.IsTrue(configContent.Contains("remote = upstream"));
        Assert.IsTrue(configContent.Contains("merge = refs/heads/feature"));
    }

    [TestMethod]
    public async Task ShouldUpdateExistingRemoteAndMergeSettings()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");
        await File.WriteAllTextAsync(
            configPath,
            "[branch \"main\"]\n\tremote = origin\n\tmerge = refs/heads/main\n"
        );

        await Push.SetUpstreamBranch(_testDir, "upstream", "main");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("[branch \"main\"]"));
        Assert.IsTrue(configContent.Contains("remote = upstream"));
        Assert.IsTrue(configContent.Contains("merge = refs/heads/main"));
    }

    [TestMethod]
    public async Task ShouldHandleMultipleBranchesCorrectly()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");
        await File.WriteAllTextAsync(
            configPath,
            "[branch \"main\"]\n\tremote = origin\n\tmerge = refs/heads/main\n"
        );

        await Push.SetUpstreamBranch(_testDir, "upstream", "feature");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("[branch \"main\"]"));
        Assert.IsTrue(configContent.Contains("remote = origin"));
        Assert.IsTrue(configContent.Contains("[branch \"feature\"]"));
        Assert.IsTrue(configContent.Contains("remote = upstream"));
        Assert.IsTrue(configContent.Contains("merge = refs/heads/feature"));
    }

    [TestMethod]
    public async Task ShouldPreserveOtherConfigSections()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");
        await File.WriteAllTextAsync(
            configPath,
            "[core]\n\trepositoryformatversion = 0\n\n[remote \"origin\"]\n\turl = test.git\n"
        );

        await Push.SetUpstreamBranch(_testDir, "origin", "main");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("[core]"));
        Assert.IsTrue(configContent.Contains("repositoryformatversion = 0"));
        Assert.IsTrue(configContent.Contains("[remote \"origin\"]"));
        Assert.IsTrue(configContent.Contains("url = test.git"));
        Assert.IsTrue(configContent.Contains("[branch \"main\"]"));
    }

    [TestMethod]
    public async Task ShouldHandleEmptyConfigFile()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");
        await File.WriteAllTextAsync(configPath, "");

        await Push.SetUpstreamBranch(_testDir, "origin", "main");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("[branch \"main\"]"));
        Assert.IsTrue(configContent.Contains("remote = origin"));
        Assert.IsTrue(configContent.Contains("merge = refs/heads/main"));
    }

    [TestMethod]
    public async Task ShouldHandleMissingConfigFile()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");
        File.Delete(configPath);

        await Push.SetUpstreamBranch(_testDir, "origin", "main");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("[branch \"main\"]"));
        Assert.IsTrue(configContent.Contains("remote = origin"));
        Assert.IsTrue(configContent.Contains("merge = refs/heads/main"));
    }

    [TestMethod]
    public async Task ShouldUseTabsForIndentation()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");

        await Push.SetUpstreamBranch(_testDir, "origin", "main");

        var configContent = await File.ReadAllTextAsync(configPath);
        Assert.IsTrue(configContent.Contains("\tremote = origin"));
        Assert.IsTrue(configContent.Contains("\tmerge = refs/heads/main"));
    }
}
