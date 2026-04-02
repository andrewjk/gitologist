using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class InitTests
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
    public async Task ShouldCreateGitDirectory()
    {
        await Init.InitRepo(_testDir);
        Assert.IsTrue(Directory.Exists(_gitDir));
    }

    [TestMethod]
    public async Task ShouldNotCreateGitIfItAlreadyExists()
    {
        Directory.CreateDirectory(_gitDir);
        var customFile = Path.Combine(_gitDir, "custom-file");
        await File.WriteAllTextAsync(customFile, "test");

        await Init.InitRepo(_testDir);

        var content = await File.ReadAllTextAsync(customFile);
        Assert.AreEqual("test", content);
    }

    [TestMethod]
    public async Task ShouldCreateHEADFile()
    {
        await Init.InitRepo(_testDir);
        var head = await File.ReadAllTextAsync(Path.Combine(_gitDir, "HEAD"));
        Assert.AreEqual("ref: refs/heads/master\n", head);
    }

    [TestMethod]
    public async Task ShouldCreateConfigFile()
    {
        await Init.InitRepo(_testDir);
        var config = await File.ReadAllTextAsync(Path.Combine(_gitDir, "config"));
        StringAssert.Contains(config, "[core]");
        StringAssert.Contains(config, "repositoryformatversion = 0");
    }

    [TestMethod]
    public async Task ShouldCreateObjectsDirectory()
    {
        await Init.InitRepo(_testDir);
        Assert.IsTrue(Directory.Exists(Path.Combine(_gitDir, "objects")));
    }

    [TestMethod]
    public async Task ShouldCreateRefsHeadsDirectory()
    {
        await Init.InitRepo(_testDir);
        Assert.IsTrue(Directory.Exists(Path.Combine(_gitDir, "refs", "heads")));
    }

    [TestMethod]
    public async Task ShouldCreateRefsTagsDirectory()
    {
        await Init.InitRepo(_testDir);
        Assert.IsTrue(Directory.Exists(Path.Combine(_gitDir, "refs", "tags")));
    }

    [TestMethod]
    public async Task ShouldCreateInfoDirectory()
    {
        await Init.InitRepo(_testDir);
        Assert.IsTrue(Directory.Exists(Path.Combine(_gitDir, "info")));
    }
}
