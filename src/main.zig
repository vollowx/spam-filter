const std = @import("std");
const zig_hello = @import("zig_hello");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var bow: std.StringHashMap(u32) = .init(allocator);
    defer {
        var key_it = bow.keyIterator();
        while (key_it.next()) |key_ptr| {
            allocator.free(key_ptr.*);
        }
        bow.deinit();
    }

    var data_dir = try std.fs.cwd().openDir("data/BG", .{ .iterate = true });
    defer data_dir.close();

    // var it = data_dir.iterate();

    var walker = try data_dir.walk(std.heap.page_allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        const file = try data_dir.openFile(entry.path, .{});
        defer file.close();

        const file_size = (try file.stat()).size;
        const buffer = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(buffer);

        var iter = std.mem.tokenizeAny(u8, buffer, " \n\r\t,:.?!");
        while (iter.next()) |word| {
            const result = try bow.getOrPut(word);
            if (result.found_existing) {
                result.value_ptr.* += 1;
            } else {
                result.key_ptr.* = try allocator.dupe(u8, word);
                result.value_ptr.* = 1;
            }
        }
    }

    var it = bow.iterator();
    while (it.next()) |entry| {
        std.debug.print("{d}: {s}\n", .{ entry.value_ptr.*, entry.key_ptr.* });
    }
}
