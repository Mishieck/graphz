run-examples:
  for e in examples/*; do zig build "example_$(basename -s .zig $e)"; done
