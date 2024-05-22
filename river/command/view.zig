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

const View = @import("../View.zig");
const Error = @import("../command.zig").Error;
const Seat = @import("../Seat.zig");

const SearchField = enum {
    @"app-id",
    title,
    id,
};

fn match(s: []const u8, glob: []const u8) bool {
    globber.validate(glob) catch return std.mem.eql(u8, s, glob);
    return globber.match(s, glob);
}

fn viewById(id: []const u8) !?*View {
    if (id.len == 0) return Error.InvalidValue;

    var it = server.root.views.iterator(.forward);
    while (it.next()) |view| {
        if (std.mem.eql(u8, id, view.id)) return view;
    }
    return Error.InvalidValue;
}

fn viewByTitle(title: []const u8) !?*View {
    var it = server.root.views.iterator(.forward);
    while (it.next()) |view| {
        // we only want to know about the view that have and output
        if (view.current.output == null) continue;

        // we should never be searching for a view that doesn't have a title.
        const v_title = std.mem.sliceTo(view.getTitle(), 0) orelse continue;

        if (match(v_title, title)) return view;
    }
    return Error.InvalidValue;
}

fn viewByAppId(app_id: []const u8) !?*View {
    var it = server.root.views.iterator(.forward);
    while (it.next()) |view| {
        // we only want to know about the view that have and output
        if (view.current.output == null) continue;

        // we should never be searching for a view that doesn't have a title.
        const v_app_id = std.mem.sliceTo(view.getAppId(), 0) orelse continue;

        if (std.mem.eql(u8, v_app_id, app_id)) return view;
    }
    return Error.InvalidValue;
}

pub fn focusViewById(seat: *Seat, args: []const [:0]const u8, _: *?[]const u8) Error!void {
    if (args.len < 3) return Error.NotEnoughArguments;
    if (args.len > 3) return Error.TooManyArguments;

    // If the fallback pseudo-output is focused, there is nowhere to send the view
    if (seat.focused_output == null) {
        assert(server.root.active_outputs.empty());
        return;
    }

    const arg = std.meta.stringToEnum(SearchField, args[1]) orelse return Error.InvalidValue;

    const view = switch (arg) {
        .@"app-id" => try viewByAppId(args[2]),
        .title => try viewByTitle(args[2]),
        .id => try viewById(args[2]),
    } orelse return Error.InvalidValue;

    var output = view.current.output orelse return;

    if (output.pending.tags != view.pending.tags) {
        output.previous_tags = output.pending.tags;
        output.pending.tags = view.pending.tags;
    }

    if (seat.focused_output == null or seat.focused_output.? != output) {
        seat.focusOutput(output);
    }

    seat.focus(view);
    server.root.applyPending();
}

pub fn fetchViewById(seat: *Seat, args: []const [:0]const u8, _: *?[]const u8) Error!void {
    if (args.len < 3) return Error.NotEnoughArguments;
    if (args.len > 3) return Error.TooManyArguments;

    // If the fallback pseudo-output is focused, there is nowhere to send the view
    if (seat.focused_output == null) {
        assert(server.root.active_outputs.empty());
        return;
    }

    const arg = std.meta.stringToEnum(SearchField, args[1]) orelse return Error.InvalidValue;

    const view = switch (arg) {
        .@"app-id" => try viewByAppId(args[2]),
        .title => try viewByTitle(args[2]),
        .id => try viewById(args[2]),
    } orelse return Error.InvalidValue;

    const output = seat.focused_output orelse return;

    const new_tags = output.pending.tags;
    if (new_tags != 0) {
        view.pending.tags = new_tags;
    }

    if (output != view.current.output) {
        view.setPendingOutput(output);
    }

    seat.focus(view);
    server.root.applyPending();
}

pub fn listViews(_: *Seat, _: []const [:0]const u8, out: *?[]const u8) Error!void {
    const T = struct {
        id: []const u8,
        @"app-id": []const u8,
        title: []const u8,
        output: []const u8,
        tags: u32,
        float: bool,
        fullscreen: bool,
    };
    var list = std.ArrayList(T).init(util.gpa);

    var it = server.root.views.iterator(.forward);
    while (it.next()) |view| {
        // we only want to know about the view that have and output
        if (view.destroying) continue;

        const app_id = std.mem.sliceTo(view.getAppId(), 0) orelse continue;
        const title = std.mem.sliceTo(view.getTitle(), 0) orelse continue;

        const name = if (view.current.output) |output| std.mem.sliceTo(output.wlr_output.name, 0) else continue;

        const tags = view.current.tags;
        try list.append(.{
            .id = view.id,
            .@"app-id" = app_id,
            .title = title,
            .output = name,
            .tags = tags,
            .float = view.current.float,
            .fullscreen = view.current.fullscreen,
        });
    }

    var buffer = std.ArrayList(u8).init(util.gpa);
    const arr = try list.toOwnedSlice();
    try std.json.stringify(arr, .{}, buffer.writer());
    out.* = try buffer.toOwnedSlice();
}