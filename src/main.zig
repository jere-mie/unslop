const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const build_options = @import("build_options");

const version = build_options.version;

const IgnoreRule = struct {
    pattern: []const u8,
    anchored: bool,
    directory_only: bool,
    has_slash: bool,
    negated: bool,
};

const IgnoreMatcher = struct {
    allocator: mem.Allocator,
    rules: std.ArrayList(IgnoreRule),

    fn init(allocator: mem.Allocator) IgnoreMatcher {
        return .{
            .allocator = allocator,
            .rules = .empty,
        };
    }

    fn deinit(self: *IgnoreMatcher) void {
        for (self.rules.items) |rule| {
            self.allocator.free(rule.pattern);
        }
        self.rules.deinit(self.allocator);
    }

    fn loadDefaults(self: *IgnoreMatcher) !void {
        const defaults = [_][]const u8{
            // --- Version Control ---
            ".git/",
            ".hg/",
            ".svn/",
            ".fossil/",

            // --- Zig Specific ---
            "zig-out/",
            "zig-cache/",
            ".zig-cache/",

            // --- JavaScript / Web Ecosystem ---
            "node_modules/",
            "bower_components/",
            "dist/",
            "build/",
            "out/",
            ".next/",
            ".nuxt/",
            ".svelte-kit/",
            "coverage/",
            ".nyc_output/",

            // --- Python Ecosystem ---
            "__pycache__/",
            ".venv/",
            "venv/",
            "env/",
            ".pytest_cache/",
            ".mypy_cache/",

            // --- Compiled Languages (C/C++, Rust, Go) ---
            "target/",      // Rust
            "cmake-build-debug/",
            "cmake-build-release/",
            ".pnpm-store/",

            // --- IDEs & Editors ---
            ".vscode/",
            ".idea/",
            ".vs/",
            "*.swp",       // Vim swap files
            ".DS_Store",   // macOS metadata
            "Thumbs.db",   // Windows thumbnail cache
            
            // --- Misc / Security ---
            ".env",
            ".env.local",
        };

        for (defaults) |pattern| {
            try self.addPatternLine(pattern);
        }
    }

    fn loadGitignore(self: *IgnoreMatcher, cwd: fs.Dir, root_path: []const u8) !void {
        const gitignore_path = try fs.path.join(self.allocator, &.{ root_path, ".gitignore" });
        defer self.allocator.free(gitignore_path);

        const file = cwd.openFile(gitignore_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => {
                var buf: [4096]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "warning: cannot read '{s}': {s}\n", .{ gitignore_path, @errorName(err) }) catch "warning: cannot read .gitignore\n";
                fs.File.stderr().writeAll(msg) catch {};
                return;
            },
        };
        defer file.close();

        const contents = file.readToEndAlloc(self.allocator, 1024 * 1024) catch |err| {
            var buf: [4096]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "warning: cannot read '{s}': {s}\n", .{ gitignore_path, @errorName(err) }) catch "warning: cannot read .gitignore\n";
            fs.File.stderr().writeAll(msg) catch {};
            return;
        };
        defer self.allocator.free(contents);

        var lines = std.mem.splitScalar(u8, contents, '\n');
        var first_line = true;
        while (lines.next()) |line_raw| {
            var line = std.mem.trimRight(u8, line_raw, "\r\t ");
            if (first_line) {
                first_line = false;
                line = std.mem.trimLeft(u8, line, "\xEF\xBB\xBF");
            }
            try self.addPatternLine(line);
        }
    }

    fn addPatternLine(self: *IgnoreMatcher, line_raw: []const u8) !void {
        if (line_raw.len == 0) return;

        var line = line_raw;
        var negated = false;

        if (line[0] == '\\' and line.len > 1 and (line[1] == '#' or line[1] == '!')) {
            line = line[1..];
        } else if (line[0] == '#') {
            return;
        } else if (line[0] == '!') {
            negated = true;
            line = line[1..];
        }

        if (line.len == 0) return;

        var anchored = false;
        if (line[0] == '/') {
            anchored = true;
            line = line[1..];
        }

        var directory_only = false;
        while (line.len > 0 and line[line.len - 1] == '/') {
            directory_only = true;
            line = line[0 .. line.len - 1];
        }

        if (line.len == 0) return;

        const owned_pattern = try self.allocator.dupe(u8, line);
        try self.rules.append(self.allocator, .{
            .pattern = owned_pattern,
            .anchored = anchored,
            .directory_only = directory_only,
            .has_slash = std.mem.indexOfScalar(u8, line, '/') != null,
            .negated = negated,
        });
    }

    fn shouldSkip(self: *const IgnoreMatcher, rel_path: []const u8, is_dir: bool) bool {
        var ignored = false;
        for (self.rules.items) |rule| {
            if (rule.directory_only and !is_dir) continue;
            if (matchesRule(rule, rel_path)) {
                ignored = !rule.negated;
            }
        }
        return ignored;
    }
};

const PendingEntry = struct {
    name: []const u8,
    kind: fs.File.Kind,
};

fn printUsage() void {
    fs.File.stderr().writeAll(
        \\Usage: unslop [options] <path>
        \\
        \\Arguments:
        \\  <path>           File or directory to process
        \\
        \\Options:
        \\  -r, --recursive  Recursively process directories
        \\      --dry-run    Print transformed output to stdout; do not modify files
        \\      --skip-gitignored
        \\                   Skip common generated folders and entries from <path>/.gitignore
        \\      --no-skip-gitignored
        \\                   Disable .gitignore/default skipping while recursing
        \\  -h, --help       Show this help message
        \\      --version    Print version and exit
        \\
    ) catch {};
}

fn matchesRule(rule: IgnoreRule, rel_path: []const u8) bool {
    if (!rule.has_slash) {
        if (rule.anchored) {
            return globMatch(rule.pattern, rel_path);
        }

        var segments = std.mem.splitScalar(u8, rel_path, '/');
        while (segments.next()) |segment| {
            if (globMatch(rule.pattern, segment)) return true;
        }
        return false;
    }

    if (rule.anchored) {
        return globMatch(rule.pattern, rel_path);
    }

    var start: usize = 0;

    while (true) {
        if (globMatch(rule.pattern, rel_path[start..])) return true;
        const next_sep = std.mem.indexOfScalarPos(u8, rel_path, start, '/') orelse break;
        start = next_sep + 1;
    }

    return false;
}

fn globMatch(pattern: []const u8, text: []const u8) bool {
    return globMatchAt(pattern, 0, text, 0);
}

fn globMatchAt(pattern: []const u8, pattern_index: usize, text: []const u8, text_index: usize) bool {
    var p = pattern_index;
    var t = text_index;

    while (p < pattern.len) {
        const token = pattern[p];
        switch (token) {
            '*' => {
                const double_star = p + 1 < pattern.len and pattern[p + 1] == '*';
                p += if (double_star) 2 else 1;

                while (p < pattern.len and pattern[p] == '*') {
                    p += 1;
                }

                if (p == pattern.len) {
                    return double_star or std.mem.indexOfScalar(u8, text[t..], '/') == null;
                }

                var scan = t;
                while (true) {
                    if (globMatchAt(pattern, p, text, scan)) return true;
                    if (scan == text.len) break;
                    if (!double_star and text[scan] == '/') break;
                    scan += 1;
                }
                return false;
            },
            '?' => {
                if (t == text.len or text[t] == '/') return false;
                p += 1;
                t += 1;
            },
            '\\' => {
                p += 1;
                if (p == pattern.len) return false;
                if (t == text.len or pattern[p] != text[t]) return false;
                p += 1;
                t += 1;
            },
            else => {
                if (t == text.len or token != text[t]) return false;
                p += 1;
                t += 1;
            },
        }
    }

    return t == text.len;
}

/// Transforms `input` bytes, replacing known "LLM accent" Unicode sequences
/// with ASCII equivalents, appending the result to `output`.
///
const Replacement = struct {
    from: []const u8,
    to: []const u8,
};

// Keep this table ASCII-only so the source stays easy to compile and review.
// The input strings are UTF-8 byte sequences written with hexadecimal escapes.
const replacements = [_]Replacement{
    // Quotes and apostrophes
    .{ .from = "\xE2\x80\x98", .to = "'" },
    .{ .from = "\xE2\x80\x99", .to = "'" },
    .{ .from = "\xE2\x80\x9A", .to = "'" },
    .{ .from = "\xE2\x80\x9B", .to = "'" },
    .{ .from = "\xE2\x80\x9C", .to = "\"" },
    .{ .from = "\xE2\x80\x9D", .to = "\"" },
    .{ .from = "\xE2\x80\x9E", .to = "\"" },
    .{ .from = "\xE2\x80\x9F", .to = "\"" },
    .{ .from = "\xE2\x80\xB2", .to = "'" },
    .{ .from = "\xE2\x80\xB3", .to = "\"" },

    // Dashes and hyphen-like characters
    .{ .from = "\xE2\x80\x90", .to = "-" },
    .{ .from = "\xE2\x80\x91", .to = "-" },
    .{ .from = "\xE2\x80\x92", .to = "-" },
    .{ .from = "\xE2\x80\x93", .to = "-" },
    .{ .from = "\xE2\x80\x94", .to = "-" },
    .{ .from = "\xE2\x80\x95", .to = "-" },
    .{ .from = "\xE2\x88\x92", .to = "-" },
    .{ .from = "\xE2\x80\xA6", .to = "..." },

    // Directional arrows
    .{ .from = "\xE2\x86\x90", .to = "<-" },
    .{ .from = "\xE2\x86\x92", .to = "->" },
    .{ .from = "\xE2\x86\x94", .to = "<->" },
    .{ .from = "\xE2\x86\x91", .to = "^" },
    .{ .from = "\xE2\x86\x93", .to = "v" },
    .{ .from = "\xE2\x86\x95", .to = "^v" },
    .{ .from = "\xE2\x87\x90", .to = "<=" },
    .{ .from = "\xE2\x87\x92", .to = "=>" },
    .{ .from = "\xE2\x87\x94", .to = "<=>" },

    // Bullets, check marks, and common list symbols
    .{ .from = "\xE2\x80\xA2", .to = "*" },
    .{ .from = "\xE2\x80\xA3", .to = ">" },
    .{ .from = "\xE2\x81\x83", .to = "-" },
    .{ .from = "\xE2\x98\x90", .to = "[ ]" },
    .{ .from = "\xE2\x98\x91", .to = "[x]" },
    .{ .from = "\xE2\x98\x92", .to = "[x]" },
    .{ .from = "\xE2\x9C\x93", .to = "[x]" },
    .{ .from = "\xE2\x9C\x94", .to = "[x]" },
    .{ .from = "\xE2\x9C\x97", .to = "[ ]" },
    .{ .from = "\xE2\x9C\x98", .to = "[ ]" },
    .{ .from = "\xE2\x98\x85", .to = "*" },
    .{ .from = "\xE2\x98\x86", .to = "*" },
    .{ .from = "\xE2\x97\x8F", .to = "*" },
    .{ .from = "\xE2\x97\x8B", .to = "o" },

    // Math and comparison symbols
    .{ .from = "\xC2\xB1", .to = "+/-" },
    .{ .from = "\xC3\x97", .to = "x" },
    .{ .from = "\xC3\xB7", .to = "/" },
    .{ .from = "\xE2\x89\xA0", .to = "!=" },
    .{ .from = "\xE2\x89\xA4", .to = "<=" },
    .{ .from = "\xE2\x89\xA5", .to = ">=" },
    .{ .from = "\xE2\x89\x88", .to = "~=" },
    .{ .from = "\xE2\x88\x9E", .to = "inf" },

    // Whitespace and invisible formatting characters
    .{ .from = "\xC2\xA0", .to = " " },
    .{ .from = "\xE2\x80\x80", .to = " " },
    .{ .from = "\xE2\x80\x81", .to = " " },
    .{ .from = "\xE2\x80\x82", .to = " " },
    .{ .from = "\xE2\x80\x83", .to = " " },
    .{ .from = "\xE2\x80\x84", .to = " " },
    .{ .from = "\xE2\x80\x85", .to = " " },
    .{ .from = "\xE2\x80\x86", .to = " " },
    .{ .from = "\xE2\x80\x87", .to = " " },
    .{ .from = "\xE2\x80\x88", .to = " " },
    .{ .from = "\xE2\x80\x89", .to = " " },
    .{ .from = "\xE2\x80\x8A", .to = " " },
    .{ .from = "\xE2\x80\x8B", .to = "" },
    .{ .from = "\xE2\x80\x8C", .to = "" },
    .{ .from = "\xE2\x80\x8D", .to = "" },
    .{ .from = "\xE2\x80\x8E", .to = "" },
    .{ .from = "\xE2\x80\x8F", .to = "" },
    .{ .from = "\xE2\x80\xAF", .to = " " },
    .{ .from = "\xE2\x81\x9F", .to = " " },
    .{ .from = "\xE2\x81\xA0", .to = "" },
    .{ .from = "\xE3\x80\x80", .to = " " },
    .{ .from = "\xEF\xBB\xBF", .to = "" },
};

fn transformBytes(input: []const u8, output: *std.ArrayList(u8), allocator: mem.Allocator) !void {
    var i: usize = 0;
    while (i < input.len) {
        var replaced = false;
        for (replacements) |replacement| {
            if (mem.startsWith(u8, input[i..], replacement.from)) {
                try output.appendSlice(allocator, replacement.to);
                i += replacement.from.len;
                replaced = true;
                break;
            }
        }

        if (!replaced) {
            try output.append(allocator, input[i]);
            i += 1;
        }
    }
}

fn processFile(
    allocator: mem.Allocator,
    base_dir: fs.Dir,
    path: []const u8,
    dry_run: bool,
    show_header: bool,
) !void {
    const max_size = 1024 * 1024 * 1024; // 1 GiB limit
    const input = blk: {
        const file = base_dir.openFile(path, .{}) catch |err| {
            var open_err_buf: [4096]u8 = undefined;
            const open_err_msg = std.fmt.bufPrint(&open_err_buf, "error: cannot open '{s}': {s}\n", .{ path, @errorName(err) }) catch "error: cannot open file\n";
            fs.File.stderr().writeAll(open_err_msg) catch {};
            return err;
        };
        const data = file.readToEndAlloc(allocator, max_size) catch |err| {
            file.close();
            var read_err_buf: [4096]u8 = undefined;
            const read_err_msg = std.fmt.bufPrint(&read_err_buf, "error: cannot read '{s}': {s}\n", .{ path, @errorName(err) }) catch "error: cannot read file\n";
            fs.File.stderr().writeAll(read_err_msg) catch {};
            return err;
        };
        file.close();
        break :blk data;
    };
    defer allocator.free(input);

    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    try transformBytes(input, &output, allocator);

    if (dry_run) {
        const stdout = fs.File.stdout();
        if (show_header) {
            var hdr_buf: [4096]u8 = undefined;
            const hdr = try std.fmt.bufPrint(&hdr_buf, "==> {s} <==\n", .{path});
            try stdout.writeAll(hdr);
        }
        try stdout.writeAll(output.items);
        if (show_header) try stdout.writeAll("\n");
    } else {
        // Atomic write: transform into a .tmp file, then rename over the original
        const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
        defer allocator.free(tmp_path);

        const tmp_file = base_dir.createFile(tmp_path, .{}) catch |err| {
            var create_err_buf: [4096]u8 = undefined;
            const create_err_msg = std.fmt.bufPrint(&create_err_buf, "error: cannot create '{s}': {s}\n", .{ tmp_path, @errorName(err) }) catch "error: cannot create tmp file\n";
            fs.File.stderr().writeAll(create_err_msg) catch {};
            return err;
        };

        tmp_file.writeAll(output.items) catch |err| {
            tmp_file.close();
            base_dir.deleteFile(tmp_path) catch {};
            var write_err_buf: [4096]u8 = undefined;
            const write_err_msg = std.fmt.bufPrint(&write_err_buf, "error: cannot write '{s}': {s}\n", .{ tmp_path, @errorName(err) }) catch "error: cannot write tmp file\n";
            fs.File.stderr().writeAll(write_err_msg) catch {};
            return err;
        };
        tmp_file.close();

        base_dir.rename(tmp_path, path) catch |err| {
            base_dir.deleteFile(tmp_path) catch {};
            var rename_err_buf: [4096]u8 = undefined;
            const rename_err_msg = std.fmt.bufPrint(&rename_err_buf, "error: cannot replace '{s}': {s}\n", .{ path, @errorName(err) }) catch "error: cannot replace file\n";
            fs.File.stderr().writeAll(rename_err_msg) catch {};
            return err;
        };

        var proc_buf: [4096]u8 = undefined;
        try fs.File.stdout().writeAll(try std.fmt.bufPrint(&proc_buf, "processed: {s}\n", .{path}));
    }
}

fn processDir(
    allocator: mem.Allocator,
    cwd: fs.Dir,
    full_dir_path: []const u8,
    rel_dir_path: []const u8,
    dry_run: bool,
    ignore_matcher: ?*const IgnoreMatcher,
) !void {
    var dir = cwd.openDir(full_dir_path, .{ .iterate = true }) catch |err| {
        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "warning: skipping '{s}': {s}\n", .{ full_dir_path, @errorName(err) }) catch "warning: skipping directory\n";
        fs.File.stderr().writeAll(msg) catch {};
        return;
    };
    defer dir.close();

    var pending_entries: std.ArrayList(PendingEntry) = .empty;
    defer {
        for (pending_entries.items) |entry| {
            allocator.free(entry.name);
        }
        pending_entries.deinit(allocator);
    }

    var iter = dir.iterate();
    while (true) {
        const entry = iter.next() catch |err| {
            var buf: [4096]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "warning: error reading '{s}': {s}\n", .{ full_dir_path, @errorName(err) }) catch "warning: error reading directory\n";
            fs.File.stderr().writeAll(msg) catch {};
            break;
        } orelse break;

        try pending_entries.append(allocator, .{
            .name = try allocator.dupe(u8, entry.name),
            .kind = entry.kind,
        });
    }

    for (pending_entries.items) |entry| {
        const full_entry_path = try fs.path.join(allocator, &.{ full_dir_path, entry.name });
        defer allocator.free(full_entry_path);

        const rel_entry_path = if (rel_dir_path.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel_dir_path, entry.name });
        defer allocator.free(rel_entry_path);

        if (ignore_matcher) |matcher| {
            if (matcher.shouldSkip(rel_entry_path, entry.kind == .directory)) {
                continue;
            }
        }

        switch (entry.kind) {
            .file => processFile(allocator, cwd, full_entry_path, dry_run, true) catch {},
            .directory => processDir(allocator, cwd, full_entry_path, rel_entry_path, dry_run, ignore_matcher) catch {},
            else => {},
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    var recursive = false;
    var dry_run = false;
    var skip_gitignored = true;
    var input_path: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.eql(u8, arg, "--recursive") or mem.eql(u8, arg, "-r")) {
            recursive = true;
        } else if (mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
        } else if (mem.eql(u8, arg, "--skip-gitignored")) {
            skip_gitignored = true;
        } else if (mem.eql(u8, arg, "--no-skip-gitignored")) {
            skip_gitignored = false;
        } else if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (mem.eql(u8, arg, "--version")) {
            var ver_buf: [256]u8 = undefined;
            const ver_msg = std.fmt.bufPrint(&ver_buf, "unslop {s}\n", .{version}) catch "unslop\n";
            fs.File.stdout().writeAll(ver_msg) catch {};
            return;
        } else if (arg.len > 0 and arg[0] != '-') {
            if (input_path != null) {
                fs.File.stderr().writeAll(
                    "error: only one path argument is supported\n",
                ) catch {};
                printUsage();
                process.exit(1);
            }
            input_path = arg;
        } else {
            var flag_err_buf: [4096]u8 = undefined;
            const flag_err_msg = std.fmt.bufPrint(&flag_err_buf, "error: unknown flag '{s}'\n", .{arg}) catch "error: unknown flag\n";
            fs.File.stderr().writeAll(flag_err_msg) catch {};
            printUsage();
            process.exit(1);
        }
    }

    const the_path = input_path orelse {
        fs.File.stderr().writeAll(
            "error: missing path argument\n",
        ) catch {};
        printUsage();
        process.exit(1);
    };

    const cwd = fs.cwd();

    // Detect whether path is a directory by attempting to open it as one
    const is_dir = blk: {
        var d = cwd.openDir(the_path, .{}) catch break :blk false;
        d.close();
        break :blk true;
    };

    if (is_dir) {
        if (!recursive) {
            var dir_err_buf: [4096]u8 = undefined;
            const dir_err_msg = std.fmt.bufPrint(&dir_err_buf, "error: '{s}' is a directory; use -r/--recursive to process directories\n", .{the_path}) catch "error: path is a directory; use -r/--recursive\n";
            fs.File.stderr().writeAll(dir_err_msg) catch {};
            process.exit(1);
        }

        var ignore_matcher = IgnoreMatcher.init(allocator);
        defer ignore_matcher.deinit();

        if (skip_gitignored) {
            try ignore_matcher.loadDefaults();
            try ignore_matcher.loadGitignore(cwd, the_path);
        }

        try processDir(allocator, cwd, the_path, "", dry_run, if (skip_gitignored) &ignore_matcher else null);
    } else {
        try processFile(allocator, cwd, the_path, dry_run, false);
    }
}

test "default ignore rules skip common generated directories" {
    var matcher = IgnoreMatcher.init(std.testing.allocator);
    defer matcher.deinit();

    try matcher.loadDefaults();

    try std.testing.expect(matcher.shouldSkip("node_modules", true));
    try std.testing.expect(matcher.shouldSkip("src/node_modules", true));
    try std.testing.expect(matcher.shouldSkip("dist", true));
    try std.testing.expect(!matcher.shouldSkip("src/dist.txt", false));
}

test "gitignore rules support comments wildcards and negation" {
    var matcher = IgnoreMatcher.init(std.testing.allocator);
    defer matcher.deinit();

    try matcher.addPatternLine("# comment");
    try matcher.addPatternLine("*.log");
    try matcher.addPatternLine("!keep.log");
    try matcher.addPatternLine("cache/");

    try std.testing.expect(matcher.shouldSkip("app.log", false));
    try std.testing.expect(matcher.shouldSkip("nested/error.log", false));
    try std.testing.expect(!matcher.shouldSkip("nested/keep.log", false));
    try std.testing.expect(matcher.shouldSkip("nested/cache", true));
    try std.testing.expect(!matcher.shouldSkip("nested/cache.txt", false));
}

test "gitignore rules support rooted and nested path patterns" {
    var matcher = IgnoreMatcher.init(std.testing.allocator);
    defer matcher.deinit();

    try matcher.addPatternLine("/root-only.txt");
    try matcher.addPatternLine("generated/output.txt");
    try matcher.addPatternLine("**/tmp/");

    try std.testing.expect(matcher.shouldSkip("root-only.txt", false));
    try std.testing.expect(!matcher.shouldSkip("nested/root-only.txt", false));
    try std.testing.expect(matcher.shouldSkip("generated/output.txt", false));
    try std.testing.expect(matcher.shouldSkip("src/generated/output.txt", false));
    try std.testing.expect(matcher.shouldSkip("src/tmp", true));
}

test "transform replaces common AI typography with ASCII" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    const input = "\xE2\x80\x9Cquoted\xE2\x80\x9D \xE2\x80\x94 \xE2\x86\x90\xE2\x86\x92 \xE2\x80\xA2 item \xE2\x9C\x93 \xE2\x89\xA4 10";
    try transformBytes(input, &output, std.testing.allocator);

    try std.testing.expectEqualStrings("\"quoted\" - <--> * item [x] <= 10", output.items);
}

test "transform removes invisible formatting and normalizes spaces" {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(std.testing.allocator);

    const input = "a\xC2\xA0b\xE2\x80\x8Bc\xE2\x80\x8Dd\xEF\xBB\xBF";
    try transformBytes(input, &output, std.testing.allocator);

    try std.testing.expectEqualStrings("a bcd", output.items);
}
