using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text.RegularExpressions;

namespace Gitologist.Tests;

[TestClass]
public class MergeTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-merge-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
                () => Merge.MergeBranch(nonGitDir, "feature")
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
    public async Task ShouldThrowErrorWhenMergingABranchIntoItself()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Merge.MergeBranch(_testDir, "main")
        );
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfBranchNotFound()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Merge.MergeBranch(_testDir, "nonexistent")
        );
    }

    [TestMethod]
    public async Task ShouldThrowErrorWhenMergingIntoEmptyBranch()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await CreateBranch(_testDir, "feature");
        await CheckoutBranch(_testDir, "feature");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "feature.txt"),
            "feature content"
        );
        await Add.AddFiles(_testDir, new[] { "feature.txt" });
        await Commit.CreateCommit(_testDir, "Feature commit");

        await CheckoutBranch(_testDir, "main");
        await DeleteBranchCommit(_testDir);

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Merge.MergeBranch(_testDir, "feature")
        );
    }

    [TestMethod]
    public async Task ShouldPerformFastForwardMergeWhenPossible()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await CreateBranch(_testDir, "feature");
        await CheckoutBranch(_testDir, "feature");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "feature.txt"),
            "feature content"
        );
        await Add.AddFiles(_testDir, new[] { "feature.txt" });
        var featureSha = await Commit.CreateCommit(_testDir, "Feature commit");

        await CheckoutBranch(_testDir, "main");

        var result = await Merge.MergeBranch(_testDir, "feature");

        Assert.IsTrue(result.Success);
        Assert.IsTrue(result.FastForward);
        Assert.AreEqual(featureSha, result.CommitSha);
    }

    [TestMethod]
    public async Task ShouldCreateMergeCommitWhenNotFastForward()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await CreateBranch(_testDir, "feature");
        await CheckoutBranch(_testDir, "feature");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "feature.txt"),
            "feature content"
        );
        await Add.AddFiles(_testDir, new[] { "feature.txt" });
        await Commit.CreateCommit(_testDir, "Feature commit");

        await CheckoutBranch(_testDir, "main");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "main.txt"),
            "main content"
        );
        await Add.AddFiles(_testDir, new[] { "main.txt" });
        await Commit.CreateCommit(_testDir, "Master commit");

        var result = await Merge.MergeBranch(_testDir, "feature");

        Assert.IsTrue(result.Success);
        Assert.IsFalse(result.FastForward);
        StringAssert.Matches(result.CommitSha, new Regex(@"^[a-f0-9]{40}$"));
    }

    [TestMethod]
    public async Task ShouldAllowNonFastForwardMergeWithOption()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await CreateBranch(_testDir, "feature");
        await CheckoutBranch(_testDir, "feature");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "feature.txt"),
            "feature content"
        );
        await Add.AddFiles(_testDir, new[] { "feature.txt" });
        await Commit.CreateCommit(_testDir, "Feature commit");

        await CheckoutBranch(_testDir, "main");

        var options = new MergeOptions { NoFastForward = true };
        var result = await Merge.MergeBranch(_testDir, "feature", options);

        Assert.IsTrue(result.Success);
        Assert.IsFalse(result.FastForward);
        StringAssert.Matches(result.CommitSha, new Regex(@"^[a-f0-9]{40}$"));
    }

    [TestMethod]
    public async Task ShouldReportAlreadyUpToDateWhenBranchesAreSame()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await CreateBranch(_testDir, "feature");

        var result = await Merge.MergeBranch(_testDir, "feature");

        Assert.IsTrue(result.Success);
        Assert.AreEqual("Already up to date.", result.Message);
    }

    [TestMethod]
    public async Task ShouldUseCustomMergeMessage()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await CreateBranch(_testDir, "feature");
        await CheckoutBranch(_testDir, "feature");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "feature.txt"),
            "feature content"
        );
        await Add.AddFiles(_testDir, new[] { "feature.txt" });
        await Commit.CreateCommit(_testDir, "Feature commit");

        await CheckoutBranch(_testDir, "main");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "main.txt"),
            "main content"
        );
        await Add.AddFiles(_testDir, new[] { "main.txt" });
        await Commit.CreateCommit(_testDir, "Master commit");

        var options = new MergeOptions { Message = "Custom merge message" };
        var result = await Merge.MergeBranch(_testDir, "feature", options);

        Assert.IsTrue(result.Success);
        Assert.AreEqual("Custom merge message", result.Message);
    }

    private static async Task CreateBranch(string path, string branchName)
    {
        var gitDir = Path.Combine(path, ".git");
        var headPath = Path.Combine(gitDir, "HEAD");
        var currentHead = (await File.ReadAllTextAsync(headPath)).Trim();
        var match = Regex.Match(currentHead, @"^ref: refs\/heads\/(.+)$");

        if (!match.Success)
        {
            throw new InvalidOperationException("Not on a branch");
        }

        var currentBranch = match.Groups[1].Value;
        var currentBranchPath = Path.Combine(gitDir, "refs", "heads", currentBranch);

        if (!File.Exists(currentBranchPath))
        {
            throw new InvalidOperationException("Current branch has no commits");
        }

        var currentCommit = await File.ReadAllTextAsync(currentBranchPath);

        var newBranchPath = Path.Combine(gitDir, "refs", "heads", branchName);
        Directory.CreateDirectory(Path.GetDirectoryName(newBranchPath)!);
        await File.WriteAllTextAsync(newBranchPath, currentCommit);
    }

    private static async Task CheckoutBranch(string path, string branchName)
    {
        var gitDir = Path.Combine(path, ".git");
        var headPath = Path.Combine(gitDir, "HEAD");
        await File.WriteAllTextAsync(headPath, $"ref: refs/heads/{branchName}\n");
    }

    private static async Task DeleteBranchCommit(string path)
    {
        var gitDir = Path.Combine(path, ".git");
        var headPath = Path.Combine(gitDir, "HEAD");
        var currentHead = (await File.ReadAllTextAsync(headPath)).Trim();
        var match = Regex.Match(currentHead, @"^ref: refs\/heads\/(.+)$");

        if (!match.Success)
        {
            throw new InvalidOperationException("Not on a branch");
        }

        var currentBranch = match.Groups[1].Value;
        var currentBranchPath = Path.Combine(gitDir, "refs", "heads", currentBranch);

        if (File.Exists(currentBranchPath))
        {
            File.Delete(currentBranchPath);
        }
    }
}
