using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class CloneTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-clone-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldCloneARepositoryToDefaultDirectory()
    {
        var url = "https://github.com/user/repo.git";
        var targetPath = Path.Combine(_testDir, "repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        Assert.AreEqual(targetPath, resultPath);

        var gitDir = Path.Combine(resultPath, ".git");
        Assert.IsTrue(Directory.Exists(gitDir));
    }

    [TestMethod]
    public async Task ShouldCloneToSpecifiedDirectory()
    {
        var url = "https://github.com/user/repo.git";
        var targetPath = Path.Combine(_testDir, "my-custom-dir");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        Assert.AreEqual(targetPath, resultPath);

        Assert.IsTrue(Directory.Exists(targetPath));
    }

    [TestMethod]
    public async Task ShouldExtractRepoNameFromURL()
    {
        var url = "https://github.com/user/my-repo.git";
        var targetPath = Path.Combine(_testDir, "test-repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        Assert.AreEqual(targetPath, resultPath);
    }

    [TestMethod]
    public async Task ShouldInitializeGitRepository()
    {
        var url = "https://github.com/user/repo.git";
        var targetPath = Path.Combine(_testDir, "test-repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        var headPath = Path.Combine(resultPath, ".git", "HEAD");
        var headContent = await File.ReadAllTextAsync(headPath);

        StringAssert.Contains(headContent, "ref: refs/heads/main");
    }

    [TestMethod]
    public async Task ShouldAddRemote()
    {
        var url = "https://github.com/user/repo.git";
        var targetPath = Path.Combine(_testDir, "test-repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        var configPath = Path.Combine(resultPath, ".git", "config");
        var configContent = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(configContent, "[remote \"origin\"]");
        StringAssert.Contains(configContent, "url = https://github.com/user/repo.git");
    }

    [TestMethod]
    public async Task ShouldHandleURLsWithGitExtension()
    {
        var url = "https://github.com/user/repo.git";
        var targetPath = Path.Combine(_testDir, "test-repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        Assert.AreEqual(targetPath, resultPath);

        var configPath = Path.Combine(resultPath, ".git", "config");
        var configContent = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(configContent, "url = https://github.com/user/repo.git");
    }

    [TestMethod]
    public async Task ShouldHandleURLsWithoutGitExtension()
    {
        var url = "https://github.com/user/repo";
        var targetPath = Path.Combine(_testDir, "test-repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        Assert.AreEqual(targetPath, resultPath);

        var configPath = Path.Combine(resultPath, ".git", "config");
        var configContent = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(configContent, "url = https://github.com/user/repo");
    }

    [TestMethod]
    public async Task ShouldExtractRepoNameFromComplexURL()
    {
        var url = "https://github.com/org/team/project.git";
        var targetPath = Path.Combine(_testDir, "test-repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        Assert.AreEqual(targetPath, resultPath);
    }

    [TestMethod]
    public async Task ShouldHandleSubdirectoryInURL()
    {
        var url = "https://github.com/user/nested/project.git";
        var targetPath = Path.Combine(_testDir, "test-repo");
        var resultPath = await Clone.CloneRepo(url, targetPath);

        Assert.AreEqual(targetPath, resultPath);
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfDirectoryAlreadyExists()
    {
        var url = "https://github.com/user/repo.git";
        var existingPath = Path.Combine(_testDir, "repo");
        Directory.CreateDirectory(existingPath);

        try
        {
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(
                () => Clone.CloneRepo(url, existingPath)
            );
        }
        finally
        {
            try
            {
                Directory.Delete(existingPath, true);
            }
            catch
            {
            }
        }
    }
}
