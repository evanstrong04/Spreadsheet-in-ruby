require_relative 'lib/grid'

GRID = Grid.new
TRANSLATOR = Translator.new

# Short builders so the trees below stay readable.
def int(n)    = Ast::Integer.new(n)
def flt(n)    = Ast::Float.new(n)
def bool(b)   = Ast::Boolean.new(b)
def str(s)    = Ast::String.new(s)
def lval(c, r) = Ast::CellLvalue.new(int(c), int(r))
def rval(c, r) = Ast::CellRvalue.new(int(c), int(r))

def addr(col, row) = Ast::Address.new([col, row])

# Translate first (so we can see the tree as source), then store it in the
# grid, which evaluates it. Any SpreadsheetError is caught and printed.
def run(label, col, row, ast)
  source = TRANSLATOR.translate(ast)
  value = GRID.set(addr(col, row), ast)
  puts format('%-28s %-38s => %s', label, source, value.raw_value.inspect)
rescue SpreadsheetError => e
  puts format('%-28s %-38s => ERROR (%s): %s', label, source, e.class, e.message)
end

def section(title)
  puts "\n=== #{title} ==="
end

# Seed cells that later expressions read through rvalues.
GRID.set(addr(3, 1), int(6))
GRID.set(addr(2, 1), int(7))
GRID.set(addr(2, 4), int(5))
GRID.set(addr(0, 0), int(1))
GRID.set(addr(0, 1), int(2))
# The statistical functions read every cell in the rectangle from (1, 2)
# to (5, 3), so all ten cells must be filled.
{ 2 => [2, 4, 3, 8, 5], 3 => [1, 7, 6, 9, 5] }.each do |row, values|
  values.each_with_index { |v, i| GRID.set(addr(i + 1, row), int(v)) }
end

section 'Required expressions'
run('arithmetic', 10, 1,
    Ast::Modulus.new(Ast::Add.new(Ast::Multiply.new(int(7), int(4)), int(3)), int(12)))
run('negation + rvalues', 10, 2,
    Ast::Multiply.new(rval(3, 1), Ast::Negate.new(rval(2, 1))))
run('rvalue lookup + shift', 10, 3,
    Ast::ShiftLeft.new(Ast::CellRvalue.new(Ast::Add.new(int(1), int(1)), int(4)), int(3)))
run('rvalue comparison', 10, 4,
    Ast::LessThan.new(rval(0, 0), rval(0, 1)))
run('logic + comparison', 10, 5,
    Ast::Not.new(Ast::GreaterThan.new(flt(3.3), flt(3.2))))
run('double negation', 10, 6,
    Ast::Negate.new(Ast::Negate.new(Ast::Multiply.new(int(6), int(8)))))
run('bitwise', 10, 7,
    Ast::BitwiseOr.new(Ast::BitwiseNot.new(int(5)), Ast::BitwiseNot.new(int(8))))
run('sum', 10, 8, Ast::Sum.new(lval(1, 2), lval(5, 3)))
run('mean', 10, 9, Ast::Mean.new(lval(1, 2), lval(5, 3)))
run('min', 10, 10, Ast::Min.new(lval(1, 2), lval(5, 3)))
run('max', 10, 11, Ast::Max.new(lval(1, 2), lval(5, 3)))
run('casting', 10, 12, Ast::Divide.new(Ast::IntToFloat.new(int(7)), flt(2.0)))

section 'Extra working cases'
run('string concat', 11, 1, Ast::Add.new(str('foo'), str('bar')))
run('string ordering', 11, 2, Ast::GreaterThanEqual.new(str('dog'), str('cat')))
run('float-to-int truncates', 11, 3, Ast::FloatToInt.new(flt(17.2)))
run('or short-circuits', 11, 4, Ast::Or.new(bool(true), rval(4, 15)))
run('and short-circuits', 11, 5, Ast::And.new(bool(false), rval(4, 15)))
run('equal via expression', 11, 6, Ast::Equal.new(int(5), Ast::Add.new(int(4), int(1))))
run('lvalue makes an address', 11, 7, lval(3, 4))

section 'Required failures'
run('float shift', 12, 1, Ast::ShiftLeft.new(flt(7.5), int(2)))
run('bool >= int', 12, 2, Ast::GreaterThanEqual.new(bool(true), int(10)))
run('string / int', 12, 3, Ast::Divide.new(str('fooo'), int(3)))

section 'More failures'
run('int + float', 13, 1, Ast::Add.new(int(5), flt(6.1)))
run('not on string', 13, 2, Ast::Not.new(str('bingo')))
run('bit-not on float', 13, 3, Ast::BitwiseNot.new(flt(2.5)))
run('and with int', 13, 4, Ast::And.new(bool(true), int(1)))
run('empty rvalue', 13, 5, Ast::Add.new(int(5), rval(3, 17)))
run('empty cell in range', 13, 6, Ast::Sum.new(lval(1, 2), lval(9, 9)))
run('divide by zero', 13, 7, Ast::Divide.new(int(1), int(0)))
run('negative int exponent', 13, 8, Ast::Exponentiate.new(int(2), int(-1)))
run('non-integer cell column', 13, 9, Ast::CellRvalue.new(flt(1.5), int(1)))
run('stat on a non-address', 13, 10, Ast::Sum.new(int(1), int(2)))

section 'A failed set leaves the old cell untouched'
GRID.set(addr(14, 1), int(99))
begin
  GRID.set(addr(14, 1), Ast::Divide.new(int(1), int(0)))
rescue SpreadsheetError => e
  puts "set raised #{e.class}"
end
puts "cell (14, 1) still holds #{GRID.get_primitive(addr(14, 1)).raw_value.inspect}"
