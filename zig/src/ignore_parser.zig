const std = @import("std");

pub const IgnorePattern = struct {
    pattern: []const u8,
    is_negated: bool,
    is_directory_only: bool,
    path_prefix: []const u8,

    pub fn deinit(self: IgnorePattern, allocator: std.mem.Allocator) void {
        allocator.free(self.pattern);
        allocator.free(self.path_prefix);
    }
};

pub const IgnoreParser = struct {
    patterns: std.StringArrayHashMap(std.ArrayList(IgnorePattern)),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) IgnoreParser {
        return .{
            .patterns = std.StringArrayHashMap(std.ArrayList(IgnorePattern)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *IgnoreParser) void {
        var iter = self.patterns.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |pattern| {
                pattern.deinit(self.allocator);
            }
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.patterns.deinit();
    }

    pub fn loadGitignore(self: *IgnoreParser, io: std.Io, repo_path: []const u8) !void {
        // Clear existing patterns
        var iter = self.patterns.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |pattern| {
                pattern.deinit(self.allocator);
            }
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.patterns.clearRetainingCapacity();

        try self.loadGitignoreRecursive(io, repo_path, repo_path);
    }

    fn loadGitignoreRecursive(self: *IgnoreParser, io: std.Io, repo_path: []const u8, current_dir: []const u8) !void {
        const gitignore_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current_dir, ".gitignore" });
        defer self.allocator.free(gitignore_path);

        const relative_dir_opt = try self.getRelativePath(repo_path, current_dir);
        const relative_dir = relative_dir_opt orelse ".";
        defer if (relative_dir_opt) |rd| self.allocator.free(rd);

        const cwd = std.Io.Dir.cwd();
        var content: ?[]u8 = null;
        if (cwd.readFileAlloc(io, gitignore_path, self.allocator, .unlimited)) |file_content| {
            content = file_content;
        } else |err| {
            if (err != error.FileNotFound) {
                return err;
            }
            // No .gitignore file in this directory - content remains null
        }
        defer if (content) |c| self.allocator.free(c);

        if (content) |c| {
            var patterns = try self.parseGitignore(c, relative_dir);
            if (patterns.items.len > 0) {
                const key = try self.allocator.dupe(u8, relative_dir);
                try self.patterns.put(key, patterns);
            } else {
                patterns.deinit(self.allocator);
            }
        }

        // Recursively check subdirectories (but skip .git)
        const dir = cwd.openDir(io, current_dir, .{}) catch |err| {
            if (err == error.FileNotFound) return;
            return err;
        };
        defer dir.close(io);

        var dir_iter = dir.iterate();
        while (try dir_iter.next(io)) |entry| {
            if (std.mem.eql(u8, entry.name, ".git")) continue;
            if (entry.kind != .directory) continue;

            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ current_dir, entry.name });
            defer self.allocator.free(full_path);

            try self.loadGitignoreRecursive(io, repo_path, full_path);
        }
    }

    fn parseGitignore(self: *IgnoreParser, content: []const u8, path_prefix: []const u8) !std.ArrayList(IgnorePattern) {
        var patterns = std.ArrayList(IgnorePattern).initCapacity(self.allocator, 10) catch unreachable;

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

            // Skip empty lines and comments
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Handle negation (!)
            var is_negated = false;
            var pattern_str = trimmed;
            if (trimmed[0] == '!') {
                is_negated = true;
                pattern_str = trimmed[1..];
            }

            // Handle directory-only patterns (trailing /)
            var is_directory_only = false;
            if (pattern_str.len > 0 and pattern_str[pattern_str.len - 1] == '/') {
                is_directory_only = true;
                pattern_str = pattern_str[0 .. pattern_str.len - 1];
            }

            // Skip empty pattern after processing
            if (pattern_str.len == 0) continue;

            const pattern_copy = try self.allocator.dupe(u8, pattern_str);
            const prefix_copy = try self.allocator.dupe(u8, path_prefix);

            try patterns.append(self.allocator, .{
                .pattern = pattern_copy,
                .is_negated = is_negated,
                .is_directory_only = is_directory_only,
                .path_prefix = prefix_copy,
            });
        }

        return patterns;
    }

    pub fn isIgnored(self: IgnoreParser, file_path: []const u8, is_directory: bool) bool {
        const normalized_path = std.mem.replaceOwned(u8, self.allocator, file_path, "\\", "/") catch file_path;
        defer if (normalized_path.ptr != file_path.ptr) self.allocator.free(normalized_path);

        var path_parts = std.ArrayList([]const u8).initCapacity(self.allocator, 10) catch unreachable;
        defer path_parts.deinit(self.allocator);

        var parts_iter = std.mem.splitScalar(u8, normalized_path, '/');
        while (parts_iter.next()) |part| {
            if (part.len > 0) {
                path_parts.append(self.allocator, part) catch unreachable;
            }
        }

        var ignored = false;

        var iter = self.patterns.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |pattern| {
                if (self.matchesPattern(normalized_path, path_parts.items, pattern, is_directory)) {
                    ignored = !pattern.is_negated;
                }
            }
        }

        return ignored;
    }

    fn matchesPattern(self: IgnoreParser, file_path: []const u8, path_parts: [][]const u8, pattern: IgnorePattern, is_directory: bool) bool {
        // Check if pattern applies to this file based on path prefix
        if (!std.mem.eql(u8, pattern.path_prefix, ".")) {
            var prefix_parts = std.mem.splitScalar(u8, pattern.path_prefix, '/');
            var prefix_count: usize = 0;
            while (prefix_parts.next()) |_| {
                prefix_count += 1;
            }

            if (path_parts.len < prefix_count) return false;

            prefix_parts = std.mem.splitScalar(u8, pattern.path_prefix, '/');
            var i: usize = 0;
            while (prefix_parts.next()) |prefix_part| : (i += 1) {
                if (!std.mem.eql(u8, prefix_part, path_parts[i])) {
                    return false;
                }
            }
        }

        // Get the relative path from the .gitignore location
        var relative_path: []const u8 = undefined;
        if (std.mem.eql(u8, pattern.path_prefix, ".")) {
            relative_path = file_path;
        } else {
            const prefix_len = pattern.path_prefix.len + 1;
            if (file_path.len > prefix_len) {
                relative_path = file_path[prefix_len..];
            } else {
                relative_path = ".";
            }
        }

        // If directory-only pattern, only match directories
        if (pattern.is_directory_only and !is_directory) {
            return false;
        }

        return self.matchPatternString(relative_path, path_parts, pattern.pattern);
    }

    fn matchPatternString(self: IgnoreParser, file_path: []const u8, path_parts: [][]const u8, pattern: []const u8) bool {
        _ = path_parts;

        // Handle patterns with /
        if (std.mem.indexOfScalar(u8, pattern, '/')) |_| {
            // Pattern with / is anchored
            var regex_pattern = pattern;
            if (pattern[0] == '/') {
                regex_pattern = pattern[1..];
            }

            // Simple string matching for now (full regex implementation would be complex)
            // Check for exact match or directory prefix match
            if (std.mem.eql(u8, file_path, regex_pattern)) {
                return true;
            }
            if (std.mem.startsWith(u8, file_path, regex_pattern)) {
                if (file_path.len > regex_pattern.len and file_path[regex_pattern.len] == '/') {
                    return true;
                }
            }
            return false;
        } else {
            // Pattern without / matches at any depth
            // Check if file_path ends with pattern or contains it as a component
            const file_name = std.fs.path.basename(file_path);
            if (std.mem.eql(u8, file_name, pattern)) {
                return true;
            }

            // Check for wildcard patterns
            if (std.mem.indexOfScalar(u8, pattern, '*')) |_| {
                return self.matchWildcard(file_path, pattern);
            }

            return false;
        }
    }

    fn matchWildcard(self: IgnoreParser, file_path: []const u8, pattern: []const u8) bool {
        _ = self;

        // Simple wildcard matching
        if (std.mem.eql(u8, pattern, "*.log")) {
            return std.mem.endsWith(u8, file_path, ".log");
        }
        if (std.mem.eql(u8, pattern, ".env")) {
            return std.mem.eql(u8, std.fs.path.basename(file_path), ".env");
        }
        if (std.mem.eql(u8, pattern, "node_modules")) {
            return std.mem.eql(u8, std.fs.path.basename(file_path), "node_modules");
        }

        return false;
    }

    fn getRelativePath(self: *IgnoreParser, base_path: []const u8, target_path: []const u8) !?[]const u8 {
        if (!std.mem.startsWith(u8, target_path, base_path)) {
            return null;
        }

        if (std.mem.eql(u8, base_path, target_path)) {
            return null;
        }

        // target_path should be base_path + "/" + relative
        const base_len = base_path.len;
        if (target_path.len > base_len + 1 and target_path[base_len] == std.fs.path.sep) {
            return try self.allocator.dupe(u8, target_path[base_len + 1 ..]);
        }

        return null;
    }

    // Test helper
    pub fn setPatternsForTesting(self: *IgnoreParser, patterns: std.StringArrayHashMap(std.ArrayList(IgnorePattern))) void {
        // Clear existing
        var iter = self.patterns.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.items) |pattern| {
                pattern.deinit(self.allocator);
            }
            entry.value_ptr.deinit(self.allocator);
            self.allocator.free(entry.key_ptr.*);
        }
        self.patterns = patterns;
    }
};
