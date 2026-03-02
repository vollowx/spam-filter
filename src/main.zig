const std = @import("std");
const spam_filter = @import("spam_filter");

pub fn main() !void {
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    var spam_bow = spam_filter.Bow.init(allocator);
    var ham_bow = spam_filter.Bow.init(allocator);

    var spam_token_count: usize = 0;
    var ham_token_count: usize = 0;

    try spam_filter.bowAppendDir(allocator, &spam_bow, &spam_token_count, "./data/enron1/spam");
    try spam_filter.bowAppendDir(allocator, &ham_bow,  &ham_token_count,  "./data/enron1/ham");

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

        const res = try spam_filter.classifyFile(
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
        @as(f64, @floatFromInt(spam_count)) / (@as(f64, @floatFromInt(spam_count + ham_count))),
    });
}
