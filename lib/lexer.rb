require_relative 'errors'

# Chunks characters into tokens. It knows nothing about order, meaning, or
# the AST.
class Lexer
  def initialize(source)
    @source = source
    @i = 0
    @tokens = []
    @text_so_far = ''
  end

  def has(c)
    @i < @source.length && @source[@i] == c
  end

  def has_digit
    @i < @source.length && @source[@i] >= '0' && @source[@i] <= '9'
  end

  def has_letter
    @i < @source.length && ((@source[@i] >= 'a' && @source[@i] <= 'z') ||
                            (@source[@i] >= 'A' && @source[@i] <= 'Z'))
  end

  # Words start with a letter or underscore...
  def has_word_start
    has_letter || has('_')
  end

  # ...and continue with letters, digits, or underscores.
  def has_word_char
    has_word_start || has_digit
  end

  def capture
    @text_so_far += @source[@i]
    @i += 1
  end

  def emit_token(type)
    @tokens.push({ type: type, text: @text_so_far })
    @text_so_far = ''
  end

  def lex
    while @i < @source.length
      if has(' ') || has("\t") || has("\r")
        @i += 1
      elsif has("\n")
        # Newlines separate statements, so they are tokens now.
        capture
        emit_token(:newline)
      elsif has_digit
        while has_digit
          capture
        end
        if has('.')
          capture
          raise LexerError, "Expected a digit after '.' in number '#{@text_so_far}'" unless has_digit

          while has_digit
            capture
          end
          reject_trailing_word
          emit_token(:float_literal)
        else
          reject_trailing_word
          emit_token(:integer_literal)
        end
      elsif has_word_start
        while has_word_char
          capture
        end
        word_token
      elsif has('"')
        capture
        while @i < @source.length && !has('"')
          capture
        end
        raise LexerError, 'Unterminated string literal' unless has('"')

        capture
        emit_token(:string_literal)
      elsif has('+')
        capture
        emit_token(:plus)
      elsif has('-')
        capture
        emit_token(:minus)
      elsif has('*')
        capture
        if has('*')
          capture
          emit_token(:exponent)
        else
          emit_token(:multiply)
        end
      elsif has('/')
        capture
        emit_token(:slash)
      elsif has('%')
        capture
        emit_token(:percent)
      elsif has('&')
        capture
        if has('&')
          capture
          emit_token(:and)
        else
          emit_token(:bitwise_and)
        end
      elsif has('|')
        capture
        if has('|')
          capture
          emit_token(:or)
        else
          emit_token(:bitwise_or)
        end
      elsif has('^')
        capture
        emit_token(:bitwise_xor)
      elsif has('~')
        capture
        emit_token(:bitwise_not)
      elsif has('!')
        capture
        if has('=')
          capture
          emit_token(:not_equal)
        else
          emit_token(:not)
        end
      elsif has('=')
        capture
        if has('=')
          capture
          emit_token(:equal)
        else
          emit_token(:assign)
        end
      elsif has('<')
        capture
        if has('<')
          capture
          emit_token(:shift_left)
        elsif has('=')
          capture
          emit_token(:less_than_or_equal)
        else
          emit_token(:less_than)
        end
      elsif has('>')
        capture
        if has('>')
          capture
          emit_token(:shift_right)
        elsif has('=')
          capture
          emit_token(:greater_than_or_equal)
        else
          emit_token(:greater_than)
        end
      elsif has('(')
        capture
        emit_token(:lparen)
      elsif has(')')
        capture
        emit_token(:rparen)
      elsif has('[')
        capture
        emit_token(:lbracket)
      elsif has(']')
        capture
        emit_token(:rbracket)
      elsif has(',')
        capture
        emit_token(:comma)
      elsif has('#')
        capture
        emit_token(:hash)
      else
        raise LexerError, "Unexpected character '#{@source[@i]}' at position #{@i}"
      end
    end

    @tokens
  end

  private

  # Now that variables exist, "40ish" would lex as 40 followed by the name
  # ish. That is almost certainly a typo, so reject it here.
  def reject_trailing_word
    return unless has_word_start

    raise LexerError, "Invalid number '#{@text_so_far}#{@source[@i]}' at position #{@i - @text_so_far.length}"
  end

  # A finished word is either a keyword or a variable name.
  def word_token
    case @text_so_far
    when 'true'  then emit_token(:true)
    when 'false' then emit_token(:false)
    when 'null'  then emit_token(:null)
    when 'int'   then emit_token(:int)
    when 'float' then emit_token(:float)
    when 'sum'   then emit_token(:sum)
    when 'min'   then emit_token(:min)
    when 'max'   then emit_token(:max)
    when 'mean'  then emit_token(:mean)
    when 'print' then emit_token(:print)
    else emit_token(:identifier)
    end
  end
end
