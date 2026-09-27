# ---------------------------------------------------------------------------
# Milestone 1 model: the expression hierarchy.
# Every node has one job: hold its children and route a visitor to the right
# visit_* method (double dispatch). Nodes know nothing about translating or
# evaluating; that lives in the visitors.
# ---------------------------------------------------------------------------

module Ast
  class Node
    def visit(_visitor)
      raise NotImplementedError, "#{self.class} must implement visit"
    end
  end

  # --- Primitives -------------------------------------------------------------

  class Primitive < Node
    attr_reader :raw_value

    def initialize(raw_value)
      @raw_value = raw_value
    end
  end

  class Integer < Primitive
    def visit(v) = v.visit_integer(self)
  end

  class Float < Primitive
    def visit(v) = v.visit_float(self)
  end

  class Boolean < Primitive
    def visit(v) = v.visit_boolean(self)
  end

  class String < Primitive
    def visit(v) = v.visit_string(self)
  end

  class Null < Primitive
    def initialize = super(nil)
    def visit(v) = v.visit_null(self)
  end

  # The result of evaluating a cell lvalue. Holds [col, row] as its raw_value,
  # the same shape the instructor's demo builds addresses from.
  class Address < Primitive
    def col = raw_value[0]
    def row = raw_value[1]

    def visit(v) = v.visit_address(self)
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

  class Add          < BinaryNode; def visit(v) = v.visit_add(self);          end
  class Subtract     < BinaryNode; def visit(v) = v.visit_subtract(self);     end
  class Multiply     < BinaryNode; def visit(v) = v.visit_multiply(self);     end
  class Divide       < BinaryNode; def visit(v) = v.visit_divide(self);       end
  class Modulus      < BinaryNode; def visit(v) = v.visit_modulus(self);      end
  class Exponentiate < BinaryNode; def visit(v) = v.visit_exponentiate(self); end
  class Negate       < UnaryNode;  def visit(v) = v.visit_negate(self);       end

  # --- Logical (3) -------------------------------------------------------------

  class And < BinaryNode; def visit(v) = v.visit_and(self); end
  class Or  < BinaryNode; def visit(v) = v.visit_or(self);  end
  class Not < UnaryNode;  def visit(v) = v.visit_not(self); end

  # --- Bitwise (6) ---------------------------------------------------------------

  class BitwiseAnd < BinaryNode; def visit(v) = v.visit_bitwise_and(self); end
  class BitwiseOr  < BinaryNode; def visit(v) = v.visit_bitwise_or(self);  end
  class BitwiseXor < BinaryNode; def visit(v) = v.visit_bitwise_xor(self); end
  class BitwiseNot < UnaryNode;  def visit(v) = v.visit_bitwise_not(self); end
  class ShiftLeft  < BinaryNode; def visit(v) = v.visit_shift_left(self);  end
  class ShiftRight < BinaryNode; def visit(v) = v.visit_shift_right(self); end

  # --- Relational (6) ------------------------------------------------------------

  class Equal            < BinaryNode; def visit(v) = v.visit_equal(self);              end
  class NotEqual         < BinaryNode; def visit(v) = v.visit_not_equal(self);          end
  class LessThan         < BinaryNode; def visit(v) = v.visit_less_than(self);          end
  class LessThanEqual    < BinaryNode; def visit(v) = v.visit_less_than_equal(self);    end
  class GreaterThan      < BinaryNode; def visit(v) = v.visit_greater_than(self);       end
  class GreaterThanEqual < BinaryNode; def visit(v) = v.visit_greater_than_equal(self); end

  # --- Casting (2) ---------------------------------------------------------------

  class FloatToInt < UnaryNode; def visit(v) = v.visit_float_to_int(self); end
  class IntToFloat < UnaryNode; def visit(v) = v.visit_int_to_float(self); end

  # --- Cells -----------------------------------------------------------------------

  # Both hold two *expressions* (not plain numbers), so #[1 + 1, 4] works.
  class CellLvalue < Node
    attr_reader :col, :row

    def initialize(col, row)
      @col = col
      @row = row
    end

    def visit(v) = v.visit_cell_lvalue(self)
  end

  class CellRvalue < Node
    attr_reader :col, :row

    def initialize(col, row)
      @col = col
      @row = row
    end

    def visit(v) = v.visit_cell_rvalue(self)
  end

  # --- Statistics (4) -------------------------------------------------------------
  # Each takes two cell lvalues: opposite corners of a rectangle of cells.

  class RangeNode < Node
    attr_reader :first, :last

    def initialize(first, last)
      @first = first
      @last = last
    end
  end

  class Max  < RangeNode; def visit(v) = v.visit_max(self);  end
  class Min  < RangeNode; def visit(v) = v.visit_min(self);  end
  class Mean < RangeNode; def visit(v) = v.visit_mean(self); end
  class Sum  < RangeNode; def visit(v) = v.visit_sum(self);  end
end
