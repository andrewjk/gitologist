namespace Gitologist;

public class IgnorePattern
{
    public string Pattern { get; set; } = string.Empty;
    public bool IsNegated { get; set; }
    public bool IsDirectoryOnly { get; set; }
    public string PathPrefix { get; set; } = string.Empty;
}

public class IgnoreParser
{
    private Dictionary<string, List<IgnorePattern>> _patterns = new();

    public async Task LoadGitignore(string repoPath)
    {
        _patterns.Clear();
        await LoadGitignoreRecursive(repoPath, repoPath);
    }

    private async Task LoadGitignoreRecursive(string repoPath, string currentDir)
    {
        var gitignorePath = Path.Combine(currentDir, ".gitignore");
        var relativeDir = GetRelativePath(repoPath, currentDir) ?? ".";

        try
        {
            var content = await File.ReadAllTextAsync(gitignorePath);
            var patterns = ParseGitignore(content, relativeDir);
            if (patterns.Count > 0)
            {
                _patterns[relativeDir] = patterns;
            }
        }
        catch
        {
            // No .gitignore file in this directory
        }

        // Recursively check subdirectories (but skip .git)
        try
        {
            var entries = Directory.GetFileSystemEntries(currentDir);
            foreach (var entry in entries)
            {
                var entryName = Path.GetFileName(entry);
                if (entryName == ".git") continue;

                if (Directory.Exists(entry))
                {
                    await LoadGitignoreRecursive(repoPath, entry);
                }
            }
        }
        catch
        {
            // Skip if can't read directory
        }
    }

    private List<IgnorePattern> ParseGitignore(string content, string pathPrefix)
    {
        var patterns = new List<IgnorePattern>();
        var lines = content.Split('\n');

        foreach (var line in lines)
        {
            var trimmedLine = line.Trim();

            // Skip empty lines and comments
            if (string.IsNullOrEmpty(trimmedLine) || trimmedLine.StartsWith("#"))
                continue;

            // Handle negation (!)
            var isNegated = trimmedLine.StartsWith("!");
            if (isNegated)
            {
                trimmedLine = trimmedLine.Substring(1);
            }

            // Handle directory-only patterns (trailing /)
            var isDirectoryOnly = trimmedLine.EndsWith("/");
            if (isDirectoryOnly)
            {
                trimmedLine = trimmedLine.Substring(0, trimmedLine.Length - 1);
            }

            // Skip empty pattern after processing
            if (string.IsNullOrEmpty(trimmedLine))
                continue;

            patterns.Add(new IgnorePattern
            {
                Pattern = trimmedLine,
                IsNegated = isNegated,
                IsDirectoryOnly = isDirectoryOnly,
                PathPrefix = pathPrefix
            });
        }

        return patterns;
    }

    public bool IsIgnored(string filePath, bool isDirectory = false)
    {
        var normalizedPath = filePath.Replace("\\", "/");
        var pathParts = normalizedPath.Split('/');

        var ignored = false;

        foreach (var patternList in _patterns.Values)
        {
            foreach (var pattern in patternList)
            {
                if (MatchesPattern(normalizedPath, pathParts, pattern, isDirectory))
                {
                    ignored = !pattern.IsNegated;
                }
            }
        }

        return ignored;
    }

    private bool MatchesPattern(string filePath, string[] pathParts, IgnorePattern pattern, bool isDirectory)
    {
        // Check if pattern applies to this file based on path prefix
        if (pattern.PathPrefix != ".")
        {
            var prefixParts = pattern.PathPrefix.Split('/');
            if (pathParts.Length < prefixParts.Length)
                return false;

            for (int i = 0; i < prefixParts.Length; i++)
            {
                if (prefixParts[i] != pathParts[i])
                    return false;
            }
        }

        // Get the relative path from the .gitignore location
        string relativePath;
        if (pattern.PathPrefix == ".")
        {
            relativePath = filePath;
        }
        else
        {
            relativePath = filePath.Substring(pattern.PathPrefix.Length + 1);
        }

        // If directory-only pattern, only match directories
        if (pattern.IsDirectoryOnly && !isDirectory)
        {
            return false;
        }

        return MatchPatternString(relativePath, pathParts, pattern.Pattern);
    }

    private bool MatchPatternString(string filePath, string[] pathParts, string pattern)
    {
        // Handle patterns with /
        if (pattern.Contains('/'))
        {
            // Pattern with / is anchored
            var regexPattern = pattern;
            if (pattern.StartsWith("/"))
            {
                regexPattern = pattern.Substring(1);
            }

            // Handle ** (matches zero or more directories)
            regexPattern = regexPattern.Replace("**", "<<<DOUBLESTAR>>>");

            // Handle * (matches anything except /)
            regexPattern = regexPattern.Replace("*", "[^/]*");

            // Handle ? (matches single character except /)
            regexPattern = regexPattern.Replace("?", "[^/]");

            // Restore ** as .*
            regexPattern = regexPattern.Replace("<<<DOUBLESTAR>>>", ".*");

            // Escape other regex special characters
            regexPattern = EscapeRegexExcept(regexPattern, "[^/].*$+()|");

            // Match pattern
            var regex = new System.Text.RegularExpressions.Regex($"^{regexPattern}(/.*)?$");
            return regex.IsMatch(filePath);
        }
        else
        {
            // Pattern without / matches at any depth
            var escapedPattern = EscapeRegex(pattern).Replace("\\*\\*", ".*");
            escapedPattern = escapedPattern.Replace("\\*", "[^/]*");
            escapedPattern = escapedPattern.Replace("\\?", ".");

            var regex = new System.Text.RegularExpressions.Regex($"(^|/){escapedPattern}$");
            return regex.IsMatch(filePath);
        }
    }

    private string EscapeRegex(string str)
    {
        var result = "";
        var specialChars = ".*+?^${}()|[]\\";
        foreach (var c in str)
        {
            if (specialChars.Contains(c))
            {
                result += "\\" + c;
            }
            else
            {
                result += c;
            }
        }
        return result;
    }

    private string EscapeRegexExcept(string str, string except)
    {
        var exceptSet = new HashSet<char>(except);
        var result = "";
        var specialChars = ".*+?^${}()|[]\\";
        foreach (var c in str)
        {
            if (specialChars.Contains(c) && !exceptSet.Contains(c))
            {
                result += "\\" + c;
            }
            else
            {
                result += c;
            }
        }
        return result;
    }

    private string? GetRelativePath(string basePath, string targetPath)
    {
        if (!targetPath.StartsWith(basePath))
        {
            return ".";
        }

        var baseUri = new Uri(basePath.EndsWith(Path.DirectorySeparatorChar.ToString()) ? basePath : basePath + Path.DirectorySeparatorChar);
        var targetUri = new Uri(targetPath.EndsWith(Path.DirectorySeparatorChar.ToString()) ? targetPath : targetPath + Path.DirectorySeparatorChar);
        var relativeUri = baseUri.MakeRelativeUri(targetUri);
        var relativePath = Uri.UnescapeDataString(relativeUri.ToString()).Replace('/', Path.DirectorySeparatorChar);

        return string.IsNullOrEmpty(relativePath) ? "." : relativePath.TrimEnd(Path.DirectorySeparatorChar);
    }

    // Test helper
    public void SetPatternsForTesting(Dictionary<string, List<IgnorePattern>> testPatterns)
    {
        _patterns = testPatterns;
    }
}
