using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class BranchTests
{
    private string _testDir = null!;
    private string _gitDir = null!;

    [TestInitialize]
    public void Setup()
    {
        _testDir = Path.Combine(Path.GetTempPath(), $"gitologist-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_testDir);
        _gitDir = Path.Combine(_testDir, ".git");
    }

    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(_testDir))
            Directory.Delete(_testDir, true);
    }

    [TestMethod]
    public async Task ShouldReturnBranchNameFromHEAD()
    {
        Directory.CreateDirectory(_gitDir);
        await File.WriteAllTextAsync(Path.Combine(_gitDir, "HEAD"), "ref: refs/heads/main\n");
        var branch = await Branch.GetCurrentBranch(_gitDir);
        Assert.AreEqual("main", branch);
    }

    [TestMethod]
    public async Task ShouldThrowIfHEADIsDetached()
    {
        Directory.CreateDirectory(_gitDir);
        await File.WriteAllTextAsync(Path.Combine(_gitDir, "HEAD"), "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\n");
        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Branch.GetCurrentBranch(_gitDir)
        );
    }

    [TestMethod]
    public async Task ShouldReturnCurrentCommitSHA()
    {
        Directory.CreateDirectory(_gitDir);
        await File.WriteAllTextAsync(Path.Combine(_gitDir, "HEAD"), "ref: refs/heads/main\n");
        var refsHeads = Path.Combine(_gitDir, "refs", "heads");
        Directory.CreateDirectory(refsHeads);
        await File.WriteAllTextAsync(Path.Combine(refsHeads, "main"), "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\n");
        var commitSha = await Branch.GetCurrentCommit(_gitDir);
        Assert.AreEqual("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2", commitSha);
    }

    [TestMethod]
    public async Task ShouldReturnNullIfNoCommitExists()
    {
        Directory.CreateDirectory(_gitDir);
        await File.WriteAllTextAsync(Path.Combine(_gitDir, "HEAD"), "ref: refs/heads/main\n");
        var commitSha = await Branch.GetCurrentCommit(_gitDir);
        Assert.IsNull(commitSha);
    }
}
