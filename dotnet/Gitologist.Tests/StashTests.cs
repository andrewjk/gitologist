using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class StashTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-stash-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public async Task ShouldStashAModifiedFile()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "initial content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified content");

        var stashSha = await Stash.CreateStash(_testDir, "WIP");

        Assert.IsTrue(System.Text.RegularExpressions.Regex.IsMatch(stashSha, @"^[a-f0-9]{40}$"));

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Modified.Length);

        var fileContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "test.txt"));
        Assert.AreEqual("initial content", fileContent);
    }

    [TestMethod]
    public async Task ShouldStashAnUntrackedFile()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "initial content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "newfile.txt"), "untracked content");

        var stashSha = await Stash.CreateStash(_testDir, "WIP");

        Assert.IsTrue(System.Text.RegularExpressions.Regex.IsMatch(stashSha, @"^[a-f0-9]{40}$"));

        var result = await Status.GetStatus(_testDir);
        Assert.AreEqual(0, result.Untracked.Length);

        Assert.IsFalse(File.Exists(Path.Combine(_testDir, "newfile.txt")));
    }

    [TestMethod]
    public async Task ShouldUpdateStashRef()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified");

        var stashSha = await Stash.CreateStash(_testDir, "Save work");

        var stashRefPath = Path.Combine(_testDir, ".git", "refs", "stash");
        var refContent = await File.ReadAllTextAsync(stashRefPath);

        Assert.AreEqual(stashSha, refContent.Trim());
    }

    [TestMethod]
    public async Task ShouldResetIndexToHEADAfterStash()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "initial content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });

        var preStashStatus = await Status.GetStatus(_testDir);
        Assert.IsTrue(preStashStatus.Staged.Contains("test.txt"));

        await Stash.CreateStash(_testDir, "WIP");

        var postStashStatus = await Status.GetStatus(_testDir);

        var fileContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "test.txt"));
        Assert.AreEqual("initial content", fileContent);
        Assert.AreEqual(0, postStashStatus.Modified.Length);
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfNothingToStash()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Stash.CreateStash(_testDir, "WIP")
        );
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfNotAGitRepository()
    {
        var nonGitDir = Path.Combine(
            Path.GetTempPath(),
            $"not-a-repo-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
        );
        Directory.CreateDirectory(nonGitDir);

        try
        {
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(
                () => Stash.CreateStash(nonGitDir, "WIP")
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
    public async Task ShouldHandleCustomStashMessage()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified");

        var message = "Work in progress on feature X";
        await Stash.CreateStash(_testDir, message);

        var stashRefPath = Path.Combine(_testDir, ".git", "refs", "stash");
        var stashSha = (await File.ReadAllTextAsync(stashRefPath)).Trim();

        var commitPath = Path.Combine(
            _testDir,
            ".git",
            "objects",
            stashSha.Substring(0, 2),
            stashSha.Substring(2)
        );

        Assert.IsTrue(File.Exists(commitPath));
    }

    [TestMethod]
    public async Task ShouldRestoreStashedModifiedFile()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "initial content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified content");

        await Stash.CreateStash(_testDir, "WIP");

        var afterStashContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "test.txt"));
        Assert.AreEqual("initial content", afterStashContent);

        await Stash.Unstash(_testDir);

        var afterUnstashContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "test.txt"));
        Assert.AreEqual("modified content", afterUnstashContent);

        var statusResult = await Status.GetStatus(_testDir);
        Assert.IsTrue(statusResult.Modified.Contains("test.txt"));
    }

    [TestMethod]
    public async Task ShouldRestoreStashedUntrackedFile()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "initial content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "newfile.txt"), "untracked content");

        await Stash.CreateStash(_testDir, "WIP");

        var existsAfterStash = File.Exists(Path.Combine(_testDir, "newfile.txt"));
        Assert.IsFalse(existsAfterStash);

        await Stash.Unstash(_testDir);

        var existsAfterUnstash = File.Exists(Path.Combine(_testDir, "newfile.txt"));
        Assert.IsTrue(existsAfterUnstash);

        var content = await File.ReadAllTextAsync(Path.Combine(_testDir, "newfile.txt"));
        Assert.AreEqual("untracked content", content);

        var statusResult = await Status.GetStatus(_testDir);
        Assert.IsTrue(statusResult.Untracked.Contains("newfile.txt"));
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfNoStashExists()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "content");
        await Add.AddFiles(_testDir, new[] { "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(
            () => Stash.Unstash(_testDir)
        );
    }

    [TestMethod]
    public async Task ShouldThrowErrorIfNotAGitRepositoryForUnstash()
    {
        var nonGitDir = Path.Combine(
            Path.GetTempPath(),
            $"not-a-repo-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
        );
        Directory.CreateDirectory(nonGitDir);

        try
        {
            await Assert.ThrowsExceptionAsync<InvalidOperationException>(
                () => Stash.Unstash(nonGitDir)
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
    public async Task ShouldPreserveIgnoredFilesWhenStashing()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "initial content");
        await File.WriteAllTextAsync(Path.Combine(_testDir, ".gitignore"), "*.log\nnode_modules/\n");
        await Add.AddFiles(_testDir, new[] { ".gitignore", "test.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "test.txt"), "modified content");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "debug.log"), "log data");
        Directory.CreateDirectory(Path.Combine(_testDir, "node_modules", "pkg"));
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "node_modules", "pkg", "index.js"),
            "module"
        );

        await Stash.CreateStash(_testDir, "WIP");

        var afterStashContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "test.txt"));
        Assert.AreEqual("initial content", afterStashContent);

        Assert.IsTrue(File.Exists(Path.Combine(_testDir, "debug.log")));
        Assert.IsTrue(File.Exists(Path.Combine(_testDir, "node_modules", "pkg", "index.js")));

        var logContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "debug.log"));
        Assert.AreEqual("log data", logContent);
    }

    [TestMethod]
    public async Task ShouldStashMultipleFilesAndPreserveIgnored()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "tracked.txt"), "tracked content");
        await File.WriteAllTextAsync(Path.Combine(_testDir, ".gitignore"), "*.log\nbuild/\n");
        await Add.AddFiles(_testDir, new[] { ".gitignore", "tracked.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "tracked.txt"), "modified");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "new.txt"), "new file");
        Directory.CreateDirectory(Path.Combine(_testDir, "build"));
        await File.WriteAllTextAsync(Path.Combine(_testDir, "build", "output.js"), "compiled");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "error.log"), "errors");

        await Stash.CreateStash(_testDir, "WIP");

        Assert.IsTrue(File.Exists(Path.Combine(_testDir, "build", "output.js")));
        Assert.IsTrue(File.Exists(Path.Combine(_testDir, "error.log")));

        var buildContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "build", "output.js"));
        Assert.AreEqual("compiled", buildContent);
    }

    [TestMethod]
    public async Task ShouldMergeStashedChangesWithChangesToHEADAfterStash()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file.txt"),
            "line1\nline2\nline3\nline4\nline5"
        );
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file.txt"),
            "line1\nline2-modified\nline3\nline4\nline5"
        );

        await Stash.CreateStash(_testDir, "WIP");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file.txt"),
            "line1\nline2\nline3\nline4-pulled\nline5"
        );
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Pulled changes");

        await Stash.Unstash(_testDir);

        var content = await File.ReadAllTextAsync(Path.Combine(_testDir, "file.txt"));
        Assert.AreEqual("line1\nline2-modified\nline3\nline4-pulled\nline5", content);
    }

    [TestMethod]
    public async Task ShouldDetectConflictsWhenBothStashAndHEADModifySameLines()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file.txt"), "line1\nline2\nline3");
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file.txt"),
            "line1\nline2-local\nline3"
        );

        await Stash.CreateStash(_testDir, "WIP");

        await File.WriteAllTextAsync(
            Path.Combine(_testDir, "file.txt"),
            "line1\nline2-remote\nline3"
        );
        await Add.AddFiles(_testDir, new[] { "file.txt" });
        await Commit.CreateCommit(_testDir, "Remote changes");

        await Stash.Unstash(_testDir);

        var content = await File.ReadAllTextAsync(Path.Combine(_testDir, "file.txt"));
        Assert.IsTrue(content.Contains("<<<<<<< Updated upstream"));
        Assert.IsTrue(content.Contains("line2-remote"));
        Assert.IsTrue(content.Contains("======="));
        Assert.IsTrue(content.Contains("line2-local"));
        Assert.IsTrue(content.Contains(">>>>>>> Stashed changes"));
    }

    [TestMethod]
    public async Task ShouldKeepHEADChangesWhenStashDidNotModifyAFile()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "a-original");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "b.txt"), "b-original");
        await Add.AddFiles(_testDir, new[] { "a.txt", "b.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "a-local");

        await Stash.CreateStash(_testDir, "WIP");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "b.txt"), "b-remote");
        await Add.AddFiles(_testDir, new[] { "b.txt" });
        await Commit.CreateCommit(_testDir, "Remote changes");

        await Stash.Unstash(_testDir);

        var aContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "a.txt"));
        Assert.AreEqual("a-local", aContent);

        var bContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "b.txt"));
        Assert.AreEqual("b-remote", bContent);
    }

    [TestMethod]
    public async Task ShouldRestoreMultipleStashedFiles()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file1.txt"), "content1");
        await Add.AddFiles(_testDir, new[] { "file1.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "file1.txt"), "modified1");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "file2.txt"), "content2");

        await Stash.CreateStash(_testDir, "Multiple files");

        var afterStashContent1 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file1.txt"));
        Assert.AreEqual("content1", afterStashContent1);
        var existsAfterStash = File.Exists(Path.Combine(_testDir, "file2.txt"));
        Assert.IsFalse(existsAfterStash);

        await Stash.Unstash(_testDir);

        var afterUnstashContent1 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file1.txt"));
        Assert.AreEqual("modified1", afterUnstashContent1);
        var existsAfterUnstash = File.Exists(Path.Combine(_testDir, "file2.txt"));
        Assert.IsTrue(existsAfterUnstash);
        var afterUnstashContent2 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file2.txt"));
        Assert.AreEqual("content2", afterUnstashContent2);

        var statusResult = await Status.GetStatus(_testDir);
        Assert.IsTrue(statusResult.Modified.Contains("file1.txt"));
        Assert.IsTrue(statusResult.Untracked.Contains("file2.txt"));
    }

    [TestMethod]
    public async Task ShouldDeleteFilesThatExistInHEADButNotInStashWhenHEADHasNotMoved()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "a-original");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "b.txt"), "b-original");
        await Add.AddFiles(_testDir, new[] { "a.txt", "b.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "a-local");
        File.Delete(Path.Combine(_testDir, "b.txt"));

        await Stash.CreateStash(_testDir, "WIP");

        await Stash.Unstash(_testDir);

        Assert.IsTrue(File.Exists(Path.Combine(_testDir, "a.txt")));
        Assert.IsFalse(File.Exists(Path.Combine(_testDir, "b.txt")));

        var aContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "a.txt"));
        Assert.AreEqual("a-local", aContent);
    }

    [TestMethod]
    public async Task ShouldDeleteFilesThatWereDeletedInStashAndNotModifiedInCurrentHEAD()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "a-original");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "b.txt"), "b-original");
        await Add.AddFiles(_testDir, new[] { "a.txt", "b.txt" });
        await Commit.CreateCommit(_testDir, "Initial commit");

        File.Delete(Path.Combine(_testDir, "b.txt"));

        await Stash.CreateStash(_testDir, "Delete b");

        await File.WriteAllTextAsync(Path.Combine(_testDir, "a.txt"), "a-remote");
        await Add.AddFiles(_testDir, new[] { "a.txt" });
        await Commit.CreateCommit(_testDir, "Remote changes");

        await Stash.Unstash(_testDir);

        Assert.IsTrue(File.Exists(Path.Combine(_testDir, "a.txt")));
        Assert.IsFalse(File.Exists(Path.Combine(_testDir, "b.txt")));

        var aContent = await File.ReadAllTextAsync(Path.Combine(_testDir, "a.txt"));
        Assert.AreEqual("a-remote", aContent);
    }

    [TestMethod]
    public async Task ShouldNotRestoreFileDeletedOnRemoteAfterStashPullUnstash()
    {
        await Init.InitRepo(_testDir);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "fileA.txt"), "a");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "fileB.txt"), "b");
        await Add.AddFiles(_testDir, new[] { "fileA.txt", "fileB.txt" });
        var firstSha = await Commit.CreateCommit(_testDir, "Initial commit");

        await Push.PushToRemote(_testDir);

        // Delete fileB on the remote and push.
        File.Delete(Path.Combine(_testDir, "fileB.txt"));
        await Add.AddAll(_testDir);
        await Commit.CreateCommit(_testDir, "Delete fileB");
        await Push.PushToRemote(_testDir);

        // Simulate a second clone at the first commit with an uncommitted
        // local edit to fileA, then refresh like RefreshManager does:
        // stash -> pull -> unstash.
        var localBranchPath = Path.Combine(_testDir, ".git", "refs", "heads", "main");
        await File.WriteAllTextAsync(localBranchPath, firstSha);
        await File.WriteAllTextAsync(Path.Combine(_testDir, "fileA.txt"), "a");
        await File.WriteAllTextAsync(Path.Combine(_testDir, "fileB.txt"), "b");
        await Add.AddFiles(_testDir, new[] { "fileA.txt", "fileB.txt" });
        await File.WriteAllTextAsync(Path.Combine(_testDir, "fileA.txt"), "a-modified");

        await Stash.CreateStash(_testDir, "WIP");
        await Pull.PullFromRemote(_testDir);
        await Stash.Unstash(_testDir);

        // fileA's local edit must be restored...
        var contentA = await File.ReadAllTextAsync(Path.Combine(_testDir, "fileA.txt"));
        Assert.AreEqual("a-modified", contentA);

        // ...but fileB was deleted on the remote and must NOT come back.
        Assert.IsFalse(File.Exists(Path.Combine(_testDir, "fileB.txt")));
    }
}
