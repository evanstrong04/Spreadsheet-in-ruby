# frozen_string_literal: true

require_relative 'errors'
require_relative 'nodes'

# Visitor that reduces any AST to a single primitive node, typechecking each
# operation as it goes. Type rules:
#   * arithmetic: both operands integer OR both float (no mixed mode);
#                 + also joins two strings
#   * logical:    booleans only, and/or short-circuit
#   * bitwise:    integers only
#   * relational: both operands the same type; ordering (<, >=, ...) is only
#                 defined for numbers and strings
class Evaluator
  NUMERIC = [IntegerPrimitive, FloatPrimitive].freeze
  ORDERABLE = [IntegerPrimitive, FloatPrimitive, StringPrimitive].freeze

  def initialize(runtime)
    @runtime = runtime
  end

  def evaluate(node)
    node.accept(self)
  end

  # --- Primitives evaluate to themselves -----------------------------------

  def visit_integer(n) = n
  def visit_float(n)   = n
  def visit_boolean(n) = n
  def visit_string(n)  = n
  def visit_null(n)    = n
  def visit_address(n) = n

  # --- Arithmetic ----------------------------------------------------------

  def visit_add(n)
    l, r = operands(n)
    return StringPrimitive.new(l.value + r.value) if both?(StringPrimitive, l, r)

    arithmetic('+', l, r) { |a, b| a + b }
  end

  def visit_subtract(n)
    l, r = operands(n)
    arithmetic('-', l, r) { |a, b| a - b }
  end

  def visit_multiply(n)
    l, r = operands(n)
    arithmetic('*', l, r) { |a, b| a * b }
  end

  def visit_divide(n)
    l, r = operands(n)
    arithmetic('/', l, r) do |a, b|
      raise EvaluationError, 'Division by zero' if b.zero?

      a / b
    end
  end

  def visit_modulo(n)
    l, r = operands(n)
    arithmetic('%', l, r) do |a, b|
      raise EvaluationError, 'Modulo by zero' if b.zero?

      a % b
    end
  end

  def visit_exponentiate(n)
    l, r = operands(n)
    arithmetic('**', l, r) do |a, b|
      # Ruby quietly returns a Rational for 2 ** -1 and a Complex for
      # (-8.0) ** (1.0 / 3). Neither is a model primitive, so reject them.
      raise EvaluationError, 'Negative exponent on integers' if a.is_a?(Integer) && b.negative?

      result = a**b
      raise EvaluationError, 'Result of ** is not a real number' unless result.is_a?(Integer) || result.is_a?(Float)

      result
    end
  end

  def visit_negate(n)
    v = evaluate(n.operand)
    require_type('unary -', v, NUMERIC)
    v.class.new(-v.value)
  end

  # --- Logical (and/or short-circuit) --------------------------------------

  def visit_and(n)
    l = evaluate(n.left)
    require_type('&&', l, [BooleanPrimitive])
    return l unless l.value # false && anything is false; skip the right side

    r = evaluate(n.right)
    require_type('&&', r, [BooleanPrimitive])
    r
  end

  def visit_or(n)
    l = evaluate(n.left)
    require_type('||', l, [BooleanPrimitive])
    return l if l.value # true || anything is true; skip the right side

    r = evaluate(n.right)
    require_type('||', r, [BooleanPrimitive])
    r
  end

  def visit_not(n)
    v = evaluate(n.operand)
    require_type('!', v, [BooleanPrimitive])
    BooleanPrimitive.new(!v.value)
  end

  # --- Bitwise -------------------------------------------------------------

  def visit_bit_and(n) = bitwise('&', n) { |a, b| a & b }
  def visit_bit_or(n)  = bitwise('|', n) { |a, b| a | b }
  def visit_bit_xor(n) = bitwise('^', n) { |a, b| a ^ b }

  def visit_shift_left(n)
    bitwise('<<', n) do |a, b|
      raise EvaluationError, 'Negative shift amount' if b.negative?

      a << b
    end
  end

  def visit_shift_right(n)
    bitwise('>>', n) do |a, b|
      raise EvaluationError, 'Negative shift amount' if b.negative?

      a >> b
    end
  end

  def visit_bit_not(n)
    v = evaluate(n.operand)
    require_type('~', v, [IntegerPrimitive])
    IntegerPrimitive.new(~v.value)
  end

  # --- Relational ----------------------------------------------------------

  def visit_equal(n)     = relational('==', n, ordering: false) { |a, b| a == b }
  def visit_not_equal(n) = relational('!=', n, ordering: false) { |a, b| a != b }
  def visit_less_than(n)          = relational('<', n) { |a, b| a < b }
  def visit_less_than_equal(n)    = relational('<=', n) { |a, b| a <= b }
  def visit_greater_than(n)       = relational('>', n) { |a, b| a > b }
  def visit_greater_than_equal(n) = relational('>=', n) { |a, b| a >= b }

  # --- Casting -------------------------------------------------------------

  def visit_float_to_int(n)
    v = evaluate(n.operand)
    require_type('float-to-int', v, [FloatPrimitive])
    raise EvaluationError, "Cannot convert #{v.value} to an integer" unless v.value.finite?

    IntegerPrimitive.new(v.value.to_i) # truncates toward zero
  end

  def visit_int_to_float(n)
    v = evaluate(n.operand)
    require_type('int-to-float', v, [IntegerPrimitive])
    FloatPrimitive.new(v.value.to_f)
  end

  # --- Cells ---------------------------------------------------------------

  # Both column and row are expressions, so evaluate them, check they came
  # out as integers, and package them as an address primitive.
  def visit_cell_lvalue(n)
    col = evaluate(n.col)
    row = evaluate(n.row)
    require_type('cell column', col, [IntegerPrimitive])
    require_type('cell row', row, [IntegerPrimitive])
    AddressPrimitive.new(col.value, row.value)
  end

  def visit_cell_rvalue(n)
    @runtime.grid.get(visit_cell_lvalue(n)) # raises EmptyCellError if empty
  end

  # --- Statistics ----------------------------------------------------------

  def visit_sum(n)
    values = range_values('sum', n)
    values.first.class.new(values.sum(&:value))
  end

  def visit_min(n)
    range_values('min', n).min_by(&:value)
  end

  def visit_max(n)
    range_values('max', n).max_by(&:value)
  end

  def visit_mean(n)
    values = range_values('mean', n)
    FloatPrimitive.new(values.sum(&:value).to_f / values.size)
  end

  private

  def operands(node)
    [evaluate(node.left), evaluate(node.right)]
  end

  def both?(type, left, right)
    left.is_a?(type) && right.is_a?(type)
  end

  def type_name(primitive)
    primitive.class.name.sub('Primitive', '').downcase
  end

  def require_type(op, primitive, allowed)
    return if allowed.any? { |t| primitive.is_a?(t) }

    raise TypeMismatchError,
          "Operator #{op} cannot be applied to #{type_name(primitive)}"
  end

  def arithmetic(op, left, right)
    require_type(op, left, NUMERIC)
    require_type(op, right, NUMERIC)
    unless left.class == right.class
      raise TypeMismatchError,
            "Operator #{op} needs matching types, got #{type_name(left)} and #{type_name(right)}"
    end

    left.class.new(yield(left.value, right.value))
  end

  def bitwise(op, node)
    l, r = operands(node)
    require_type(op, l, [IntegerPrimitive])
    require_type(op, r, [IntegerPrimitive])
    IntegerPrimitive.new(yield(l.value, r.value))
  end

  def relational(op, node, ordering: true)
    l, r = operands(node)
    unless l.class == r.class
      raise TypeMismatchError,
            "Operator #{op} needs matching types, got #{type_name(l)} and #{type_name(r)}"
    end
    require_type(op, l, ORDERABLE) if ordering
    BooleanPrimitive.new(yield(l.value, r.value))
  end

  # Evaluate both corners, walk the rectangle between them, and return every
  # cell's primitive. All values must be numbers of one type.
  def range_values(op, node)
    a = evaluate(node.first)
    b = evaluate(node.last)
    require_type(op, a, [AddressPrimitive])
    require_type(op, b, [AddressPrimitive])

    values = ([a.col, b.col].min..[a.col, b.col].max).flat_map do |col|
      ([a.row, b.row].min..[a.row, b.row].max).map do |row|
        @runtime.grid.get(AddressPrimitive.new(col, row))
      end
    end

    values.each { |v| require_type(op, v, NUMERIC) }
    unless values.map(&:class).uniq.size == 1
      raise TypeMismatchError, "#{op} needs all cells in the range to have the same type"
    end

    values
  end
end
