using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class SwitchTests
{
    private string _testDir = null!;
    private string _gitDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
        );
        Directory.CreateDirectory(_testDir);
        _gitDir = Path.Combine(_testDir, ".git");
    }

    [TestCleanup]
    public void CleanupTestDir()
    {
        if (Directory.Exists(_testDir))
        {
            Directory.Delete(_testDir, true);
        }
    }

    [TestMethod]
    public async Task ShouldSwitchToExistingLocalBranchAndUpdateHEADAndTree()
    {
        await Init.InitRepo(_testDir);

        // First commit on main (file.txt = "A")
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "A");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "First commit");

        // Create a "feature" branch pointing at the first commit
        await File.WriteAllTextAsync(Path.Combine(_gitDir, "refs", "heads", "feature"), firstSha);

        // Second commit on main changes the working tree (file.txt = "B")
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "B");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await Switch.SwitchBranch(_testDir, "feature");

        var head = await File.ReadAllTextAsync(Path.Combine(_gitDir, "HEAD"));
        Assert.AreEqual("ref: refs/heads/feature\n", head);

        // Working tree should now reflect the feature branch (file.txt = "A")
        var content = await File.ReadAllTextAsync(Path.Combine(_testDir, "file.txt"));
        Assert.AreEqual("A", content);
    }

    [TestMethod]
    public async Task ShouldCreateLocalBranchFromSingleRemoteTrackingBranch()
    {
        await Init.InitRepo(_testDir);

        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        var sha = await Commit.CreateCommit(_testDir, "Initial commit");

        // Simulate a fetched remote-tracking branch with no local branch yet
        Directory.CreateDirectory(Path.Combine(_gitDir, "refs", "remotes", "origin"));
        await File.WriteAllTextAsync(Path.Combine(_gitDir, "refs", "remotes", "origin", "feature"), sha);

        await Switch.SwitchBranch(_testDir, "feature");

        // Local branch created at the same SHA
        var localSha = (await File.ReadAllTextAsync(Path.Combine(_gitDir, "refs", "heads", "feature"))).Trim();
        Assert.AreEqual(sha, localSha);

        // HEAD points at the new local branch
        var head = await File.ReadAllTextAsync(Path.Combine(_gitDir, "HEAD"));
        Assert.AreEqual("ref: refs/heads/feature\n", head);

        // Tracking config written
        var config = await File.ReadAllTextAsync(Path.Combine(_gitDir, "config"));
        StringAssert.Contains(config, "[branch \"feature\"]");
        StringAssert.Contains(config, "remote = origin");
        StringAssert.Contains(config, "merge = refs/heads/feature");

        // Tree checked out
        var content = await File.ReadAllTextAsync(Path.Combine(_testDir, "file.txt"));
        Assert.AreEqual("content", content);
    }

    [TestMethod]
    public async Task ShouldThrowIfBranchDoesNotExist()
    {
        await Init.InitRepo(_testDir);

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Switch.SwitchBranch(_testDir, "nonexistent")
        );
    }

    [TestMethod]
    public async Task ShouldThrowIfNotAGitRepository()
    {
        // _testDir has no .git directory
        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Switch.SwitchBranch(_testDir, "feature-branch")
        );
    }
}
