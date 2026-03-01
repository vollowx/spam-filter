const std = @import("std");
const zig_hello = @import("zig_hello");

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
    bow: *std.StringHashMap(u32),
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
            const lowered_word = try allocLower(allocator, word);
            const result = try bow.getOrPut(lowered_word);
            if (result.found_existing) {
                result.value_ptr.* += 1;
            } else {
                result.key_ptr.* = try allocator.dupe(u8, lowered_word);
                result.value_ptr.* = 1;
            }
        }
}

fn walkDirCountBow(
    allocator: std.mem.Allocator,
    bow: *std.StringHashMap(u32),
    path: []const u8,
) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(std.heap.page_allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        try readToEndCountBow(allocator, bow, dir, entry.path);
    }
}

pub fn main() !void {
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer _ = arena_alloc.deinit();
    const allocator = arena_alloc.allocator();

    var spam_bow: std.StringHashMap(u32) = .init(allocator);
    defer spam_bow.deinit();
    var ham_bow: std.StringHashMap(u32) = .init(allocator);
    defer ham_bow.deinit();

    try walkDirCountBow(allocator, &spam_bow, "./data/enron1/spam");
    try walkDirCountBow(allocator, &ham_bow, "./data/enron1/ham");

    const email =
        \\Subject: re : entex transistion                                                                 
        \\thanks so much for the memo . i would like to reiterate my support on two key                   
        \\issues :                                                                                        
        \\1 ) . thu - best of luck on this new assignment . howard has worked hard and                    
        \\done a great job ! please don ' t be shy on asking questions . entex is                         
        \\critical to the texas business , and it is critical to our team that we are                     
        \\timely and accurate .                                                                           
        \\2 ) . rita : thanks for setting up the account team . communication is                          
        \\critical to our success , and i encourage you all to keep each other informed                   
        \\at all times . the p & l impact to our business can be significant .                            
        \\additionally , this is high profile , so we want to assure top quality .                        
        \\thanks to all of you for all of your efforts . let me know if there is                          
        \\anything i can do to help provide any additional support .                                      
        \\rita wynne                                                                                      
        \\12 / 14 / 99 02 : 38 : 45 pm                                                                    
        \\to : janet h wallis / hou / ect @ ect , ami chokshi / corp / enron @ enron , howard b           
        \\camp / hou / ect @ ect , thu nguyen / hou / ect @ ect , kyle r lilly / hou / ect @ ect , stacey 
        \\neuweiler / hou / ect @ ect , george grant / hou / ect @ ect , julie meyers / hou / ect @ ect   
        \\cc : daren j farmer / hou / ect @ ect , kathryn cordes / hou / ect @ ect , rita                 
        \\wynne / hou / ect , lisa csikos / hou / ect @ ect , brenda f herod / hou / ect @ ect , pamela   
        \\chambers / corp / enron @ enron                                                                 
        \\subject : entex transistion                                                                     
        \\the purpose of the email is to recap the kickoff meeting held on yesterday                      
        \\with members from commercial and volume managment concernig the entex account :                 
        \\effective january 2000 , thu nguyen ( x 37159 ) in the volume managment group ,                 
        \\will take over the responsibility of allocating the entex contracts . howard                    
        \\and thu began some training this month and will continue to transition the                      
        \\account over the next few months . entex will be thu ' s primary account                        
        \\especially during these first few months as she learns the allocations                          
        \\process and the contracts .                                                                     
        \\howard will continue with his lead responsibilites within the group and be                      
        \\available for questions or as a backup , if necessary ( thanks howard for all                   
        \\your hard work on the account this year ! ) .                                                   
        \\in the initial phases of this transistion , i would like to organize an entex                   
        \\" account " team . the team ( members from front office to back office ) would                  
        \\meet at some point in the month to discuss any issues relating to the                           
        \\scheduling , allocations , settlements , contracts , deals , etc . this hopefully               
        \\will give each of you a chance to not only identify and resolve issues before                   
        \\the finalization process , but to learn from each other relative to your                        
        \\respective areas and allow the newcomers to get up to speed on the account as                   
        \\well . i would encourage everyone to attend these meetings initially as i                       
        \\believe this is a critical part to the success of the entex account .                           
        \\i will have my assistant to coordinate the initial meeting for early 1 / 2000 .                 
        \\if anyone has any questions or concerns , please feel free to call me or stop                   
        \\by . thanks in advance for everyone ' s cooperation . . . . . . . . . . .                       
        \\julie - please add thu to the confirmations distributions list                                  
    ;

    var spam_total: u32 = 0;
    var ham_total: u32 = 0;

    var it = spam_bow.iterator();
    while (it.next()) |entry| {
        spam_total += entry.value_ptr.*;
    }
    it = ham_bow.iterator();
    while (it.next()) |entry| {
        ham_total += entry.value_ptr.*;
    }

    const total = spam_total + ham_total;

    const spam_p = std.math.log(f64, 10, @as(f64, @floatFromInt(spam_total)) / @as(f64, @floatFromInt(total)));
    const  ham_p = std.math.log(f64, 10, @as(f64, @floatFromInt( ham_total)) / @as(f64, @floatFromInt(total)));

    var      dp: f64 = 0;
    var spam_dp: f64 = 0;
    var  ham_dp: f64 = 0;

    var iter = std.mem.tokenizeAny(u8, email, " \n\r\t,:.?!");
    while (iter.next()) |word| {
        const lowered_word = try allocLower(allocator, word);
        const n_spam = @as(f64, @floatFromInt(spam_bow.get(lowered_word) orelse 0));
        const n_ham  = @as(f64, @floatFromInt( ham_bow.get(lowered_word) orelse 0));
        if (n_spam == 0) continue;
        if ( n_ham == 0) continue;
        dp      += std.math.log(f64, 10, (n_spam + n_ham)                                             / @as(f64, @floatFromInt(total)));
        spam_dp += std.math.log(f64, 10, @as(f64, @floatFromInt(spam_bow.get(lowered_word) orelse 0)) / @as(f64, @floatFromInt(spam_total)));
        ham_dp  += std.math.log(f64, 10, @as(f64, @floatFromInt( ham_bow.get(lowered_word) orelse 0)) / @as(f64, @floatFromInt(ham_total)));
    }

    std.debug.print(
        \\overall spam probability = {}
        \\overall  ham probability = {}
        \\email   spam probability = {}
        \\email    ham probability = {}
        \\
    , .{
        std.math.pow(f64, 10, spam_p),
        std.math.pow(f64, 10, ham_p),
        std.math.pow(f64, 10, spam_dp * spam_p / dp),
        std.math.pow(f64, 10,  ham_dp * ham_p  / dp)
    });
}
