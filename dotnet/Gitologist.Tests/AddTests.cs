using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class AddTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-add-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldAddASingleFileToIndex()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");

        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var result = await Status.GetStatus(_testDir);
        CollectionAssert.DoesNotContain(result.Untracked, "test.txt");
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldAddMultipleFilesToIndex()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file1.txt"), "content1");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file2.txt"), "content2");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file3.txt"), "content3");

        await Add.AddFiles(_testDir, new[] { "file1.txt", "file2.txt", "file3.txt" });

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldUpdateAModifiedFileInIndex()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "original");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified");

        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldThrowErrorForNonExistentFile()
    {
        await Init.InitRepo(_testDir);

        await Assert.ThrowsExceptionAsync<FileNotFoundException>(
            () => Add.AddFiles(_testDir, new[] { "nonexistent.txt" })
        );
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
                () => Add.AddFiles(nonGitDir, new[] { "test.txt" })
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
    public async Task ShouldAddAllUntrackedFilesWithAddAll()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file1.txt"), "content1");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file2.txt"), "content2");
        Directory.CreateDirectory(Path.Combine(_testDir, "src"));
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts"),
            "console.log('hello')"
        );

        await Add.AddAll(_testDir);

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldAddAllModifiedFilesWithAddAll()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "original");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified");

        await Add.AddAll(_testDir);

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldAddBothUntrackedAndModifiedFilesWithAddAll()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "tracked.txt"), "original");
        await Add.AddFiles(_testDir, new[] { "tracked.txt" });
        await File.WriteAllTextAsync(Path.Combine(_testDir, "tracked.txt"), "modified");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "new.txt"), "new content");

        await Add.AddAll(_testDir);

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldHandleEmptyRepositoryWithAddAll()
    {
        await Init.InitRepo(_testDir);

        await Add.AddAll(_testDir);

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldThrowErrorWithAddAllIfNotAGitRepository()
    {
        var nonGitDir = Path.Combine(
            Path.GetTempPath(),
            $"not-a-repo-{DateTime.UtcNow.Ticks}"
        );
        Directory.CreateDirectory(nonGitDir);

        try
        {
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(
                () => Add.AddAll(nonGitDir)
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
    public async Task ShouldVerifyFileHashInIndex()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var indexPath = Path.Combine(_testDir, ".git", "index");
        var index = await Utils.GetIndex(indexPath);
        var expectedHash = Utils.HashString("content");

        Assert.IsTrue(index.ContainsKey("test.txt"));
        Assert.AreEqual(expectedHash, index["test.txt"].Sha);
        Assert.AreEqual("100644", index["test.txt"].Mode);
    }

    [TestMethod]
    public async Task ShouldPreserveExistingIndexEntriesWhenAddingNewFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file1.txt"), "content1");
        await Add.AddFiles(_testDir, new[] { "file1.txt" });
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file2.txt"), "content2");

        await Add.AddFiles(_testDir, new[] { "file2.txt" });

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }
}
