using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Gitologist.Tests;

[TestClass]
public class IgnoreParserTests
{
    private string _testDir = null!;

    [TestInitialize]
    public void SetupTestDir()
    {
        _testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitologist-ignore-test-{DateTime.UtcNow.Ticks}-{Guid.NewGuid():N}"
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
    public void ShouldIgnoreSimplePatterns()
    {
        var parser = new IgnoreParser();
        parser.SetPatternsForTesting(new Dictionary<string, List<IgnorePattern>>
        {
            ["."] = new()
            {
                new IgnorePattern { Pattern = "node_modules", IsNegated = false, IsDirectoryOnly = true, PathPrefix = "." },
                new IgnorePattern { Pattern = "*.log", IsNegated = false, IsDirectoryOnly = false, PathPrefix = "." }
            }
        });

        Assert.IsTrue(parser.IsIgnored("node_modules", true));
        Assert.IsTrue(parser.IsIgnored("app.log"));
        Assert.IsFalse(parser.IsIgnored("src/main.ts"));
    }

    [TestMethod]
    public void ShouldHandleNegationPatterns()
    {
        var parser = new IgnoreParser();
        parser.SetPatternsForTesting(new Dictionary<string, List<IgnorePattern>>
        {
            ["."] = new()
            {
                new IgnorePattern { Pattern = "*.log", IsNegated = false, IsDirectoryOnly = false, PathPrefix = "." },
                new IgnorePattern { Pattern = "important.log", IsNegated = true, IsDirectoryOnly = false, PathPrefix = "." }
            }
        });

        Assert.IsTrue(parser.IsIgnored("debug.log"));
        Assert.IsFalse(parser.IsIgnored("important.log"));
    }

    [TestMethod]
    public void ShouldHandleDirectoryOnlyPatterns()
    {
        var parser = new IgnoreParser();
        parser.SetPatternsForTesting(new Dictionary<string, List<IgnorePattern>>
        {
            ["."] = new()
            {
                new IgnorePattern { Pattern = "build", IsNegated = false, IsDirectoryOnly = true, PathPrefix = "." }
            }
        });

        Assert.IsTrue(parser.IsIgnored("build", true));
        Assert.IsFalse(parser.IsIgnored("build", false));
        Assert.IsFalse(parser.IsIgnored("build/output.txt"));
    }

    [TestMethod]
    public async Task ShouldLoadGitignoreFromRepository()
    {
        var testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitignore-test-{DateTime.UtcNow.Ticks}"
        );
        Directory.CreateDirectory(testDir);

        try
        {
            // Create a .gitignore file
            await File.WriteAllTextAsync(
                Path.Combine(testDir, ".gitignore"),
                "node_modules/\n*.log\n.env\n"
            );

            var parser = new IgnoreParser();
            await parser.LoadGitignore(testDir);

            Assert.IsTrue(parser.IsIgnored("node_modules", true));
            Assert.IsTrue(parser.IsIgnored("app.log"));
            Assert.IsTrue(parser.IsIgnored(".env"));
            Assert.IsFalse(parser.IsIgnored("src/main.ts"));
        }
        finally
        {
            try
            {
                Directory.Delete(testDir, true);
            }
            catch
            {
            }
        }
    }

    [TestMethod]
    public async Task ShouldRespectGitignoreInStatusCommand()
    {
        var testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitignore-status-test-{DateTime.UtcNow.Ticks}"
        );
        Directory.CreateDirectory(testDir);

        try
        {
            await Init.InitRepo(testDir);

            // Create files
            await File.WriteAllTextAsync(Path.Combine(testDir, "main.ts"), "console.log('hello');");
            await File.WriteAllTextAsync(Path.Combine(testDir, "debug.log"), "debug info");
            Directory.CreateDirectory(Path.Combine(testDir, "node_modules"));
            await File.WriteAllTextAsync(Path.Combine(testDir, "node_modules", "package.json"), "{}");

            // Create .gitignore
            await File.WriteAllTextAsync(Path.Combine(testDir, ".gitignore"), "node_modules/\n*.log\n");

            var result = await Status.GetStatus(testDir);

            // Should only see main.ts, not debug.log or node_modules/
            CollectionAssert.Contains(result.Untracked, "main.ts");
            CollectionAssert.DoesNotContain(result.Untracked, "debug.log");
            CollectionAssert.DoesNotContain(result.Untracked, "node_modules/package.json");
        }
        finally
        {
            try
            {
                Directory.Delete(testDir, true);
            }
            catch
            {
            }
        }
    }

    [TestMethod]
    public async Task ShouldRespectGitignoreInAddAllCommand()
    {
        var testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitignore-add-test-{DateTime.UtcNow.Ticks}"
        );
        Directory.CreateDirectory(testDir);

        try
        {
            await Init.InitRepo(testDir);

            // Create files
            await File.WriteAllTextAsync(Path.Combine(testDir, "main.ts"), "console.log('hello');");
            await File.WriteAllTextAsync(Path.Combine(testDir, "debug.log"), "debug info");

            // Create .gitignore
            await File.WriteAllTextAsync(Path.Combine(testDir, ".gitignore"), "*.log\n");

            await Add.AddAll(testDir);

            var result = await Status.GetStatus(testDir);

            // Should have staged main.ts but not debug.log
            CollectionAssert.Contains(result.Staged, "main.ts");
            CollectionAssert.DoesNotContain(result.Staged, "debug.log");
        }
        finally
        {
            try
            {
                Directory.Delete(testDir, true);
            }
            catch
            {
            }
        }
    }

    [TestMethod]
    public async Task ShouldRespectGitignoreInAddCommandForSpecificFiles()
    {
        var testDir = Path.Combine(
            Path.GetTempPath(),
            $"gitignore-add-specific-test-{DateTime.UtcNow.Ticks}"
        );
        Directory.CreateDirectory(testDir);

        try
        {
            await Init.InitRepo(testDir);

            // Create files
            await File.WriteAllTextAsync(Path.Combine(testDir, "main.ts"), "console.log('hello');");
            await File.WriteAllTextAsync(Path.Combine(testDir, "debug.log"), "debug info");

            // Create .gitignore
            await File.WriteAllTextAsync(Path.Combine(testDir, ".gitignore"), "*.log\n");

            // Try to add both files
            await Add.AddFiles(testDir, new[] { "main.ts", "debug.log" });

            var result = await Status.GetStatus(testDir);

            // Should have staged main.ts but not debug.log
            CollectionAssert.Contains(result.Staged, "main.ts");
            CollectionAssert.DoesNotContain(result.Staged, "debug.log");
        }
        finally
        {
            try
            {
                Directory.Delete(testDir, true);
            }
            catch
            {
            }
        }
    }
}
