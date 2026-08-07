using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class PullTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-pull-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldPullFromDefaultRemoteAndBranch()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        await Pull.PullFromRemote(_testDir);

        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "test.txt")
        );
        Assert.AreEqual("modified", content);
    }

    [TestMethod]
    public async Task ShouldPullFromSpecifiedRemote()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir, "upstream");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir, "upstream");

        await Pull.PullFromRemote(_testDir, "upstream");

        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "test.txt")
        );
        Assert.AreEqual("modified", content);
    }

    [TestMethod]
    public async Task ShouldPullFromSpecifiedBranch()
    {
        await Init.InitRepo(_testDir);
        var headPath = Path.Combine(_testDir, ".git", "HEAD");
        await File.WriteAllTextAsync(headPath, "ref: refs/heads/main");

        Directory.CreateDirectory(
            Path.Combine(_testDir, ".git", "refs", "heads")
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, ".git", "refs", "heads", "main"),
            "abc123"
        );

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir, "origin", "main");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir, "origin", "main");

        await Pull.PullFromRemote(_testDir, "origin", "main");

        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "test.txt")
        );
        Assert.AreEqual("modified", content);
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
                () => Pull.PullFromRemote(nonGitDir)
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
    public async Task ShouldThrowErrorIfRemoteBranchDoesNotExist()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Pull.PullFromRemote(_testDir)
        );
    }

    [TestMethod]
    public async Task ShouldUpdateLocalBranchReference()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var secondSha = await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        await Pull.PullFromRemote(_testDir);

        var localBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "heads",
            "main"
        );
        var localBranchContent = await File.ReadAllTextAsync(localBranchPath);

        Assert.AreEqual(secondSha, localBranchContent.Trim());
    }

    [TestMethod]
    public async Task ShouldHandleDirectories()
    {
        await Init.InitRepo(_testDir);
        Directory.CreateDirectory(Path.Combine(_testDir, "src"));
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts"),
            "console.log('hello')"
        );
        await Add.AddFiles(_testDir, new[] { "src/index.ts" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts"),
            "console.log('world')"
        );
        await Add.AddFiles(_testDir, new[] { "src/index.ts" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        await Pull.PullFromRemote(_testDir);

        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "src", "index.ts")
        );
        Assert.AreEqual("console.log('world')", content);
    }

    [TestMethod]
    public async Task ShouldHandleMultipleFiles()
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
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

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
        await Add.AddFiles(
            _testDir,
            new[] { "file1.txt", "file2.txt", "file3.txt" }
        );
        await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        await Pull.PullFromRemote(_testDir);

        var content1 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file1.txt")
        );
        var content2 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file2.txt")
        );
        var content3 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file3.txt")
        );

        Assert.AreEqual("modified1", content1);
        Assert.AreEqual("modified2", content2);
        Assert.AreEqual("modified3", content3);
    }

    [TestMethod]
    public async Task ShouldFastForwardWhenRemoteIsAhead()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var secondSha = await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        // Reset local branch back to first commit to simulate another clone
        var localBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "heads",
            "main"
        );
        await File.WriteAllTextAsync(localBranchPath, firstSha);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        await Pull.PullFromRemote(_testDir);

        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "test.txt")
        );
        Assert.AreEqual("modified", content);

        var localBranchContent = await File.ReadAllTextAsync(localBranchPath);
        Assert.AreEqual(secondSha, localBranchContent.Trim());
    }

    [TestMethod]
    public async Task ShouldThrowErrorWhenLocalChangesWouldBeOverwritten()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "modified"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        // Reset local branch back to first commit
        var localBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "heads",
            "main"
        );
        await File.WriteAllTextAsync(localBranchPath, firstSha);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "content"
        );
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        // Make uncommitted local change
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "test.txt"),
            "local changes"
        );

        var exception = await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Pull.PullFromRemote(_testDir)
        );
        Assert.IsTrue(exception.Message.Contains("would be overwritten by merge"));

        // Verify local changes are preserved
        var content = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "test.txt")
        );
        Assert.AreEqual("local changes", content);
    }

    [TestMethod]
    public async Task ShouldDeleteFilesRemovedOnRemote()
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
        var firstSha = await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        // Remove file2 on the remote
        File.Delete(Path.Combine(_testDir, "file2.txt"));
        await Add.AddAll(_testDir);
        await Commit.CreateCommit(_testDir, "Remove file2");

        await Push.PushToRemote(_testDir);

        // Reset local branch back to first commit to simulate another clone
        var localBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "heads",
            "main"
        );
        await File.WriteAllTextAsync(localBranchPath, firstSha);
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

        await Pull.PullFromRemote(_testDir);

        // file2 should be deleted from the working tree
        Assert.IsFalse(File.Exists(Path.Combine(_testDir, "file2.txt")));

        // surviving files should be untouched
        var content1 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file1.txt")
        );
        var content3 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file3.txt")
        );
        Assert.AreEqual("content1", content1);
        Assert.AreEqual("content3", content3);
    }

    [TestMethod]
    public async Task ShouldPreserveLocallyModifiedFileDeletedOnRemote()
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
        await Add.AddFiles(_testDir, new[] { "file1.txt", "file2.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        // Remove file2 on the remote
        File.Delete(Path.Combine(_testDir, "file2.txt"));
        await Add.AddAll(_testDir);
        await Commit.CreateCommit(_testDir, "Remove file2");

        await Push.PushToRemote(_testDir);

        // Reset local branch back to first commit to simulate another clone
        var localBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "heads",
            "main"
        );
        await File.WriteAllTextAsync(localBranchPath, firstSha);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "content1"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "content2"
        );
        await Add.AddFiles(_testDir, new[] { "file1.txt", "file2.txt" });

        // Make uncommitted local edits to file2, which was deleted on the remote
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "local changes"
        );

        await Pull.PullFromRemote(_testDir);

        // file2 should be preserved because it has uncommitted local edits
        var content2 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file2.txt")
        );
        Assert.AreEqual("local changes", content2);

        // file1 should be untouched
        var content1 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file1.txt")
        );
        Assert.AreEqual("content1", content1);
    }

    [TestMethod]
    public async Task ShouldNotOverwriteUnchangedFilesWithLocalModifications()
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
        await Add.AddFiles(_testDir, new[] { "file1.txt", "file2.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        // Commit a change only to file1
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "modified1"
        );
        await Add.AddFiles(_testDir, new[] { "file1.txt" });
        var secondSha = await Commit.CreateCommit(_testDir, "Second commit");

        await Push.PushToRemote(_testDir);

        // Reset local branch back to first commit
        var localBranchPath = Path.Combine(
            _testDir,
            ".git",
            "refs",
            "heads",
            "main"
        );
        await File.WriteAllTextAsync(localBranchPath, firstSha);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file1.txt"),
            "content1"
        );
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "content2"
        );
        await Add.AddFiles(_testDir, new[] { "file1.txt", "file2.txt" });

        // Make uncommitted change to file2 (which did not change in the pull)
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file2.txt"),
            "local changes to file2"
        );

        await Pull.PullFromRemote(_testDir);

        // file1 should be updated
        var content1 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file1.txt")
        );
        Assert.AreEqual("modified1", content1);

        // file2 local changes should be preserved since it wasn't changed in the pull
        var content2 = await File.ReadAllTextAsync(
            Path.Combine(_testDir, "file2.txt")
        );
        Assert.AreEqual("local changes to file2", content2);
    }
}
