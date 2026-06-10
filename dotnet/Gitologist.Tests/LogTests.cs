using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text.RegularExpressions;

namespace Gitologist.Tests;

[TestClass]
public class LogTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-log-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldReturnEmptyLogForEmptyRepository()
    {
        await Init.InitRepo(_testDir);

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(0, result.Count);
    }

    [TestMethod]
    public async Task ShouldLogSingleCommit()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(1, result.Count);
        Assert.AreEqual("Initial commit", result[0].Message);
    }

    [TestMethod]
    public async Task ShouldLogMultipleCommitsInReverseOrder()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content1"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "First commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content2"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content3"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Third commit");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(3, result.Count);
        Assert.AreEqual("Third commit", result[0].Message);
        Assert.AreEqual("Second commit", result[1].Message);
        Assert.AreEqual("First commit", result[2].Message);
    }

    [TestMethod]
    public async Task ShouldLimitNumberOfCommits()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content1"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "First commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content2"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content3"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Third commit");

        var options = new LogOptions { Limit = 2 };
        var result = await Log.GetLog(_testDir, options);

        Assert.AreEqual(2, result.Count);
        Assert.AreEqual("Third commit", result[0].Message);
        Assert.AreEqual("Second commit", result[1].Message);
    }

    [TestMethod]
    public async Task ShouldIncludeCommitSHA()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Test commit");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(1, result.Count);
        StringAssert.Matches(result[0].Sha, new Regex(@"^[a-f0-9]{40}$"));
    }

    [TestMethod]
    public async Task ShouldIncludeAbbreviatedSHA()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Test commit");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(1, result.Count);
        StringAssert.Matches(result[0].AbbreviatedSha, new Regex(@"^[a-f0-9]{7}$"));
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
                () => Log.GetLog(nonGitDir)
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
    public async Task ShouldThrowErrorIfBranchNotFound()
    {
        await Init.InitRepo(_testDir);
        var options = new LogOptions { Branch = "nonexistent" };

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Log.GetLog(_testDir, options)
        );
    }

    [TestMethod]
    public async Task ShouldIncludeAuthor()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Test commit");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(1, result.Count);
        Assert.IsFalse(string.IsNullOrEmpty(result[0].Author));
    }

    [TestMethod]
    public async Task ShouldIncludeCommitDate()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Test commit");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(1, result.Count);
        var elapsed = (DateTime.Now - result[0].Date).TotalSeconds;
        Assert.IsTrue(elapsed < 10, "Commit date should be recent");
    }

    [TestMethod]
    public async Task ShouldHandleMultilineCommitMessages()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Multi-line\ncommit\nmessage");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(1, result.Count);
        Assert.AreEqual("Multi-line\ncommit\nmessage", result[0].Message);
    }

    [TestMethod]
    public async Task ShouldIncludeParentCommitReference()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "First commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        var result = await Log.GetLog(_testDir);

        Assert.AreEqual(2, result.Count);
        Assert.AreEqual(firstSha, result[0].Parent);
        Assert.IsNull(result[1].Parent);
    }

    [TestMethod]
    public async Task ShouldReturnEmptyWhenFileNeverExisted()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "First commit");

        var result = await Log.GetLog(_testDir, new LogOptions { File = "nonexistent.txt" });

        Assert.AreEqual(0, result.Count);
    }

    [TestMethod]
    public async Task ShouldReturnOnlyCommitsThatTouchedFile()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "content a");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "b.txt"), "content b");
        await Add.AddFiles(_testDir, new[] { "a.txt", "b.txt" });
        await Commit.CreateCommit(_testDir, "Add both files");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "modified a");
        await Add.AddFiles(_testDir, new[] { "a.txt" });
        await Commit.CreateCommit(_testDir, "Modify a.txt");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "b.txt"), "modified b");
        await Add.AddFiles(_testDir, new[] { "b.txt" });
        await Commit.CreateCommit(_testDir, "Modify b.txt");

        var resultA = await Log.GetLog(_testDir, new LogOptions { File = "a.txt" });
        Assert.AreEqual(2, resultA.Count);
        Assert.AreEqual("Modify a.txt", resultA[0].Message);
        Assert.AreEqual("Add both files", resultA[1].Message);

        var resultB = await Log.GetLog(_testDir, new LogOptions { File = "b.txt" });
        Assert.AreEqual(2, resultB.Count);
        Assert.AreEqual("Modify b.txt", resultB[0].Message);
        Assert.AreEqual("Add both files", resultB[1].Message);
    }

    [TestMethod]
    public async Task ShouldWorkWithNestedFilePaths()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "outer.txt"), "outer");
        await Add.AddFiles(_testDir, new[] { "outer.txt" });
        await Commit.CreateCommit(_testDir, "Add outer.txt");

        Directory.CreateDirectory(Path.Combine(_testDir, "sub"));
        await File.WriteAllTextAsync(Path.Combine(_testDir, "sub", "inner.txt"), "inner");
        await Add.AddFiles(_testDir, new[] { "sub/inner.txt" });
        await Commit.CreateCommit(_testDir, "Add sub/inner.txt");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "sub", "inner.txt"), "modified");
        await Add.AddFiles(_testDir, new[] { "sub/inner.txt" });
        await Commit.CreateCommit(_testDir, "Modify sub/inner.txt");

        var result = await Log.GetLog(_testDir, new LogOptions { File = "sub/inner.txt" });

        Assert.AreEqual(2, result.Count);
        Assert.AreEqual("Modify sub/inner.txt", result[0].Message);
        Assert.AreEqual("Add sub/inner.txt", result[1].Message);
    }

    [TestMethod]
    public async Task ShouldRespectLimitWithFileFilter()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "v1");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "First");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "v2");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Second");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "v3");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Third");

        var result = await Log.GetLog(_testDir, new LogOptions { File = "file.txt", Limit = 2 });

        Assert.AreEqual(2, result.Count);
        Assert.AreEqual("Third", result[0].Message);
        Assert.AreEqual("Second", result[1].Message);
    }

    [TestMethod]
    public async Task ShouldIncludeInitialCommitWhenFileWasAdded()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "initial");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Add file.txt");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "other.txt"), "other");
        await Add.AddFiles(_testDir, new[] { "other.txt" });
        await Commit.CreateCommit(_testDir, "Add other.txt");

        var result = await Log.GetLog(_testDir, new LogOptions { File = "file.txt" });

        Assert.AreEqual(1, result.Count);
        Assert.AreEqual("Add file.txt", result[0].Message);
    }
}
