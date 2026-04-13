using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class StatusTests
{
    private string _testDir = null!;
    private string _gitDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-status-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
        );
        Directory.CreateDirectory(_testDir);
        _gitDir = Path.Combine(_testDir, ".git");
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
    public async Task ShouldReturnCurrentBranch()
    {
        await Init.InitRepo(_testDir);
        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual("main", result.Branch);
    }

    [TestMethod]
    public async Task ShouldReturnUpToDateMessage()
    {
        await Init.InitRepo(_testDir);
        var result = await Status.GetStatus(_testDir);
        StringAssert.Contains(result.UpToDate, "Your branch is up to date with");
    }

    [TestMethod]
    public async Task ShouldReturnEmptyArraysForChangesWhenNoFilesExist()
    {
        await Init.InitRepo(_testDir);
        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Staged.Length);
        Assert.AreEqual(0, result.Modified.Length);
        Assert.AreEqual(0, result.Untracked.Length);
    }

    [TestMethod]
    public async Task ShouldDetectUntrackedFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");

        var result = await Status.GetStatus(_testDir);
        CollectionAssert.Contains(result.Untracked, "test.txt");
        Assert.AreEqual(0, result.Modified.Length);
        Assert.AreEqual(0, result.Staged.Length);
    }

    [TestMethod]
    public async Task ShouldDetectMultipleUntrackedFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "README.md"), "# Test");
        Directory.CreateDirectory(Path.Combine(_testDir, "src"));
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts"),
            "console.log('hello')"
        );

        var result = await Status.GetStatus(_testDir);
        CollectionAssert.Contains(result.Untracked, "test.txt");
        CollectionAssert.Contains(result.Untracked, "README.md");
        CollectionAssert.Contains(result.Untracked, Path.Combine("src", "index.ts"));
    }

    [TestMethod]
    public async Task ShouldDetectModifiedFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "original");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified content");

        var result = await Status.GetStatus(_testDir);
        CollectionAssert.Contains(result.Modified, "test.txt");
        Assert.AreEqual(0, result.Untracked.Length);
    }

    [TestMethod]
    public async Task ShouldDetectDeletedFilesAsModified()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        File.Delete(Path.Combine(_testDir, "test.txt"));

        var result = await Status.GetStatus(_testDir);
        CollectionAssert.Contains(result.Deleted, "test.txt");
    }

    [TestMethod]
    public async Task ShouldHandleDetachedHead()
    {
        await Init.InitRepo(_testDir);
        var headPath = Path.Combine(_testDir, ".git", "HEAD");
        await File.WriteAllTextAsync(headPath, "deadbeef\n");

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual("(detached HEAD)", result.Branch);
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
                () => Status.GetStatus(nonGitDir)
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
    public async Task ShouldHandleCustomBranchName()
    {
        await Init.InitRepo(_testDir);
        var headPath = Path.Combine(_testDir, ".git", "HEAD");
        await File.WriteAllTextAsync(headPath, "ref: refs/heads/main\n");

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual("main", result.Branch);
    }

    [TestMethod]
    public async Task ShouldNotDetectGitDirectoryAsUntracked()
    {
        await Init.InitRepo(_testDir);
        Directory.CreateDirectory(Path.Combine(_testDir, ".git", "other"));
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, ".git", "other", "file.txt"),
            "content"
        );

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
    }

    [TestMethod]
    public async Task ShouldCorrectlyIdentifyFilesMatchingIndex()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Modified.Length);
        Assert.AreEqual(0, result.Untracked.Length);
    }
}
