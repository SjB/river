// This file is part of river, a dynamic tiling wayland compositor.
//
// Copyright 2020 - 2023 The River Developers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const assert = std.debug.assert;

const globber = @import("globber");
const server = &@import("../main.zig").server;
const util = @import("../util.zig");

const Error = @import("../command.zig").Error;
const Seat = @import("../Seat.zig");

pub fn fetchView(seat: *Seat, args: []const [:0]const u8, _: *?[]const u8) Error!void {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    // If the fallback pseudo-output is focused, there is nowhere to send the view
    if (seat.focused_output == null) {
        assert(server.root.active_outputs.empty());
        return;
    }

    if (args[1].len == 0) return;

    const output = seat.focused_output orelse return;

    var it = server.root.views.iterator(.forward);

    while (it.next()) |view| {
        // we only want to know about the view that have and output
        if (view.current.output == null) continue;

        // we should never be searching for a view that doesn't have a title.
        const title = std.mem.span(view.getTitle()) orelse continue;

        if (globber.match(title, args[1])) {
            const new_tags = view.pending.tags | output.pending.tags;
            if (new_tags != 0) {
                view.pending.tags = new_tags;
            }
            if (output != view.current.output) {
                view.setPendingOutput(output);
            }
            seat.focus(view);
            server.root.applyPending();
            break;
        }
    }
}

pub fn listViewsDump(_: *Seat, _: []const [:0]const u8, out: *?[]const u8) Error!void {
    var buffer = std.ArrayList(u8).init(util.gpa);
    const writer = buffer.writer();

    var list = std.ArrayList(struct { appId: []const u8, title: []const u8, output: u8, tags: u32 }).init(util.gpa);

    var it = server.root.views.iterator(.forward);
    var maxIdSize: usize = 10;
    var maxTitleSize: usize = 10;

    while (it.next()) |view| {
        const appId = std.mem.span(view.getAppId()) orelse "";
        const title = std.mem.span(view.getTitle()) orelse "";
        const output: u8 = if (view.current.output == null) ' ' else '+';
        const tags = view.current.tags;

        try list.append(.{ .appId = appId, .title = title, .output = output, .tags = tags });
        if (appId.len > maxIdSize) maxIdSize = appId.len;
        if (title.len > maxTitleSize) maxTitleSize = title.len;
    }
    maxIdSize += 1;
    maxTitleSize += 1;

    try std.fmt.formatBuf("app-id", .{ .width = maxIdSize, .alignment = .left }, writer);
    try std.fmt.formatBuf("title", .{ .width = maxTitleSize, .alignment = .left }, writer);
    try std.fmt.formatBuf("tags", .{ .width = 5, .alignment = .left }, writer);
    try writer.writeAll("output");
    for (list.items) |el| {
        try writer.writeByte('\n');
        try std.fmt.formatBuf(el.appId, .{ .width = maxIdSize, .alignment = .left }, writer);
        try std.fmt.formatBuf(el.title, .{ .width = maxTitleSize, .alignment = .left }, writer);
        try writer.print("{d:<5}", .{el.tags});
        try writer.writeByte(el.output);
    }
    out.* = try buffer.toOwnedSlice();
}

pub fn listViews(_: *Seat, _: []const [:0]const u8, out: *?[]const u8) Error!void {
    var it = server.root.views.iterator(.forward);
    var buffer = std.ArrayList(u8).init(util.gpa);
    const writer = buffer.writer();

    while (it.next()) |view| {
        // we only want to know about the view that have and output
        if (view.current.output == null) continue;

        const title = std.mem.span(view.getTitle()) orelse continue;
        try writer.print("{s}\n", .{title});
    }
    out.* = try buffer.toOwnedSlice();
}
