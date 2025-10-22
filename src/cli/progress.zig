const std = @import("std");

/// Progress bar for displaying extraction/compression progress
pub const ProgressBar = struct {
    file: std.fs.File,
    total: usize,
    current: usize,
    last_update: i64,
    update_interval_ns: i64,
    use_color: bool,
    is_tty: bool,

    const bar_width = 40;
    const update_interval = 100 * std.time.ns_per_ms; // 100ms

    /// Initialize progress bar
    pub fn init(file: std.fs.File, total: usize, use_color: bool) ProgressBar {
        return .{
            .file = file,
            .total = total,
            .current = 0,
            .last_update = 0,
            .update_interval_ns = update_interval,
            .use_color = use_color,
            .is_tty = file.isTty(),
        };
    }

    /// Update progress
    pub fn update(self: *ProgressBar, current: usize) !void {
        self.current = current;

        // Only update if enough time has passed or we're at 100%
        const now = std.time.nanoTimestamp();
        if (current < self.total and (now - self.last_update) < self.update_interval_ns) {
            return;
        }
        self.last_update = now;

        try self.render();
    }

    /// Increment progress by one
    pub fn increment(self: *ProgressBar) !void {
        try self.update(self.current + 1);
    }

    /// Render the progress bar
    fn render(self: ProgressBar) !void {
        if (!self.is_tty) {
            // Don't show progress bar if not a TTY
            return;
        }

        const percent = if (self.total > 0)
            (@as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total))) * 100.0
        else
            0.0;

        const filled = if (self.total > 0)
            (@as(usize, @intFromFloat((@as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total))) * @as(f64, bar_width))))
        else
            0;

        // Move cursor to beginning of line
        try self.file.writeAll("\r");

        // Draw progress bar
        if (self.use_color) {
            try self.file.writeAll("\x1b[36m"); // Cyan
        }
        try self.file.writeAll("[");

        var i: usize = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled) {
                try self.file.writeAll("█");
            } else {
                try self.file.writeAll(" ");
            }
        }

        try self.file.writeAll("]");
        if (self.use_color) {
            try self.file.writeAll("\x1b[0m"); // Reset
        }

        // Show percentage and count
        var buf: [256]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, " {d:>3.0}% ({d}/{d})", .{
            percent,
            self.current,
            self.total,
        });
        try self.file.writeAll(msg);
    }

    /// Finish and clear the progress bar
    pub fn finish(self: *ProgressBar) !void {
        if (!self.is_tty) return;

        // Update to 100%
        self.current = self.total;
        try self.render();

        // Move to next line
        try self.file.writeAll("\n");
    }

    /// Clear the progress bar from the terminal
    pub fn clear(self: ProgressBar) !void {
        if (!self.is_tty) return;

        // Move cursor to beginning and clear line
        try self.file.writeAll("\r\x1b[K");
    }
};

/// Simple spinner for indeterminate progress
pub const Spinner = struct {
    file: std.fs.File,
    frames: []const []const u8,
    current_frame: usize,
    last_update: i64,
    update_interval_ns: i64,
    use_color: bool,
    is_tty: bool,

    const default_frames = [_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };
    const update_interval = 80 * std.time.ns_per_ms; // 80ms

    /// Initialize spinner
    pub fn init(file: std.fs.File, use_color: bool) Spinner {
        return .{
            .file = file,
            .frames = &default_frames,
            .current_frame = 0,
            .last_update = 0,
            .update_interval_ns = update_interval,
            .use_color = use_color,
            .is_tty = file.isTty(),
        };
    }

    /// Update and render spinner
    pub fn spin(self: *Spinner) !void {
        if (!self.is_tty) return;

        const now = std.time.nanoTimestamp();
        if ((now - self.last_update) < self.update_interval_ns) {
            return;
        }
        self.last_update = now;

        // Move cursor to beginning
        try self.file.writeAll("\r");

        // Draw spinner
        if (self.use_color) {
            try self.file.writeAll("\x1b[36m"); // Cyan
        }
        try self.file.writeAll(self.frames[self.current_frame]);
        if (self.use_color) {
            try self.file.writeAll("\x1b[0m"); // Reset
        }

        // Advance frame
        self.current_frame = (self.current_frame + 1) % self.frames.len;
    }

    /// Finish and clear the spinner
    pub fn finish(self: Spinner) !void {
        if (!self.is_tty) return;
        try self.file.writeAll("\r\x1b[K");
    }
};

// Tests
test "ProgressBar: init" {
    const stdout_file = std.fs.File.stdout();
    const bar = ProgressBar.init(stdout_file, 100, false);

    try std.testing.expectEqual(@as(usize, 100), bar.total);
    try std.testing.expectEqual(@as(usize, 0), bar.current);
    try std.testing.expectEqual(false, bar.use_color);
}

test "ProgressBar: update" {
    const stdout_file = std.fs.File.stdout();
    var bar = ProgressBar.init(stdout_file, 100, false);

    bar.current = 50;
    try std.testing.expectEqual(@as(usize, 50), bar.current);
}

test "Spinner: init" {
    const stdout_file = std.fs.File.stdout();
    const spinner = Spinner.init(stdout_file, false);

    try std.testing.expectEqual(@as(usize, 0), spinner.current_frame);
    try std.testing.expectEqual(false, spinner.use_color);
}
