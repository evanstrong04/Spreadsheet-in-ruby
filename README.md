# Spreadsheet: Milestone 2 (Lexer and Parser)

Ruby spreadsheet. Milestone 1 built the model: expression nodes, a translator
and an evaluator (both visitors), a grid of cells, and a runtime. Milestone 2
adds a lexer and a parser, so source text like `#[0, 0] + 3` can be turned
into tokens, then into an AST, then evaluated.

    source text -> Lexer -> tokens -> Parser -> AST -> Evaluator -> primitive

## Run

    ruby test/ms1_demo.rb    # Milestone 1: hand-built trees, translated and evaluated
    ruby test/ms2_demo.rb    # Milestone 2: minitest suite for the lexer and parser

## Layout

- `lib/ast.rb`: expression hierarchy
- `lib/translator.rb`: AST to source text
- `lib/evaluator.rb`: AST to primitive, with typechecking
- `lib/grid.rb`: cells, grid, and runtime
- `lib/lexer.rb`: source text to tokens (knows nothing about order or meaning)
- `lib/parser.rb`: tokens to AST (recursive descent, one method per grammar level)
- `lib/errors.rb`: custom exception classes (`LexerError`, `ParserError`, ...)
- `grammar.txt`: the grammar the parser implements
- `grammar/`: Treeformer screenshots of the grammar
- `test/ms1_demo.rb`: Milestone 1 demo
- `test/ms2_demo.rb`: Milestone 2 tests (good expressions, lexer errors, parser errors)

## Grammar notes

- Lowest to highest precedence: `||`, `&&`, `== !=`, `< <= > >=`,
  `& | ^`, `<< >>`, `+ -`, `* / %`, `**`, prefix `- ! ~`, then primitives,
  parentheses, cells, casts, and statistics.
- Binary operators are left associative, except `**`, which is right
  associative (`2 ** 3 ** 2` is `2 ** (3 ** 2)`).
- Bitwise operators bind tighter than comparisons, so `a & b == c` is
  `(a & b) == c`.
- Prefix operators bind tighter than `**`, so `-2 ** 2` is `(-2) ** 2`.
- `#[c, r]` is a cell rvalue (reads the cell); `[c, r]` is a cell lvalue
  (an address). Column and row can be any expression.
- `sum`, `min`, `max`, and `mean` take two lvalues: opposite corners of a
  rectangle of cells.

## Errors

All errors inherit from `SpreadsheetError`.

- `LexerError`: bad characters, unknown words, malformed numbers, unterminated strings
- `ParserError`: tokens in an order the grammar does not allow
- `TypeMismatchError`, `EmptyCellError`, `EvaluationError`: raised while evaluating