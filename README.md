# Spreadsheet: Milestone 1 (Model)

Ruby model for a spreadsheet: expression nodes, a translater and an
evaluator (both visitors), a grid of cells, and a runtime.

## Run

    ruby ms1_demo.rb

Tested with Ruby 3.2. Requires Ruby 3.0 or newer.

## Layout

- `ms1_demo.rb`: builds trees by hand, translates and evaluates them
- `lib/nodes.rb`: expression hierarchy
- `lib/translater.rb`: AST to source text
- `lib/evaluator.rb`: AST to primitive, with typechecking
- `lib/grid.rb`: cells, grid, and runtime
- `lib/errors.rb`: custom exception classes