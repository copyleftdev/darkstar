const std = @import("std");

pub const Terminal = struct {
    writer: std.fs.File.Writer,
    
    // POSIX termios handling
    orig_termios: ?std.posix.termios = null,

    pub fn init() Terminal {
        return Terminal{ .writer = std.io.getStdOut().writer() };
    }
    
    pub fn enableRawMode(self: *Terminal) !void {
        const stdin_fd = std.io.getStdIn().handle;
        self.orig_termios = try std.posix.tcgetattr(stdin_fd);
        
        var raw = self.orig_termios.?;
        // Disable ECHO, ICANON (canonical mode), ISIG (signals like Ctrl-C), IEXTEN
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.ISIG = false; // We will handle quits manually or pass through
        raw.lflag.IEXTEN = false;
        
        // Apply changes
        try std.posix.tcsetattr(stdin_fd, .FLUSH, raw);
    }
    
    pub fn disableRawMode(self: *Terminal) void {
        if (self.orig_termios) |orig| {
            const stdin_fd = std.io.getStdIn().handle;
            std.posix.tcsetattr(stdin_fd, .FLUSH, orig) catch {};
        }
    }
    
    pub fn readKey(self: Terminal) !?u8 {
        _ = self;
        const stdin = std.io.getStdIn();
        // Check if data is available (poll)
        var pfd = [1]std.posix.pollfd{
            .{ .fd = stdin.handle, .events = std.posix.POLL.IN, .revents = 0 },
        };
        const count = try std.posix.poll(&pfd, 0); // 0 timeout = return immediately
        if (count > 0) {
             var buf: [1]u8 = undefined;
             const bits = try stdin.read(&buf);
             if (bits > 0) return buf[0];
        }
        return null;
    }

    pub fn hideCursor(self: Terminal) !void {
        try self.writer.writeAll("\x1B[?25l");
    }

    pub fn showCursor(self: Terminal) !void {
        try self.writer.writeAll("\x1B[?25h");
    }

    pub fn clearLine(self: Terminal) !void {
        // Clear entire line and return header to column 0
        try self.writer.writeAll("\x1B[2K\r");
    }

    pub fn moveUp(self: Terminal, n: usize) !void {
        try self.writer.print("\x1B[{d}A", .{n});
    }
    
    // ... colors ...
    pub fn colorRed(self: Terminal) !void { try self.writer.writeAll("\x1B[31m"); }
    pub fn colorGreen(self: Terminal) !void { try self.writer.writeAll("\x1B[32m"); }
    pub fn colorReset(self: Terminal) !void { try self.writer.writeAll("\x1B[0m"); }
    pub fn colorDim(self: Terminal) !void { try self.writer.writeAll("\x1B[2m"); }
    pub fn bold(self: Terminal) !void { try self.writer.writeAll("\x1B[1m"); }
};

// UI Dashboard State
pub const Dashboard = struct {
    term: Terminal,
    last_printed_lines: usize = 0,
    
    // Ring Buffer for Logs
    allocator: std.mem.Allocator,
    logs: std.ArrayList([]const u8),
    max_logs: usize = 10,
    
    // Rate Limiting
    log_rate_limit: usize = 5,
    logs_this_second: usize = 0,
    last_log_sec: i64 = 0,

    pub fn init(allocator: std.mem.Allocator) Dashboard {
        return Dashboard{ 
            .term = Terminal.init(),
            .allocator = allocator,
            .logs = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn start(self: *Dashboard) !void {
        try self.term.enableRawMode();
        try self.term.hideCursor();
    }
    
    pub fn finish(self: *Dashboard) !void {
        try self.term.showCursor();
        self.term.disableRawMode();
        try self.term.writer.print("\n", .{}); 
    }
    
    // Check if we can add a log right now (prevents alloc spam)
    pub fn canLog(self: *Dashboard) bool {
        const now_sec = @divTrunc(std.time.milliTimestamp(), 1000);
        if (now_sec > self.last_log_sec) {
            self.logs_this_second = 0;
            self.last_log_sec = now_sec;
        }
        return self.logs_this_second < self.log_rate_limit;
    }
    
    pub fn deinit(self: *Dashboard) void {
        for (self.logs.items) |msg| {
            self.allocator.free(msg);
        }
        self.logs.deinit();
    }
    
    pub fn addLog(self: *Dashboard, msg: []const u8) !void {
        // Enforce limit if not checked (safety)
        if (!self.canLog()) return; 
        
        const msg_copy = try self.allocator.dupe(u8, msg);
        if (self.logs.items.len >= self.max_logs) {
             const old = self.logs.orderedRemove(0);
             self.allocator.free(old);
        }
        try self.logs.append(msg_copy);
        self.logs_this_second += 1;
    }
    
    pub fn render(self: *Dashboard, target: []const u8, elapsed_ms: i64, announcements: usize, withdrawals: usize, unique_peers: usize) !void {
        // Clear previous frame
        if (self.last_printed_lines > 0) {
            try self.term.moveUp(self.last_printed_lines);
        }
        
        // Calculate total lines: 
        // Header (3) + Stats (4) + Logs (max_logs + 2) + Progress (2) = ~21 lines
        // Minimal layout:
        
        try self.term.clearLine();
        try self.term.bold();
        try self.term.writer.print("Target: {s}", .{target});
        try self.term.colorReset();
        
        try self.term.writer.print("   [ ", .{});
        try self.term.colorDim();
        try self.term.writer.print("{d:0>2}:{d:0>2}", .{@divTrunc(elapsed_ms, 60000), @divTrunc(@mod(elapsed_ms, 60000), 1000)});
        try self.term.colorReset();
        try self.term.writer.print(" ]\n", .{});
        try self.term.clearLine(); 
        
        // Stats Row
        try self.term.writer.print("  Ann: ", .{});
        try self.term.colorGreen(); try self.term.writer.print("{d:<5}", .{announcements}); try self.term.colorReset();
        try self.term.writer.print("  Wdn: ", .{});
        try self.term.colorRed();   try self.term.writer.print("{d:<5}", .{withdrawals});   try self.term.colorReset();
        try self.term.writer.print("  Peers: {d}\n", .{unique_peers});
        try self.term.clearLine(); 
        try self.term.writer.print("\n", .{});

        // Event Log
        try self.term.clearLine();
        try self.term.bold(); try self.term.writer.print("Recent Events:\n", .{}); try self.term.colorReset();
        
        var i: usize = 0;
        while (i < self.max_logs) : (i += 1) {
            try self.term.clearLine();
            if (i < self.logs.items.len) {
                // Reverse order? Newest at bottom?
                // Typically scrolling log has newest at bottom.
                const msg = self.logs.items[i];
                try self.term.writer.print("  {s}\n", .{msg});
            } else {
                try self.term.writer.print("\n", .{});
            }
        }
        
        try self.term.clearLine(); 
        try self.term.writer.print("\n", .{});

        // Progress
        try self.term.clearLine();
        const width = 40;
        const progress = @min(width, @divTrunc(elapsed_ms * width, 5000));
        try self.term.writer.print(" [", .{});
        var j: usize = 0;
        while (j < width) : (j += 1) {
            if (j < progress) { try self.term.colorGreen(); try self.term.writer.print("=", .{}); try self.term.colorReset(); }
            else if (j == progress) try self.term.writer.print(">", .{})
            else try self.term.writer.print(" ", .{});
        }
        try self.term.writer.print("] Scanning...\n", .{});

        self.last_printed_lines = 4 + 2 + self.max_logs + 2 + 1; // Approx
    }
};
