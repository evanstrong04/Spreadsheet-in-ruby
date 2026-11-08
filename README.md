# Spreadsheet: Milestone 3 (Statements and Curses UI)

Ruby spreadsheet. Milestone 1 built the model (nodes, translator, evaluator,
grid, runtime). Milestone 2 added a lexer and parser. Milestone 3 adds
statements (`print`, assignment, variables, blocks) and a terminal user
interface built with Curses.

    source text -> Lexer -> tokens -> Parser -> AST -> Evaluator -> primitive

## Run

    gem install curses            # once, if the curses gem is missing
    ruby main.rb                  # empty spreadsheet, saves to spreadsheet.json
    ruby main.rb sample/demo.json # load a file; Ctrl-S writes back to it

    ruby test/ms1_demo.rb         # Milestone 1: hand-built trees
    ruby test/ms2_demo.rb         # Milestone 2: lexer and parser tests
    ruby test/ms3_demo.rb         # Milestone 3: statements, grid, file, editor

## Layout

- `main.rb`: entry point (reads the optional file argument)
- `lib/ast.rb`: expression and statement hierarchy
- `lib/translator.rb`: AST to source text
- `lib/evaluator.rb`: AST to primitive, with typechecking
- `lib/display.rb`: primitive to text (shared by `print` and the UI)
- `lib/grid.rb`: cells, grid, runtime (variables and output buffer), file I/O
- `lib/lexer.rb`, `lib/parser.rb`: text to tokens to AST
- `lib/editor.rb`: multiline text buffer (no curses, so it is unit tested)
- `lib/ui.rb`: the Curses interface
- `lib/errors.rb`: exception classes
- `grammar/grammar.txt`: the grammar the parser implements
- `sample/demo.json`: part of the demo spreadsheet, to load from a file

## Statements

    x = 7 ** 2
    y = 8 << 1
    print(x)
    print(y)
    x + y

A program is statements separated by line breaks. `print(e)` appends the text
of `e` plus a newline to the runtime's output buffer (never to stdout);
`x = e` stores a value in the runtime's variables; `x` reads it; a block
evaluates to its last statement (65 above, with output `49` and `16`).
Variables and output are local to one cell's evaluation. `=` is assignment and
`==` is equality. `print` is a statement, not an expression.

## Cell input rules

- Starts with `=`: the rest is code (lexed, parsed, evaluated). Put a newline
  after the `=` for a multiline program.
- Otherwise an integer, float, or `true`/`false` becomes that primitive.
- Anything else is a plain string.

A cell holding bad code keeps its text and shows `#ERR`; the expanded display
shows the error. Every edit re-evaluates all formulas, with cells evaluated
after the cells they read, so dependents always update. Circular references
are reported as `CircularReferenceError`.

## Keys

- Arrows, PgUp/PgDn: move (the grid scrolls forever in every direction)
- Type, or Enter: edit the selected cell. Enter or Tab commits, Ctrl-J starts
  a new line, Esc cancels
- Del or Backspace: clear the cell
- Ctrl-S: save to the file. Ctrl-Q: quit (asks twice if unsaved)

## Extra features

1. **Color:** numbers cyan, strings green, booleans yellow, errors bold red.
2. **Mouse navigation:** click selects a cell, double-click edits it, the
   wheel scrolls.

## File format

JSON: `{"cells": [{"col": 0, "row": 0, "source": "5.3"}, ...]}` where `source`
is exactly what was typed into the cell.
