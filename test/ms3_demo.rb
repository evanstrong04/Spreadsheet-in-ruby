require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/grid'
require_relative '../lib/lexer'
require_relative '../lib/parser'
require_relative '../lib/editor'

PROGRAM = <<~SRC.freeze
  x = 7 ** 2
  y = 8 << 1
  print(x)
  print(y)
  x + y
SRC

class Ms3StatementTest < Minitest::Test
  def parse(src) = Parser.new(Lexer.new(src).lex).parse

  # Returns [value primitive, output text].
  def run_program(src, grid = Grid.new)
    runtime = Runtime.new(grid)
    value = Evaluator.new(runtime).evaluate(parse(src))
    [value, runtime.output]
  end

  def test_assignment_stores_and_returns_value
    runtime = Runtime.new(Grid.new)
    result = Evaluator.new(runtime).evaluate(parse('x = 7 ** 2'))
    assert_equal 49, result.raw_value
    assert_equal 49, runtime.variables['x'].raw_value
  end

  def test_variable_rvalue
    value, = run_program("n = 4\nn * n")
    assert_equal 16, value.raw_value
  end

  def test_print_collects_output_instead_of_writing_to_stdout
    value, output = nil
    out, = capture_io { value, output = run_program('print(1 + 2)') }
    assert_equal '', out
    assert_equal "3\n", output
    assert_equal 3, value.raw_value
  end

  def test_print_formats_each_type
    _, output = run_program("print(\"hi\")\nprint(2.5)\nprint(true)\nprint(null)\nprint([1, 2])")
    assert_equal "hi\n2.5\ntrue\nnull\n[1, 2]\n", output
  end

  def test_block_returns_last_statement_and_collects_output
    value, output = run_program(PROGRAM)
    assert_equal 65, value.raw_value
    assert_equal "49\n16\n", output
  end

  def test_blank_lines_and_leading_trailing_newlines_are_ignored
    value, = run_program("\n\nx = 1\n\n\nx + 1\n\n")
    assert_equal 2, value.raw_value
  end

  def test_single_statement_is_not_wrapped_in_a_block
    assert_instance_of Ast::Add, parse('1 + 2')
    assert_instance_of Ast::Block, parse("1\n2")
  end

  def test_variables_can_be_reassigned
    value, = run_program("x = 1\nx = x + 10\nx")
    assert_equal 11, value.raw_value
  end

  def test_assignment_uses_cells
    grid = Grid.new
    grid.enter(0, 0, '20')
    value, = run_program("a = #[0, 0]\na * 2", grid)
    assert_equal 40, value.raw_value
  end

  def test_undefined_variable
    assert_raises(UndefinedVariableError) { run_program('nope + 1') }
  end

  def test_type_errors_still_apply_inside_blocks
    assert_raises(TypeMismatchError) { run_program("x = 9\ny = false\nx << y") }
  end

  def test_equal_and_assign_are_different_tokens
    types = Lexer.new('x = 1 == 1').lex.map { |t| t[:type] }
    assert_equal %i[identifier assign integer_literal equal integer_literal], types
  end

  def test_identifiers_and_keywords
    types = Lexer.new("print(my_var2)\nprinter").lex.map { |t| t[:type] }
    assert_equal %i[print lparen identifier rparen newline identifier], types
  end

  def test_lexer_still_rejects_numbers_glued_to_words
    assert_raises(LexerError) { Lexer.new('40ish').lex }
  end

  def test_parser_errors
    ['x =', '= 5', 'print(1', 'print 1', "x = 1 2\n3", 'x y'].each do |src|
      assert_raises(ParserError, src) { parse(src) }
    end
  end

  def test_newline_in_error_message_is_readable
    error = assert_raises(ParserError) { parse("x =\n5") }
    assert_match(/end of line/, error.message)
  end

  def test_translator_round_trip
    translated = Translator.new.translate(parse(PROGRAM))
    assert_equal "x = (7 ** 2)\ny = (8 << 1)\nprint(x)\nprint(y)\n(x + y)", translated
    value, output = run_program(translated)
    assert_equal 65, value.raw_value
    assert_equal "49\n16\n", output
  end
end

class Ms3GridTest < Minitest::Test
  def setup
    @grid = Grid.new
  end

  def value(col, row) = @grid.cell_at(col, row).value
  def error(col, row) = @grid.cell_at(col, row).error

  def test_plain_text_classification
    { '42' => Ast::Integer, '-7' => Ast::Integer, '5.3' => Ast::Float, '-4.1' => Ast::Float,
      'true' => Ast::Boolean, 'false' => Ast::Boolean, 'hello' => Ast::String,
      '40ish' => Ast::String, '1.2.3' => Ast::String }.each do |text, type|
      @grid.enter(0, 0, text)
      assert_instance_of type, value(0, 0), text
    end
    @grid.enter(0, 0, '5.3')
    assert_equal 5.3, value(0, 0).raw_value
  end

  def test_equals_means_code
    @grid.enter(0, 0, '=1 + 2')
    assert_equal 3, value(0, 0).raw_value
  end

  def test_blank_input_clears_the_cell
    @grid.enter(0, 0, '5')
    @grid.enter(0, 0, '  ')
    assert_nil @grid.cell_at(0, 0)
  end

  def test_dependents_update_when_a_cell_changes
    @grid.enter(4, 0, '100')
    @grid.enter(4, 1, '3')
    @grid.enter(4, 2, '=#[4, 0] * #[4, 1]')
    assert_equal 300, value(4, 2).raw_value
    @grid.enter(4, 0, '7')
    assert_equal 21, value(4, 2).raw_value
    @grid.enter(4, 1, '10')
    assert_equal 70, value(4, 2).raw_value
  end

  def test_chains_update_regardless_of_cell_order
    # (0, 0) depends on (5, 5), which depends on (9, 9): evaluation order
    # must follow dependencies, not position.
    @grid.enter(0, 0, '=#[5, 5] + 1')
    @grid.enter(5, 5, '=#[9, 9] + 1')
    @grid.enter(9, 9, '1')
    assert_equal 3, value(0, 0).raw_value
    @grid.enter(9, 9, '10')
    assert_equal 12, value(0, 0).raw_value
  end

  def test_ranges_update
    @grid.enter(0, 0, '1')
    @grid.enter(1, 0, '2')
    @grid.enter(2, 0, '=sum([0, 0], [1, 0])')
    assert_equal 3, value(2, 0).raw_value
    @grid.enter(1, 0, '20')
    assert_equal 21, value(2, 0).raw_value
  end

  def test_errors_are_stored_and_propagate_then_clear
    @grid.enter(5, 0, '9')
    @grid.enter(5, 1, 'false')
    @grid.enter(5, 2, '=#[5, 0] << #[5, 1]')
    assert_instance_of TypeMismatchError, error(5, 2)
    @grid.enter(6, 2, '=#[5, 2] + 1')
    assert_instance_of EvaluationError, error(6, 2)
    @grid.enter(5, 1, '3')
    assert_nil error(5, 2)
    assert_equal 72, value(5, 2).raw_value
    assert_equal 73, value(6, 2).raw_value
  end

  def test_malformed_code_is_kept_with_its_error
    @grid.enter(0, 0, '=1 +')
    assert_instance_of ParserError, error(0, 0)
    assert_equal '=1 +', @grid.cell_at(0, 0).source
    @grid.enter(0, 1, '=$')
    assert_instance_of LexerError, error(0, 1)
  end

  def test_circular_references_do_not_hang
    @grid.enter(0, 0, '=#[1, 0]')
    @grid.enter(1, 0, '=#[0, 0]')
    refute_nil error(0, 0)
    refute_nil error(1, 0)
    @grid.enter(0, 0, '=#[0, 0] + 1')
    assert_instance_of CircularReferenceError, error(0, 0)
    @grid.enter(0, 0, '5')
    assert_nil error(1, 0)
    assert_equal 5, value(1, 0).raw_value
  end

  def test_program_in_a_cell_keeps_output
    @grid.enter(0, 0, "=\n#{PROGRAM}")
    assert_equal 65, value(0, 0).raw_value
    assert_equal "49\n16\n", @grid.cell_at(0, 0).output
  end

  def test_program_with_error_keeps_partial_output
    @grid.enter(0, 0, "=print(1)\nprint(1 / 0)")
    assert_instance_of EvaluationError, error(0, 0)
    assert_equal "1\n", @grid.cell_at(0, 0).output
  end

  def test_each_cell_has_its_own_variables
    @grid.enter(0, 0, "=x = 1\nx")
    @grid.enter(1, 0, '=x')
    assert_equal 1, value(0, 0).raw_value
    assert_instance_of UndefinedVariableError, error(1, 0)
  end

  def test_reevaluate_one_cell
    @grid.enter(0, 0, "=print(5)\n5")
    @grid.reevaluate(0, 0)
    assert_equal "5\n", @grid.cell_at(0, 0).output
  end

  def test_unbounded_coordinates
    @grid.enter(-3, 1_000_000, '7')
    @grid.enter(0, 0, '=#[-3, 1000000] + 1')
    assert_equal 8, value(0, 0).raw_value
  end

  def test_save_and_load_round_trip
    @grid.enter(0, 0, '5.3')
    @grid.enter(1, 0, 'hello')
    @grid.enter(2, 0, "=a = 2\na * 3")
    @grid.enter(3, 0, '=1 +')
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'sheet.json')
      @grid.save_file(path)
      other = Grid.new
      other.load_file(path)
      assert_equal 5.3, other.cell_at(0, 0).value.raw_value
      assert_equal 'hello', other.cell_at(1, 0).value.raw_value
      assert_equal 6, other.cell_at(2, 0).value.raw_value
      assert_instance_of ParserError, other.cell_at(3, 0).error
    end
  end

  def test_load_rejects_bad_files
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'bad.json')
      File.write(path, '{not json')
      assert_raises(SpreadsheetError) { Grid.new.load_file(path) }
      File.write(path, '{"cells": [{"col": "a"}]}')
      assert_raises(SpreadsheetError) { Grid.new.load_file(path) }
    end
  end

  def test_demo_sheet_file
    grid = Grid.new
    grid.load_file(File.join(__dir__, '..', 'sample', 'demo.json'))
    get = ->(c, r) { grid.cell_at(c, r).value.raw_value }
    assert_equal(-4.1, get.call(0, 3))
    assert_equal 10.8, get.call(1, 3)
    assert_in_delta 13.9, get.call(2, 3), 1e-9
    assert_in_delta 13.9 / 6, get.call(3, 3), 1e-9
    assert_equal 300, get.call(4, 2)
  end
end

class Ms3EditorTest < Minitest::Test
  def test_typing_and_cursor
    e = Editor.new
    e.insert('ab')
    e.left
    e.insert('X')
    assert_equal 'aXb', e.text
    assert_equal 2, e.col
  end

  def test_newline_splits_and_backspace_joins
    e = Editor.new('hello')
    e.left
    e.left
    e.newline
    assert_equal "hel\nlo", e.text
    assert_equal [1, 0], [e.row, e.col]
    e.backspace
    assert_equal 'hello', e.text
    assert_equal [0, 3], [e.row, e.col]
  end

  def test_up_down_clamp_column
    e = Editor.new("long line\nhi")
    assert_equal [1, 2], [e.row, e.col]
    e.up
    assert_equal [0, 2], [e.row, e.col]
    e.end_of_line
    e.down
    assert_equal [1, 2], [e.row, e.col]
  end

  def test_delete_and_load
    e = Editor.new("a\nb")
    e.up
    e.end_of_line
    e.delete
    assert_equal 'ab', e.text
    e.load('')
    assert_equal [''], e.lines
  end

  def test_insert_multiline_paste
    e = Editor.new
    e.insert("x = 1\nprint(x)")
    assert_equal "x = 1\nprint(x)", e.text
    assert_equal 1, e.row
  end
end
