using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text.RegularExpressions;

namespace Gitologist.Tests;

[TestClass]
public class CommitTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-commit-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldCommitStagedFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var commitSha = await Commit.CreateCommit(_testDir, "Initial commit");

        StringAssert.Matches(commitSha, new Regex(@"^[a-f0-9]{40}$"));

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfNothingToCommit()
    {
        await Init.InitRepo(_testDir);

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Commit.CreateCommit(_testDir, "Empty commit")
        );
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfNoFilesStaged()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Commit.CreateCommit(_testDir, "Test commit")
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
                () => Commit.CreateCommit(nonGitDir, "Test commit")
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
    public async Task ShouldCreateCommitObjectInGitObjects()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        await Commit.CreateCommit(_testDir, "Test commit");

        var objectsDir = Path.Combine(_testDir, ".git", "objects");
        var dirs = Directory.GetDirectories(objectsDir);

        Assert.IsTrue(dirs.Length > 0);
    }

    [TestMethod]
    public async Task ShouldUpdateBranchReference()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var commitSha = await Commit.CreateCommit(_testDir, "Test commit");

        var branchPath = Path.Combine(_testDir, ".git", "refs", "heads", "master");
        var branchRef = await File.ReadAllTextAsync(branchPath);

        Assert.AreEqual(commitSha, branchRef.Trim());
    }

    [TestMethod]
    public async Task ShouldHandleMultipleCommits()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var firstSha = await Commit.CreateCommit(_testDir, "First commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var secondSha = await Commit.CreateCommit(_testDir, "Second commit");

        Assert.AreNotEqual(firstSha, secondSha);

        var branchPath = Path.Combine(_testDir, ".git", "refs", "heads", "master");
        var branchRef = await File.ReadAllTextAsync(branchPath);

        Assert.AreEqual(secondSha, branchRef.Trim());
    }

    [TestMethod]
    public async Task ShouldHandleCommitWithMessageContainingNewlines()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var message = "Multi-line\ncommit\nmessage";
        var commitSha = await Commit.CreateCommit(_testDir, message);

        StringAssert.Matches(commitSha, new Regex(@"^[a-f0-9]{40}$"));
    }

    [TestMethod]
    public async Task ShouldCommitMultipleFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "content1"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "content2"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file3.txt"),
            "content3"
        );

        await Add.AddFiles(
            _testDir,
            new[] { "file1.txt", "file2.txt", "file3.txt" }
        );

        var commitSha = await Commit.CreateCommit(_testDir, "Add multiple files");

        StringAssert.Matches(commitSha, new Regex(@"^[a-f0-9]{40}$"));

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);
        Assert.AreEqual(0, result.Modified.Length);
    }
}
