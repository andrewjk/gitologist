using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class RemoteTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-remote-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldAddARemote()
    {
        await Init.InitRepo(_testDir);
        await Remote.AddRemote(
            _testDir,
            "origin",
            "https://github.com/user/repo.git"
        );

        var configPath = Path.Combine(_testDir, ".git", "config");
        var configContent = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(configContent, "[remote \"origin\"]");
        StringAssert.Contains(configContent, "url = https://github.com/user/repo.git");
    }

    [TestMethod]
    public async Task ShouldAddFetchRefspec()
    {
        await Init.InitRepo(_testDir);
        await Remote.AddRemote(
            _testDir,
            "origin",
            "https://github.com/user/repo.git"
        );

        var configPath = Path.Combine(_testDir, ".git", "config");
        var configContent = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(configContent, "fetch = +refs/heads/*:refs/remotes/origin/*");
    }

    [TestMethod]
    public async Task ShouldAddRemoteWithCustomName()
    {
        await Init.InitRepo(_testDir);
        await Remote.AddRemote(
            _testDir,
            "upstream",
            "https://github.com/original/repo.git"
        );

        var configPath = Path.Combine(_testDir, ".git", "config");
        var configContent = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(configContent, "[remote \"upstream\"]");
        StringAssert.Contains(configContent, "url = https://github.com/original/repo.git");
        StringAssert.Contains(configContent, "fetch = +refs/heads/*:refs/remotes/upstream/*");
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
                () =>
                    Remote.AddRemote(
                        nonGitDir,
                        "origin",
                        "https://github.com/user/repo.git"
                    )
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
    public async Task ShouldThrowErrorIfRemoteAlreadyExists()
    {
        await Init.InitRepo(_testDir);
        await Remote.AddRemote(
            _testDir,
            "origin",
            "https://github.com/user/repo.git"
        );

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () =>
                Remote.AddRemote(
                    _testDir,
                    "origin",
                    "https://github.com/other/repo.git"
                )
        );
    }

    [TestMethod]
    public async Task ShouldPreserveExistingConfig()
    {
        await Init.InitRepo(_testDir);
        await Remote.AddRemote(
            _testDir,
            "origin",
            "https://github.com/user/repo.git"
        );
        await Remote.AddRemote(
            _testDir,
            "upstream",
            "https://github.com/original/repo.git"
        );

        var configPath = Path.Combine(_testDir, ".git", "config");
        var configContent = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(configContent, "[remote \"origin\"]");
        StringAssert.Contains(configContent, "[remote \"upstream\"]");
        StringAssert.Contains(configContent, "url = https://github.com/user/repo.git");
        StringAssert.Contains(configContent, "url = https://github.com/original/repo.git");
    }

    [TestMethod]
    public async Task ShouldAppendToExistingConfigFile()
    {
        await Init.InitRepo(_testDir);
        var configPath = Path.Combine(_testDir, ".git", "config");
        var originalConfig = await File.ReadAllTextAsync(configPath);

        await Remote.AddRemote(
            _testDir,
            "origin",
            "https://github.com/user/repo.git"
        );

        var newConfig = await File.ReadAllTextAsync(configPath);

        StringAssert.Contains(newConfig, originalConfig.Trim());
        StringAssert.Contains(newConfig, "[remote \"origin\"]");
    }
}
