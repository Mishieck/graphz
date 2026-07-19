const std = @import("std");
const testing = std.testing;
const heap = std.heap;
const debug = std.debug;
const graphz = @import("graphz");

pub fn main() !void {
    const G = graphz.graph.Graph(u8);
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var arena = heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var nodes = G.Nodes.init(allocator);
    defer nodes.deinit();
    try nodes.appendSlice(&.{ 0, 1, 2, 3, 4, 5, 6 });

    var edges = G.Edges.init(allocator);
    defer edges.deinit();
    try edges.appendSlice(&.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 1, 3 },
        .{ 1, 4 },
        .{ 2, 5 },
        .{ 2, 6 },
    });

    var graph = G{ .nodes = nodes, .edges = edges };

    const N = graphz.graph.Node(u8);
    var node = try N.fromGraph(arena.allocator(), graph);
    try testing.expectEqual(0, node.interface.data);
    try testing.expectEqual(0, node.data());
    graph = try node.toGraph(arena.allocator());

    try testing.expectEqual(nodes.items.len, graph.nodes.items.len);
    try testing.expectEqualSlices(u8, nodes.items, graph.nodes.items);

    try testing.expectEqual(edges.items.len, graph.edges.items.len);
    for (edges.items, 0..) |edge, i| try testing.expectEqualSlices(
        usize,
        &edge,
        &graph.edges.items[i],
    );
}
