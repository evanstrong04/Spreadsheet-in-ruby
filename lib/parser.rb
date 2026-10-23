require_relative 'errors'
require_relative 'ast'

class Parser
  def initialize(tokens)
    @tokens = tokens
    @i = 0
  end

  def parse
    raise ParserError, 'Empty expression' if @tokens.empty?

    node = expression
    if @i < @tokens.length
      raise ParserError, "Unexpected token '#{@tokens[@i][:text]}' after the end of the expression"
    end
    node
  end

  private

  def has(type)
    @i < @tokens.length && @tokens[@i][:type] == type
  end

  def advance
    raise ParserError, 'Unexpected end of input' if @i >= @tokens.length

    token = @tokens[@i]
    @i += 1
    token
  end

  def expect(type, description)
    unless has(type)
      found = @i < @tokens.length ? "'#{@tokens[@i][:text]}'" : 'end of input'
      raise ParserError, "Expected #{description} but found #{found}"
    end
    advance
  end

  def expression
    level0
  end

  # ||
  def level0
    left = level1
    while has(:or)
      advance
      left = Ast::Or.new(left, level1)
    end
    left
  end

  # &&
  def level1
    left = level2
    while has(:and)
      advance
      left = Ast::And.new(left, level2)
    end
    left
  end

  # == !=
  def level2
    left = level3
    while has(:equal) || has(:not_equal)
      if has(:equal)
        advance
        left = Ast::Equal.new(left, level3)
      else
        advance
        left = Ast::NotEqual.new(left, level3)
      end
    end
    left
  end

  # < <= > >=
  def level3
    left = level4
    while has(:less_than) || has(:less_than_or_equal) ||
          has(:greater_than) || has(:greater_than_or_equal)
      if has(:less_than)
        advance
        left = Ast::LessThan.new(left, level4)
      elsif has(:less_than_or_equal)
        advance
        left = Ast::LessThanEqual.new(left, level4)
      elsif has(:greater_than)
        advance
        left = Ast::GreaterThan.new(left, level4)
      else
        advance
        left = Ast::GreaterThanEqual.new(left, level4)
      end
    end
    left
  end

  # & | ^
  def level4
    left = level5
    while has(:bitwise_and) || has(:bitwise_or) || has(:bitwise_xor)
      if has(:bitwise_and)
        advance
        left = Ast::BitwiseAnd.new(left, level5)
      elsif has(:bitwise_or)
        advance
        left = Ast::BitwiseOr.new(left, level5)
      else
        advance
        left = Ast::BitwiseXor.new(left, level5)
      end
    end
    left
  end

  # << >>
  def level5
    left = level6
    while has(:shift_left) || has(:shift_right)
      if has(:shift_left)
        advance
        left = Ast::ShiftLeft.new(left, level6)
      else
        advance
        left = Ast::ShiftRight.new(left, level6)
      end
    end
    left
  end

  # + -
  def level6
    left = level7
    while has(:plus) || has(:minus)
      if has(:plus)
        advance
        left = Ast::Add.new(left, level7)
      else
        advance
        left = Ast::Subtract.new(left, level7)
      end
    end
    left
  end

  # * / %
  def level7
    left = level8
    while has(:multiply) || has(:slash) || has(:percent)
      if has(:multiply)
        advance
        left = Ast::Multiply.new(left, level8)
      elsif has(:slash)
        advance
        left = Ast::Divide.new(left, level8)
      else
        advance
        left = Ast::Modulus.new(left, level8)
      end
    end
    left
  end

  # ** recurses on the right so 2 ** 3 ** 2 is 2 ** (3 ** 2)
  def level8
    left = level9
    if has(:exponent)
      advance
      return Ast::Exponentiate.new(left, level8)
    end
    left
  end

  # prefix - ! ~
  def level9
    if has(:minus)
      advance
      Ast::Negate.new(level9)
    elsif has(:not)
      advance
      Ast::Not.new(level9)
    elsif has(:bitwise_not)
      advance
      Ast::BitwiseNot.new(level9)
    else
      level10
    end
  end

  # primitives, parens, cells, casts, statistics
  def level10
    if has(:integer_literal)
      Ast::Integer.new(advance[:text].to_i)
    elsif has(:float_literal)
      Ast::Float.new(advance[:text].to_f)
    elsif has(:string_literal)
      Ast::String.new(advance[:text][1..-2])
    elsif has(:true)
      advance
      Ast::Boolean.new(true)
    elsif has(:false)
      advance
      Ast::Boolean.new(false)
    elsif has(:null)
      advance
      Ast::Null.new
    elsif has(:lparen)
      advance
      inner = expression
      expect(:rparen, "')'")
      inner
    elsif has(:hash)
      advance
      lvalue = cell_lvalue
      Ast::CellRvalue.new(lvalue.col, lvalue.row)
    elsif has(:lbracket)
      cell_lvalue
    elsif has(:int)
      cast_to_int
    elsif has(:float)
      cast_to_float
    elsif has(:sum)
      statistic(:sum)
    elsif has(:min)
      statistic(:min)
    elsif has(:max)
      statistic(:max)
    elsif has(:mean)
      statistic(:mean)
    elsif @i >= @tokens.length
      raise ParserError, 'Unexpected end of input; expected a value'
    else
      raise ParserError, "Unexpected token '#{@tokens[@i][:text]}'; expected a value"
    end
  end

  def cell_lvalue
    expect(:lbracket, "'['")
    col = expression
    expect(:comma, "',' between column and row")
    row = expression
    expect(:rbracket, "']'")
    Ast::CellLvalue.new(col, row)
  end

  def cast_to_int
    advance
    expect(:lparen, "'(' after int")
    operand = expression
    expect(:rparen, "')'")
    Ast::FloatToInt.new(operand)
  end

  def cast_to_float
    advance
    expect(:lparen, "'(' after float")
    operand = expression
    expect(:rparen, "')'")
    Ast::IntToFloat.new(operand)
  end

  def statistic(kind)
    advance
    expect(:lparen, "'(' after #{kind}")
    first = cell_lvalue
    expect(:comma, "',' between the two cells")
    last = cell_lvalue
    expect(:rparen, "')'")
    if kind == :sum
      Ast::Sum.new(first, last)
    elsif kind == :min
      Ast::Min.new(first, last)
    elsif kind == :max
      Ast::Max.new(first, last)
    else
      Ast::Mean.new(first, last)
    end
  end
end