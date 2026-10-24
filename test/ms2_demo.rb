require 'minitest/autorun'
require_relative '../lib/grid'
require_relative '../lib/lexer'
require_relative '../lib/parser'

class Ms2Test < Minitest::Test
  def setup
    @grid = Grid.new
    set_cell(0, 0, 1)
    set_cell(0, 1, 2)
    set_cell(1, 0, 3)
    set_cell(1, 1, 4)
    set_cell(2, 0, 5)
    set_cell(2, 1, 6)
  end

  def set_cell(col, row, value)
    @grid.set(Ast::Address.new([col, row]), Ast::Integer.new(value))
  end

  def run_source(src)
    ast = Parser.new(Lexer.new(src).lex).parse
    Evaluator.new(Runtime.new(@grid)).evaluate(ast).raw_value
  end

  def test_good
    assert_equal 1, run_source('(5 + 2) * 3 % 4')
    assert_equal true, run_source('true == !!!false')
    assert_equal 4, run_source('#[0, 0] + 3')
    assert_equal true, run_source('#[1 - 1, 0] < #[1 * 1 - 1, 1]')
    assert_equal true, run_source('(5 > 3) && !(2 > 8)')
    assert_equal 2.5, run_source('float(10) / 4.0')
    assert_equal 512, run_source('2 ** 3 ** 2')
    assert_equal 44, run_source('45 & ---(1 + 3)') # 45 & -4
    assert_equal 22, run_source('1 + sum([0, 0], [2, 1])')
  end

  def test_lexer_errors
    ['$money', '40ish', '1.2.3.4.5'].each do |s|
      assert_raises(LexerError) { Lexer.new(s).lex }
    end
  end

  def test_parser_errors
    ['#[5]', '5 + 6 8', '----', '()', 'sum()'].each do |s|
      assert_raises(ParserError) { Parser.new(Lexer.new(s).lex).parse }
    end
  end

  def test_error_messages
    e = assert_raises(ParserError) { Parser.new(Lexer.new('5 + 6 8').lex).parse }
    assert_match(/Unexpected token '8'/, e.message)
    e = assert_raises(LexerError) { Lexer.new('$money').lex }
    assert_match(/Unexpected character '\$'/, e.message)
  end
end