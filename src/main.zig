const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const process = std.process;
const build_options = @import("build_options");

const version = build_options.version;

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
        \\  -h, --help       Show this help message
        \\      --version    Print version and exit
        \\
    ) catch {};
}

/// Transforms `input` bytes, replacing known "LLM accent" Unicode sequences
/// with ASCII equivalents, appending the result to `output`.
///
/// Replacements (UTF-8 encoded):
///   U+201C / U+201D  E2 80 9C / 9D  curly double quotes  ->  "
///   U+2018 / U+2019  E2 80 98 / 99  curly single quotes  ->  '
///   U+2014           E2 80 94       em-dash               ->  -
///   U+2013           E2 80 93       en-dash               ->  -
///   U+2026           E2 80 A6       ellipsis              ->  ...
///   U+00A0           C2 A0          non-breaking space    ->  (space)
fn transformBytes(input: []const u8, output: *std.ArrayList(u8), allocator: mem.Allocator) !void {
    var i: usize = 0;
    while (i < input.len) {
        const b0 = input[i];
        i += 1;
        switch (b0) {
            // Potential E2 80 XX sequence: smart quotes, em/en-dash, ellipsis
            0xE2 => {
                // Need at least 2 more bytes for a match
                if (i + 1 < input.len and input[i] == 0x80) {
                    const b2 = input[i + 1];
                    i += 2;
                    switch (b2) {
                        0x9C, 0x9D => try output.append(allocator, '"'), // " " -> "
                        0x98, 0x99 => try output.append(allocator, '\''), // ' ' -> '
                        0x94, 0x93 => try output.append(allocator, '-'), // em/en-dash -> -
                        0xA6 => try output.appendSlice(allocator, "..."), // ellipsis -> ...
                        else => {
                            try output.append(allocator, b0);
                            try output.append(allocator, 0x80);
                            try output.append(allocator, b2);
                        },
                    }
                } else {
                    // Insufficient bytes or b1 != 0x80: pass through as-is
                    try output.append(allocator, b0);
                    if (i < input.len) {
                        try output.append(allocator, input[i]);
                        i += 1;
                    }
                }
            },
            // Potential C2 A0 sequence: non-breaking space
            0xC2 => {
                if (i < input.len and input[i] == 0xA0) {
                    try output.append(allocator, ' '); // NBSP -> space
                    i += 1;
                } else {
                    try output.append(allocator, b0);
                    if (i < input.len) {
                        try output.append(allocator, input[i]);
                        i += 1;
                    }
                }
            },
            else => try output.append(allocator, b0),
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
    dir_path: []const u8,
    dry_run: bool,
) !void {
    var dir = cwd.openDir(dir_path, .{ .iterate = true }) catch |err| {
        var buf: [4096]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "warning: skipping '{s}': {s}\n", .{ dir_path, @errorName(err) }) catch "warning: skipping directory\n";
        fs.File.stderr().writeAll(msg) catch {};
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (true) {
        const entry = iter.next() catch |err| {
            var buf: [4096]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "warning: error reading '{s}': {s}\n", .{ dir_path, @errorName(err) }) catch "warning: error reading directory\n";
            fs.File.stderr().writeAll(msg) catch {};
            break;
        } orelse break;

        const entry_path = try fs.path.join(allocator, &.{ dir_path, entry.name });
        defer allocator.free(entry_path);

        switch (entry.kind) {
            .file => processFile(allocator, cwd, entry_path, dry_run, true) catch {},
            .directory => processDir(allocator, cwd, entry_path, dry_run) catch {},
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
    var input_path: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (mem.eql(u8, arg, "--recursive") or mem.eql(u8, arg, "-r")) {
            recursive = true;
        } else if (mem.eql(u8, arg, "--dry-run")) {
            dry_run = true;
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
        try processDir(allocator, cwd, the_path, dry_run);
    } else {
        try processFile(allocator, cwd, the_path, dry_run, false);
    }
}
