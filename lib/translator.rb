# Visitor that turns an AST back into source text in the hypothetical syntax
# from the assignment: #[c, r] is an rvalue, [c, r] is an lvalue.
# Binary operations are fully parenthesized so the output is unambiguous
# without needing a precedence table.
class Translator
  def translate(node)
    node.visit(self)
  end

  # Primitives
  def visit_integer(n) = n.raw_value.to_s
  def visit_float(n)   = n.raw_value.to_s
  def visit_boolean(n) = n.raw_value.to_s
  def visit_string(n)  = n.raw_value.inspect
  def visit_null(_n)   = 'null'
  def visit_address(n) = "addr(#{n.col}, #{n.row})"

  # Arithmetic
  def visit_add(n)          = binary(n, '+')
  def visit_subtract(n)     = binary(n, '-')
  def visit_multiply(n)     = binary(n, '*')
  def visit_divide(n)       = binary(n, '/')
  def visit_modulus(n)      = binary(n, '%')
  def visit_exponentiate(n) = binary(n, '**')
  def visit_negate(n)       = unary(n, '-')

  # Logical
  def visit_and(n) = binary(n, '&&')
  def visit_or(n)  = binary(n, '||')
  def visit_not(n) = unary(n, '!')

  # Bitwise
  def visit_bitwise_and(n) = binary(n, '&')
  def visit_bitwise_or(n)  = binary(n, '|')
  def visit_bitwise_xor(n) = binary(n, '^')
  def visit_bitwise_not(n) = unary(n, '~')
  def visit_shift_left(n)  = binary(n, '<<')
  def visit_shift_right(n) = binary(n, '>>')

  # Relational
  def visit_equal(n)              = binary(n, '==')
  def visit_not_equal(n)          = binary(n, '!=')
  def visit_less_than(n)          = binary(n, '<')
  def visit_less_than_equal(n)    = binary(n, '<=')
  def visit_greater_than(n)       = binary(n, '>')
  def visit_greater_than_equal(n) = binary(n, '>=')

  # Casting
  def visit_float_to_int(n) = "int(#{translate(n.operand)})"
  def visit_int_to_float(n) = "float(#{translate(n.operand)})"

  # Cells
  def visit_cell_lvalue(n) = "[#{translate(n.col)}, #{translate(n.row)}]"
  def visit_cell_rvalue(n) = "#[#{translate(n.col)}, #{translate(n.row)}]"

  # Statistics
  def visit_max(n)  = range(n, 'max')
  def visit_min(n)  = range(n, 'min')
  def visit_mean(n) = range(n, 'mean')
  def visit_sum(n)  = range(n, 'sum')

  private

  def binary(node, op)
    "(#{translate(node.left)} #{op} #{translate(node.right)})"
  end

  def unary(node, op)
    "#{op}#{translate(node.operand)}"
  end

  def range(node, name)
    "#{name}(#{translate(node.first)}, #{translate(node.last)})"
  end
end
