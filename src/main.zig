const std = @import("std");

const ContentError = error { NoFileProvided, UnclosedLoop, InexistantLoop };
const nb_cells = 32768;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const filepath = args.next();

    if (filepath == null) {
        return ContentError.NoFileProvided;
    }

    const input_file = try std.fs.cwd().openFile(filepath.?, .{});
    defer input_file.close();

    const fstat = try input_file.stat();
    const content = try input_file.readToEndAlloc(allocator, fstat.size);
    defer allocator.free(content);

    try interpret(
        content,
        std.io.getStdIn().reader().any(),
        std.io.getStdOut().writer().any()
    );
}

inline fn bounded_increment(value: usize, cap: usize) usize {
    if (value >= cap) { return 0; } else { return value + 1; }
}

inline fn bounded_decrement(value: usize, cap: usize) usize {
    if (value == 0) { return cap; } else { return value - 1; }
}

fn interpret(
    content: []const u8,
    rstream: std.io.AnyReader,
    ostream: std.io.AnyWriter
) !void {
    var buf_read = std.io.bufferedReader(rstream);
    var buf_writ = std.io.bufferedWriter(ostream);

    const reader = buf_read.reader();
    const writer = buf_writ.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var stack = std.ArrayList(usize).init(gpa.allocator());

    defer {
        stack.deinit();
        _ = gpa.deinit();
    }

    var array = std.mem.zeroes([nb_cells]u8);

    var pointer: usize = 0;
    var content_pos: usize = 0;

    while (content_pos < content.len) {
        switch (content[content_pos]) {
            '>' => pointer = bounded_increment(pointer, nb_cells - 1),
            '<' => pointer = bounded_decrement(pointer, nb_cells - 1),
            '+' => array[pointer] +%= 1,
            '-' => array[pointer] -%= 1,
            '.' => try writer.writeByte(array[pointer]),
            ',' => array[pointer] = try reader.readByte(),
            '[' => if (array[pointer] == 0) {
                var loops: usize = 1;
                content_pos += 1;

                while (loops > 0 and content_pos < content.len) {
                    switch (content[content_pos]) {
                        '[' => loops += 1,
                        ']' => loops -= 1,
                        else => {},
                    }

                    if (loops > 0) {
                        content_pos += 1;
                    }
                }

                if (loops > 0) {
                    return ContentError.UnclosedLoop;
                }
            } else {
                try stack.append(content_pos);
            },
            ']' => if (array[pointer] == 0) {
                _ = stack.pop() orelse return ContentError.InexistantLoop;
            } else {
                content_pos = stack.getLastOrNull() orelse
                    return ContentError.InexistantLoop;
            },
            else => {},
        }

        content_pos += 1;
    }

    try buf_writ.flush();
}

test "hello world" {
    const allocator = std.testing.allocator;
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer buffer.deinit();

    const content =
        \\ ++++++++++
        \\ [>+++++++>++++++++++>+++>+<<<<-]
        \\ >++.>+.+++++++..+++.>++.<<
        \\ +++++++++++++++.>.+++.------.--------.>+.>.
    ;

    // Reader is not used in this test
    try interpret(
        content,
        std.io.getStdIn().reader().any(),
        buffer.writer().any()
    );

    try std.testing.expect(std.mem.eql(u8, buffer.items, "Hello World!\n"));
}
