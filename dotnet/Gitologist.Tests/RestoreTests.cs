using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class RestoreTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-restore-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldRestoreAModifiedFile()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "original"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );

        await Restore.RestoreFiles(_testDir, new[] { "test.txt" });

        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "test.txt")
        );
        Assert.AreEqual("original", content);
    }

    [TestMethod]
    public async Task ShouldRestoreMultipleFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "original1"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "original2"
        );
        await Add.AddFiles(_testDir, new[] { "file1.txt", "file2.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "modified1"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "modified2"
        );

        await Restore.RestoreFiles(_testDir, new[] { "file1.txt", "file2.txt" });

        var content1 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file1.txt")
        );
        var content2 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file2.txt")
        );
        Assert.AreEqual("original1", content1);
        Assert.AreEqual("original2", content2);
    }

    [TestMethod]
    public async Task ShouldThrowErrorForNonExistentFile()
    {
        await Init.InitRepo(_testDir);

        await Assert.ThrowsExceptionAsync<FileNotFoundException>(
            () => Restore.RestoreFiles(_testDir, new[] { "nonexistent.txt" })
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
                () => Restore.RestoreFiles(nonGitDir, new[] { "test.txt" })
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
    public async Task ShouldThrowErrorIfFileNotInCommit()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "newfile.txt"),
            "new content"
        );

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Restore.RestoreFiles(_testDir, new[] { "newfile.txt" })
        );
    }

    [TestMethod]
    public async Task ShouldUpdateStatusAfterRestore()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "original"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );

        var result = await Status.GetStatus(_testDir);
        CollectionAssert.Contains(result.Modified, "test.txt");

        await Restore.RestoreFiles(_testDir, new[] { "test.txt" });

        result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldRestoreAllModifiedFilesWithRestoreAll()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "original1"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "original2"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file3.txt"),
            "original3"
        );
        await Add.AddFiles(
            _testDir,
            new[] { "file1.txt", "file2.txt", "file3.txt" }
        );
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "modified1"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "modified2"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file3.txt"),
            "modified3"
        );

        await Restore.RestoreAll(_testDir);

        var content1 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file1.txt")
        );
        var content2 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file2.txt")
        );
        var content3 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file3.txt")
        );

        Assert.AreEqual("original1", content1);
        Assert.AreEqual("original2", content2);
        Assert.AreEqual("original3", content3);
    }

    [TestMethod]
    public async Task ShouldDoNothingWithRestoreAllWhenNoModifiedFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Restore.RestoreAll(_testDir);

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldThrowErrorWithRestoreAllIfNotAGitRepository()
    {
        var nonGitDir = Path.Combine(
            Path.GetTempPath(),
            $"not-a-repo-{DateTime.UtcNow.Ticks}"
        );
        Directory.CreateDirectory(nonGitDir);

        try
        {
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(
                () => Restore.RestoreAll(nonGitDir)
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
    public async Task ShouldHandleFilesInSubdirectories()
    {
        await Init.InitRepo(_testDir);
        Directory.CreateDirectory(Path.Combine(_testDir, "src"));
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts"),
            "original"
        );
        await Add.AddFiles(_testDir, new[] { "src/index.ts" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts"),
            "modified"
        );

        await Restore.RestoreFiles(_testDir, new[] { "src/index.ts" });

        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts")
        );
        Assert.AreEqual("original", content);
    }
}
