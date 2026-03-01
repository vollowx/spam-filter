const std = @import("std");

const Bow = std.StringHashMap(u32);

fn allocLower(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var dest = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        dest[i] = switch (c) {
            'A'...'Z' => c + 32,
            else => c,
        };
    }
    return dest;
}

fn readToEndCountBow(
    allocator: std.mem.Allocator,
    bow: *Bow,
    dir: std.fs.Dir,
    relpath: []const u8,
) !void {
    const file = try dir.openFile(relpath, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(buffer);

    var iter = std.mem.tokenizeAny(u8, buffer, " \n\r\t,:.?!");
    while (iter.next()) |word| {
        const lowered = try allocator.dupe(u8, word);
        _ = std.ascii.lowerString(lowered, lowered);
        const result = try bow.getOrPut(lowered);
        if (result.found_existing) {
            result.value_ptr.* += 1;
        } else {
            result.key_ptr.* = try allocator.dupe(u8, lowered);
            result.value_ptr.* = 1;
        }
    }
}

fn walkDirCountBow(
    allocator: std.mem.Allocator,
    bow: *Bow,
    path: []const u8,
) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        try readToEndCountBow(allocator, bow, dir, entry.path);
    }
}

pub const ClassificationResult = struct {
    is_spam: bool,
    spam_score: f64,
    ham_score: f64,
};

fn classifyFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    spam_bow: Bow,
    ham_bow: Bow,
    spam_total: usize,
    ham_total: usize,
    spam_p: f64,
    ham_p: f64,
) !ClassificationResult {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, (try file.stat()).size);
    defer allocator.free(buffer);

    var spam_score = spam_p;
    var ham_score = ham_p;

    const vocabulary_size = @as(f64, @floatFromInt(spam_bow.count() + ham_bow.count()));

    var iter = std.mem.tokenizeAny(u8, buffer, " \n\r\t,:.?!");
    while (iter.next()) |word| {
        const lowered = try allocLower(allocator, word);
        defer allocator.free(lowered);

        const n_spam = @as(f64, @floatFromInt(spam_bow.get(lowered) orelse 0));
        const n_ham  = @as(f64, @floatFromInt(ham_bow.get(lowered) orelse 0));

        // Use Laplace Smoothing (adding 1 to avoid log(0))
        // P(word|spam) = (count in spam + 1) / (total words in spam + vocab size)
        spam_score += std.math.log10((n_spam + 1.0) / (@as(f64, @floatFromInt(spam_total)) + vocabulary_size));
        ham_score += std.math.log10((n_ham + 1.0) / (@as(f64, @floatFromInt(ham_total)) + vocabulary_size));
    }

    return ClassificationResult{
        .is_spam = spam_score > ham_score,
        .spam_score = spam_score,
        .ham_score = ham_score,
    };
}

pub fn main() !void {
    var arena_alloc = std.heap.GeneralPurposeAllocator.init(std.heap.page_allocator);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    var spam_bow = Bow.init(allocator);
    var ham_bow = Bow.init(allocator);

    std.debug.print("Training...\n", .{});
    try walkDirCountBow(allocator, &spam_bow, "./data/enron1/spam");
    try walkDirCountBow(allocator, &ham_bow, "./data/enron1/ham");
    std.debug.print("Training done.\n", .{});

    var spam_total: usize = 0;
    var ham_total: usize = 0;

    var it = spam_bow.iterator();
    while (it.next()) |entry| { spam_total += entry.value_ptr.*; }
    it = ham_bow.iterator();
    while (it.next()) |entry| { ham_total += entry.value_ptr.*; }

    const total = @as(f64, @floatFromInt(spam_total + ham_total));
    const spam_p = std.math.log10(@as(f64, @floatFromInt(spam_total)) / total);
    const ham_p = std.math.log10(@as(f64, @floatFromInt(ham_total)) / total);

    std.debug.print("Classifying emails...\n---\n", .{});

    var test_dir = try std.fs.cwd().openDir("./data/enron1/ham", .{ .iterate = true });
    defer test_dir.close();
    var walker = try test_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ "./data/enron1/ham", entry.path });

        const res = try classifyFile(
            allocator,
            full_path,
            spam_bow,
            ham_bow,
            spam_total,
            ham_total,
            spam_p,
            ham_p
        );

        std.debug.print("Path: {s: <40} => {s} {} {}\n", .{
            entry.path,
            if (res.is_spam) "spam" else "ham ",
            res.spam_score,
            res.ham_score,
        });
    }
}
