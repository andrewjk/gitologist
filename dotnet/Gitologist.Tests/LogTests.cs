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
}
