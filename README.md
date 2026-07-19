# Graphz

A Zig library for graphs.

## Features

### Data Structures

The data structures available include:

<dl>
  <dt><a href="./src/graph.zig">Graph</a></dt>
  <dd>
    A graph containing a list of nodes and list of edges. Each edge is a
    pair of indices. Each edge index is the index of its nodes in the nodes
    array.
  </dd>
  <dt><a href="./src/graph.zig">Node</a></dt>
  <dd>
    A node in a graph. It has a data property and neighbors property. The data
    property has the data associated with a node. The neighbors are the nodes it
    is connected to.
  </dd>
  <dt><a href="./src/tree.zig">TreeNode</a></dt>
  <dd>
    A node in a tree. It has a parent method, which returns a node or
    <code>null</code>. It also has a <code>children</code> method which returns
    the children of the node.
  </dd>
  <dt><a href="./src/traversal.zig">Traversal</a></dt>
  <dd>
    A traverser of graphs. It creates an iterable of nodes. The rules of
    traversal are determined by the nature of the graph and the
    <a href="#traversal">method</a>.
  </dd>
  <!--<dt><a href="./src/root.zig">ChainNode</a></dt>
  <dd>
    A node in a chain (doubly-linked list). It has <code>previous</code> and
    <code>next</code> properties, which maybe a node or <code>null</code>.
  </dd>
  <dt><a href="./src/root.zig">ListNode</a></dt>
  <dd>
    A node in a list (singly-linked list). It has a <code>next</code> property
    which maybe a node or <code>null</code>.
  </dd>-->
</dl>

### Traversal

The nodes support the following traversal algorithms:

<dl>
  <dt>breadth-first</dt>
  <dd>Level-order traversal.</dd>
  <dt>depth-first</dt>
  <dd>
    <ul>
      <li>post-order</li>
      <li>pre-order</li>
    </ul>
  </dd>
</dl>

## Installation

### Fetch

```sh
zig fetch --save git+https://github.com/mishieck/graphz
```

### Add Dependency

In `build.zig`, add the following:

```zig
const graphz = b.dependency("graphz", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("graphz", graphz.module("graphz"));
```

## Examples

- [Node](./examples/node.zig)
- [TreeNode](./examples/tree_node.zig)
- [Traversal](./examples/traversal.zig)
- [Graph-node Conversions](./examples/graph_node_conversions.zig)
