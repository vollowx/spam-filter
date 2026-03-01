const std = @import("std");

const Bow = std.StringHashMap(u32);

fn bowAppendFile(
    allocator: std.mem.Allocator,
    bow: *Bow,
    bow_token_count: *usize,
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
        bow_token_count.* += 1;
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

fn bowAppendDir(
    allocator: std.mem.Allocator,
    bow: *Bow,
    bow_token_count: *usize,
    path: []const u8,
) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        try bowAppendFile(allocator, bow, bow_token_count, dir, entry.path);
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
    spam_token_count: usize,
    ham_token_count: usize,
    spam_prob: f64,
    ham_prob: f64,
) !ClassificationResult {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, (try file.stat()).size);
    defer allocator.free(buffer);

    var spam_score = spam_prob;
    var ham_score  = ham_prob;

    const vocabulary_size = @as(f64, @floatFromInt(spam_bow.count() + ham_bow.count()));

    var iter = std.mem.tokenizeAny(u8, buffer, " \n\r\t,:.?!");
    while (iter.next()) |word| {
        const lowered = try allocator.dupe(u8, word);
        _ = std.ascii.lowerString(lowered, lowered);

        const n_spam = @as(f64, @floatFromInt(spam_bow.get(lowered) orelse 0));
        const n_ham  = @as(f64, @floatFromInt(ham_bow.get(lowered) orelse 0));

        // Use Laplace Smoothing (adding 1 to avoid log(0))
        // P(word|spam) = (count in spam + 1) / (total words in spam + vocab size)
        spam_score += std.math.log10((n_spam + 1.0) / (@as(f64, @floatFromInt(spam_token_count)) + vocabulary_size));
        ham_score  += std.math.log10((n_ham + 1.0)  / (@as(f64, @floatFromInt(ham_token_count))  + vocabulary_size));
    }

    return ClassificationResult{
        .is_spam = spam_score > ham_score,
        .spam_score = spam_score,
        .ham_score = ham_score,
    };
}

pub fn main() !void {
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    var spam_bow = Bow.init(allocator);
    var ham_bow = Bow.init(allocator);

    var spam_token_count: usize = 0;
    var ham_token_count: usize = 0;

    try bowAppendDir(allocator, &spam_bow, &spam_token_count, "./data/enron1/spam");
    try bowAppendDir(allocator, &ham_bow,  &ham_token_count,  "./data/enron1/ham");

    const total_token_count = @as(f64, @floatFromInt(spam_token_count + ham_token_count));
    const spam_prob = std.math.log10(@as(f64, @floatFromInt(spam_token_count)) / total_token_count);
    const ham_prob = std.math.log10(@as(f64, @floatFromInt(ham_token_count)) / total_token_count);

    var spam_count: u32 = 0;
    var ham_count: u32 = 0;

    var test_dir = try std.fs.cwd().openDir("./data/enron1/spam", .{ .iterate = true });
    defer test_dir.close();
    var walker = try test_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ "./data/enron1/spam", entry.path });

        const res = try classifyFile(
            allocator,
            full_path,
            spam_bow,
            ham_bow,
            spam_token_count,
            ham_token_count,
            spam_prob,
            ham_prob
        );

        if (res.is_spam) {
            spam_count += 1;
        } else {
            ham_count += 1;
        }
    }

    std.debug.print("Acc: {}\n", .{
        @as(f64, @floatFromInt(ham_count)) / (@as(f64, @floatFromInt(spam_count + ham_count))),
    });
}
