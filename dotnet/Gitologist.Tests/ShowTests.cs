using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class ShowTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-show-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldReadFileContentAtHEAD()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        var content = await Show.ShowFile(_testDir, "test.txt");

        Assert.AreEqual("content", content);
    }

    [TestMethod]
    public async Task ShouldReadNestedFileContentAtHEAD()
    {
        await Init.InitRepo(_testDir);
        Directory.CreateDirectory(Path.Combine(_testDir, "sub"));
        await File.WriteAllTextAsync(Path.Combine(_testDir, "sub", "inner.txt"), "inner content");
        await Add.AddFiles(_testDir, new[] { "sub/inner.txt" });
        await Commit.CreateCommit(_testDir, "Add nested file");

        var content = await Show.ShowFile(_testDir, "sub/inner.txt");

        Assert.AreEqual("inner content", content);
    }

    [TestMethod]
    public async Task ShouldReflectLatestCommittedContentAfterUpdates()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "v1");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "First");

        Assert.AreEqual("v1", await Show.ShowFile(_testDir, "test.txt"));

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "v2");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second");

        Assert.AreEqual("v2", await Show.ShowFile(_testDir, "test.txt"));
    }

    [TestMethod]
    public async Task ShouldNotReflectUncommittedWorkingChanges()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "committed");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "uncommitted");

        var content = await Show.ShowFile(_testDir, "test.txt");

        Assert.AreEqual("committed", content);
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
                () => Show.ShowFile(nonGitDir, "test.txt")
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
    public async Task ShouldThrowErrorIfFileDoesNotExistInHEAD()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Show.ShowFile(_testDir, "nonexistent.txt")
        );
    }

    [TestMethod]
    public async Task ShouldReadFileContentAtSpecificCommit()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "v1");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "First");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "v2");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var secondSha = await Commit.CreateCommit(_testDir, "Second");

        Assert.AreEqual("v1", await Show.ShowFile(_testDir, "test.txt", firstSha));
        Assert.AreEqual("v2", await Show.ShowFile(_testDir, "test.txt", secondSha));
        Assert.AreEqual("v2", await Show.ShowFile(_testDir, "test.txt"));
    }

    [TestMethod]
    public async Task ShouldThrowPathNotFoundAtOlderCommitForFileAddedLater()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "first.txt"), "first");
        await Add.AddFiles(_testDir, new[] { "first.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "First");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "later.txt"), "later");
        await Add.AddFiles(_testDir, new[] { "later.txt" });
        await Commit.CreateCommit(_testDir, "Add later file");

        var ex = await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Show.ShowFile(_testDir, "later.txt", firstSha)
        );
        StringAssert.Contains(ex.Message, "does not exist in 'HEAD'");
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfCommitDoesNotExist()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        var ex = await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Show.ShowFile(_testDir, "test.txt", "0000000000000000000000000000000000000000")
        );
        StringAssert.Contains(ex.Message, "not found");
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfPathPointsToADirectory()
    {
        await Init.InitRepo(_testDir);
        Directory.CreateDirectory(Path.Combine(_testDir, "sub"));
        await File.WriteAllTextAsync(Path.Combine(_testDir, "sub", "inner.txt"), "inner");
        await Add.AddFiles(_testDir, new[] { "sub/inner.txt" });
        await Commit.CreateCommit(_testDir, "Add nested file");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Show.ShowFile(_testDir, "sub")
        );
    }
}
