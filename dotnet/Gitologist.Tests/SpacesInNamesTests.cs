using Gitologist.Types;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class SpacesInNamesTests
{
	private string _testDir = null!;

	[TestInitialize]
	public void SetupTestDir()
	{
		_testDir = Path.Combine(
			Path.GetTempPath(),
			$"gitologist-spaces-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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

	// MARK: - Add Tests

	[TestMethod]
	public async Task ShouldAddFileWithSingleSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content");

		await Add.AddFiles(_testDir, new[] { "test file.txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	[TestMethod]
	public async Task ShouldAddFileWithMultipleSpacesInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test  multiple  spaces.txt"), "content");

		await Add.AddFiles(_testDir, new[] { "test  multiple  spaces.txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	[TestMethod]
	public async Task ShouldAddFileWithTrailingSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "trailing .txt"), "content");

		await Add.AddFiles(_testDir, new[] { "trailing .txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	[TestMethod]
	public async Task ShouldAddFilesInFolderWithSpaceInName()
	{
		await Init.InitRepo(_testDir);
		var myFolder = Path.Combine(_testDir, "my folder");
		Directory.CreateDirectory(myFolder);
		await File.WriteAllTextAsync(Path.Combine(myFolder, "file.txt"), "content");

		await Add.AddFiles(_testDir, new[] { "my folder/file.txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	[TestMethod]
	public async Task ShouldAddFilesInFolderWithMultipleSpacesInName()
	{
		await Init.InitRepo(_testDir);
		var myFolder = Path.Combine(_testDir, "my  test  folder");
		Directory.CreateDirectory(myFolder);
		await File.WriteAllTextAsync(Path.Combine(myFolder, "file.txt"), "content");

		await Add.AddFiles(_testDir, new[] { "my  test  folder/file.txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	[TestMethod]
	public async Task ShouldAddFileWithSpaceInNameInFolderWithSpace()
	{
		await Init.InitRepo(_testDir);
		var myFolder = Path.Combine(_testDir, "my folder");
		Directory.CreateDirectory(myFolder);
		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.txt"), "content");

		await Add.AddFiles(_testDir, new[] { "my folder/test file.txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	[TestMethod]
	public async Task ShouldAddMultipleFilesWithSpacesInNames()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "content1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "content2");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file three.txt"), "content3");

		await Add.AddFiles(_testDir, new[] { "file one.txt", "file two.txt", "file three.txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	[TestMethod]
	public async Task ShouldUpdateModifiedFileWithSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "original");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "modified");

		await Add.AddFiles(_testDir, new[] { "test file.txt" });

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Modified.Length);
	}

	[TestMethod]
	public async Task ShouldAddAllFilesWithSpacesUsingAddAll()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "content1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "content2");

		var myFolder = Path.Combine(_testDir, "my folder");
		Directory.CreateDirectory(myFolder);
		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.ts"), "console.log('hello')");

		await Add.AddAll(_testDir);

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
	}

	// MARK: - Commit Tests

	[TestMethod]
	public async Task ShouldCommitFileWithSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });

		var commitSha = await Commit.CreateCommit(_testDir, "Add file with space");

		Assert.AreEqual(40, commitSha.Length);

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
		Assert.AreEqual(0, result.Modified.Length);
	}

	[TestMethod]
	public async Task ShouldCommitMultipleFilesWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "content1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "content2");

		await Add.AddFiles(_testDir, new[] { "file one.txt", "file two.txt" });

		var commitSha = await Commit.CreateCommit(_testDir, "Add multiple files with spaces");

		Assert.AreEqual(40, commitSha.Length);

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
		Assert.AreEqual(0, result.Modified.Length);
	}

	[TestMethod]
	public async Task ShouldCommitFilesInFolderWithSpace()
	{
		await Init.InitRepo(_testDir);
		var myFolder = Path.Combine(_testDir, "my folder");
		Directory.CreateDirectory(myFolder);
		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.txt"), "content");

		await Add.AddFiles(_testDir, new[] { "my folder/test file.txt" });

		var commitSha = await Commit.CreateCommit(_testDir, "Add file in folder with space");

		Assert.AreEqual(40, commitSha.Length);

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
		Assert.AreEqual(0, result.Modified.Length);
	}

	[TestMethod]
	public async Task ShouldHandleMultipleCommitsWithFilesWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });

		var firstSha = await Commit.CreateCommit(_testDir, "First commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "modified");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });

		var secondSha = await Commit.CreateCommit(_testDir, "Second commit");

		Assert.AreNotEqual(firstSha, secondSha);

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Modified.Length);
	}

	// MARK: - Status Tests

	[TestMethod]
	public async Task ShouldDetectUntrackedFileWithSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content");

		var result = await Status.GetStatus(_testDir);
		CollectionAssert.Contains(result.Untracked, "test file.txt");
	}

	[TestMethod]
	public async Task ShouldDetectMultipleUntrackedFilesWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "content1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "content2");

		var myFolder = Path.Combine(_testDir, "my folder");
		Directory.CreateDirectory(myFolder);
		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.ts"), "console.log('hello')");

		var result = await Status.GetStatus(_testDir);
		CollectionAssert.Contains(result.Untracked, "file one.txt");
		CollectionAssert.Contains(result.Untracked, "file two.txt");
		CollectionAssert.Contains(result.Untracked, "my folder/test file.ts");
	}

	[TestMethod]
	public async Task ShouldDetectModifiedFileWithSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "original");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "modified");

		var result = await Status.GetStatus(_testDir);
		CollectionAssert.Contains(result.Modified, "test file.txt");
	}

	[TestMethod]
	public async Task ShouldDetectDeletedFileWithSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "Add file");

		File.Delete(Path.Combine(_testDir, "test file.txt"));

		var result = await Status.GetStatus(_testDir);
		CollectionAssert.Contains(result.Deleted, "test file.txt");
	}

	// MARK: - Restore Tests

	[TestMethod]
	public async Task ShouldRestoreModifiedFileWithSpaceInName()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "original");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "Initial commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "modified");

		await Restore.RestoreFiles(_testDir, new[] { "test file.txt" });

		var content = await File.ReadAllTextAsync(Path.Combine(_testDir, "test file.txt"));
		Assert.AreEqual("original", content);
	}

	[TestMethod]
	public async Task ShouldRestoreMultipleFilesWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "original1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "original2");

		await Add.AddFiles(_testDir, new[] { "file one.txt", "file two.txt" });
		await Commit.CreateCommit(_testDir, "Initial commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "modified1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "modified2");

		await Restore.RestoreFiles(_testDir, new[] { "file one.txt", "file two.txt" });

		var content1 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file one.txt"));
		var content2 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file two.txt"));
		Assert.AreEqual("original1", content1);
		Assert.AreEqual("original2", content2);
	}

	[TestMethod]
	public async Task ShouldRestoreFileInFolderWithSpace()
	{
		await Init.InitRepo(_testDir);
		var myFolder = Path.Combine(_testDir, "my folder");
		Directory.CreateDirectory(myFolder);
		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.txt"), "original");

		await Add.AddFiles(_testDir, new[] { "my folder/test file.txt" });
		await Commit.CreateCommit(_testDir, "Initial commit");

		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.txt"), "modified");

		await Restore.RestoreFiles(_testDir, new[] { "my folder/test file.txt" });

		var content = await File.ReadAllTextAsync(Path.Combine(myFolder, "test file.txt"));
		Assert.AreEqual("original", content);
	}

	[TestMethod]
	public async Task ShouldRestoreAllModifiedFilesWithSpacesUsingRestoreAll()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "original1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "original2");

		await Add.AddFiles(_testDir, new[] { "file one.txt", "file two.txt" });
		await Commit.CreateCommit(_testDir, "Initial commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "modified1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "modified2");

		await Restore.RestoreAll(_testDir);

		var content1 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file one.txt"));
		var content2 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file two.txt"));
		Assert.AreEqual("original1", content1);
		Assert.AreEqual("original2", content2);
	}

	// MARK: - Log Tests

	[TestMethod]
	public async Task ShouldLogCommitsForFilesWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "Add file with space");

		var result = await Log.GetLog(_testDir);

		Assert.AreEqual(1, result.Count);
		Assert.AreEqual("Add file with space", result[0].Message);
	}

	[TestMethod]
	public async Task ShouldLogMultipleCommitsWithFilesWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content1");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "First commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content2");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "Second commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content3");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "Third commit");

		var result = await Log.GetLog(_testDir);

		Assert.AreEqual(3, result.Count);
		Assert.AreEqual("Third commit", result[0].Message);
		Assert.AreEqual("Second commit", result[1].Message);
		Assert.AreEqual("First commit", result[2].Message);
	}

	[TestMethod]
	public async Task ShouldLimitCommitsForFilesWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content1");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "First commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content2");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "Second commit");

		await File.WriteAllTextAsync(Path.Combine(_testDir, "test file.txt"), "content3");
		await Add.AddFiles(_testDir, new[] { "test file.txt" });
		await Commit.CreateCommit(_testDir, "Third commit");

		var result = await Log.GetLog(_testDir, new LogOptions { Limit = 2 });

		Assert.AreEqual(2, result.Count);
		Assert.AreEqual("Third commit", result[0].Message);
		Assert.AreEqual("Second commit", result[1].Message);
	}

	// MARK: - Remote Tests

	[TestMethod]
	public async Task ShouldAddRemoteWithSpaceInURLPath()
	{
		await Init.InitRepo(_testDir);

		await Remote.AddRemote(_testDir, "origin", "https://example.com/path with spaces/repo.git");

		var configPath = Path.Combine(_testDir, ".git", "config");
		var configContent = await File.ReadAllTextAsync(configPath);

		StringAssert.Contains(configContent, "https://example.com/path with spaces/repo.git");
	}

	// MARK: - Complex Scenarios

	[TestMethod]
	public async Task ShouldHandleCompleteWorkflowWithFilesAndFoldersWithSpaces()
	{
		await Init.InitRepo(_testDir);
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "content1");
		await File.WriteAllTextAsync(Path.Combine(_testDir, "file two.txt"), "content2");

		var myFolder = Path.Combine(_testDir, "my folder");
		Directory.CreateDirectory(myFolder);

		var anotherFolder = Path.Combine(_testDir, "another  folder");
		Directory.CreateDirectory(anotherFolder);

		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.ts"), "console.log('hello')");
		await File.WriteAllTextAsync(Path.Combine(anotherFolder, "data  file.json"), "{\"key\": \"value\"}");

		await Add.AddAll(_testDir);

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);

		await Commit.CreateCommit(_testDir, "Initial commit with spaced files");

		result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Modified.Length);

		await File.WriteAllTextAsync(Path.Combine(_testDir, "file one.txt"), "modified1");
		await File.WriteAllTextAsync(Path.Combine(myFolder, "test file.ts"), "console.log('modified')");

		result = await Status.GetStatus(_testDir);
		CollectionAssert.Contains(result.Modified, "file one.txt");
		CollectionAssert.Contains(result.Modified, "my folder/test file.ts");

		await Restore.RestoreFiles(_testDir, new[] { "file one.txt" });

		var content1 = await File.ReadAllTextAsync(Path.Combine(_testDir, "file one.txt"));
		Assert.AreEqual("content1", content1);

		var logResult = await Log.GetLog(_testDir);
		Assert.AreEqual(1, logResult.Count);
		Assert.AreEqual("Initial commit with spaced files", logResult[0].Message);
	}

	[TestMethod]
	public async Task ShouldHandleFilesWithVariousSpacePatterns()
	{
		await Init.InitRepo(_testDir);
		var files = new[]
		{
			"single space.txt",
			"double  space.txt",
			"triple   space.txt",
			"trailing .txt",
		};

		foreach (var file in files)
		{
			await File.WriteAllTextAsync(Path.Combine(_testDir, file), "content");
		}

		await Add.AddAll(_testDir);
		await Commit.CreateCommit(_testDir, "Add files with various space patterns");

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);
		Assert.AreEqual(0, result.Modified.Length);

		var logResult = await Log.GetLog(_testDir);
		Assert.AreEqual(1, logResult.Count);
	}

	[TestMethod]
	public async Task ShouldHandleNestedFoldersWithSpaces()
	{
		await Init.InitRepo(_testDir);
		var folderOne = Path.Combine(_testDir, "folder one");
		Directory.CreateDirectory(folderOne);

		var folderTwo = Path.Combine(folderOne, "folder two");
		Directory.CreateDirectory(folderTwo);

		var folderThree = Path.Combine(folderTwo, "folder three");
		Directory.CreateDirectory(folderThree);

		await File.WriteAllTextAsync(Path.Combine(folderOne, "file1.txt"), "content1");
		await File.WriteAllTextAsync(Path.Combine(folderTwo, "file2.txt"), "content2");
		await File.WriteAllTextAsync(Path.Combine(folderThree, "file3.txt"), "content3");

		await Add.AddAll(_testDir);
		await Commit.CreateCommit(_testDir, "Add nested folders with spaces");

		var result = await Status.GetStatus(_testDir);
		Assert.AreEqual(0, result.Untracked.Length);

		var logResult = await Log.GetLog(_testDir);
		Assert.AreEqual(1, logResult.Count);
	}
}
