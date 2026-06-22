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

    private void CreateBranchRef(string name)
    {
        var refsHeadsDir = Path.Combine(_gitDir, "refs", "heads");
        Directory.CreateDirectory(refsHeadsDir);
        File.WriteAllText(Path.Combine(refsHeadsDir, name), "abc123\n");
    }

    [TestMethod]
    public async Task ShouldWriteBranchNameToHEAD()
    {
        Directory.CreateDirectory(_gitDir);
        CreateBranchRef("feature-branch");

        await Switch.SwitchBranch(_testDir, "feature-branch");

        var head = await File.ReadAllTextAsync(Path.Combine(_gitDir, "HEAD"));
        Assert.AreEqual("ref: refs/heads/feature-branch\n", head);
    }

    [TestMethod]
    public async Task ShouldThrowIfNotAGitRepository()
    {
        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Switch.SwitchBranch(_testDir, "feature-branch")
        );
    }

    [TestMethod]
    public async Task ShouldThrowIfBranchDoesNotExist()
    {
        Directory.CreateDirectory(_gitDir);

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Switch.SwitchBranch(_testDir, "nonexistent")
        );
    }
}
