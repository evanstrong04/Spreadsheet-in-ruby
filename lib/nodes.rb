# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Milestone 1 model: the expression hierarchy.
# Every node has one job: hold its children and route a visitor to the right
# visit_* method (double dispatch). Nodes know nothing about translating or
# evaluating; that lives in the visitors.
# ---------------------------------------------------------------------------

class Node
  def accept(_visitor)
    raise NotImplementedError, "#{self.class} must implement accept"
  end
end

# --- Primitives -------------------------------------------------------------

class Primitive < Node
  attr_reader :value

  def initialize(value)
    @value = value
  end
end

class IntegerPrimitive < Primitive
  def accept(v) = v.visit_integer(self)
end

class FloatPrimitive < Primitive
  def accept(v) = v.visit_float(self)
end

class BooleanPrimitive < Primitive
  def accept(v) = v.visit_boolean(self)
end

class StringPrimitive < Primitive
  def accept(v) = v.visit_string(self)
end

class NullPrimitive < Primitive
  def initialize = super(nil)
  def accept(v) = v.visit_null(self)
end

# The result of evaluating a cell lvalue.
class AddressPrimitive < Primitive
  attr_reader :col, :row

  def initialize(col, row)
    @col = col
    @row = row
    super([col, row])
  end

  def accept(v) = v.visit_address(self)
end

# --- Shapes shared by the operators -----------------------------------------

class UnaryNode < Node
  attr_reader :operand

  def initialize(operand)
    @operand = operand
  end
end

class BinaryNode < Node
  attr_reader :left, :right

  def initialize(left, right)
    @left = left
    @right = right
  end
end

# --- Arithmetic (7) ---------------------------------------------------------

class Add         < BinaryNode; def accept(v) = v.visit_add(self);         end
class Subtract    < BinaryNode; def accept(v) = v.visit_subtract(self);    end
class Multiply    < BinaryNode; def accept(v) = v.visit_multiply(self);    end
class Divide      < BinaryNode; def accept(v) = v.visit_divide(self);      end
class Modulo      < BinaryNode; def accept(v) = v.visit_modulo(self);      end
class Exponentiate < BinaryNode; def accept(v) = v.visit_exponentiate(self); end
class Negate      < UnaryNode;  def accept(v) = v.visit_negate(self);      end

# --- Logical (3) ------------------------------------------------------------

class And < BinaryNode; def accept(v) = v.visit_and(self); end
class Or  < BinaryNode; def accept(v) = v.visit_or(self);  end
class Not < UnaryNode;  def accept(v) = v.visit_not(self); end

# --- Bitwise (6) ------------------------------------------------------------

class BitAnd     < BinaryNode; def accept(v) = v.visit_bit_and(self);     end
class BitOr      < BinaryNode; def accept(v) = v.visit_bit_or(self);      end
class BitXor     < BinaryNode; def accept(v) = v.visit_bit_xor(self);     end
class BitNot     < UnaryNode;  def accept(v) = v.visit_bit_not(self);     end
class ShiftLeft  < BinaryNode; def accept(v) = v.visit_shift_left(self);  end
class ShiftRight < BinaryNode; def accept(v) = v.visit_shift_right(self); end

# --- Relational (6) ---------------------------------------------------------

class Equal            < BinaryNode; def accept(v) = v.visit_equal(self);            end
class NotEqual         < BinaryNode; def accept(v) = v.visit_not_equal(self);        end
class LessThan         < BinaryNode; def accept(v) = v.visit_less_than(self);        end
class LessThanEqual    < BinaryNode; def accept(v) = v.visit_less_than_equal(self);  end
class GreaterThan      < BinaryNode; def accept(v) = v.visit_greater_than(self);     end
class GreaterThanEqual < BinaryNode; def accept(v) = v.visit_greater_than_equal(self); end

# --- Casting (2) ------------------------------------------------------------

class FloatToInt < UnaryNode; def accept(v) = v.visit_float_to_int(self); end
class IntToFloat < UnaryNode; def accept(v) = v.visit_int_to_float(self); end

# --- Cells ------------------------------------------------------------------

# Both hold two *expressions* (not plain numbers), so #[1 + 1, 4] works.
class CellLValue < Node
  attr_reader :col, :row

  def initialize(col, row)
    @col = col
    @row = row
  end

  def accept(v) = v.visit_cell_lvalue(self)
end

class CellRValue < Node
  attr_reader :col, :row

  def initialize(col, row)
    @col = col
    @row = row
  end

  def accept(v) = v.visit_cell_rvalue(self)
end

# --- Statistics (4) ---------------------------------------------------------
# Each takes two cell lvalues: opposite corners of a rectangle of cells.

class RangeNode < Node
  attr_reader :first, :last

  def initialize(first, last)
    @first = first
    @last = last
  end
end

class Max  < RangeNode; def accept(v) = v.visit_max(self);  end
class Min  < RangeNode; def accept(v) = v.visit_min(self);  end
class Mean < RangeNode; def accept(v) = v.visit_mean(self); end
class Sum  < RangeNode; def accept(v) = v.visit_sum(self);  end
