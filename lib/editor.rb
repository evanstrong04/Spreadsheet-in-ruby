# A small multiline text buffer with a cursor. Pure Ruby (no curses) so it
# can be tested on its own; the UI just draws it and feeds it keystrokes.
class Editor
  attr_reader :lines, :row, :col

  def initialize(text = '')
    load(text)
  end

  # Replace the contents and put the cursor at the end.
  def load(text)
    @lines = text.to_s.split("\n", -1)
    @lines = [''] if @lines.empty?
    @row = @lines.length - 1
    @col = @lines[@row].length
  end

  def text
    @lines.join("\n")
  end

  def insert(chars)
    chars.to_s.each_char do |ch|
      if ch == "\n"
        newline
      else
        line = @lines[@row]
        @lines[@row] = line[0, @col] + ch + line[@col..]
        @col += 1
      end
    end
  end

  def newline
    line = @lines[@row]
    @lines[@row] = line[0, @col]
    @lines.insert(@row + 1, line[@col..])
    @row += 1
    @col = 0
  end

  def backspace
    if @col > 0
      line = @lines[@row]
      @lines[@row] = line[0, @col - 1] + line[@col..]
      @col -= 1
    elsif @row > 0
      previous = @lines[@row - 1]
      @col = previous.length
      @lines[@row - 1] = previous + @lines[@row]
      @lines.delete_at(@row)
      @row -= 1
    end
  end

  def delete
    line = @lines[@row]
    if @col < line.length
      @lines[@row] = line[0, @col] + line[@col + 1..]
    elsif @row < @lines.length - 1
      @lines[@row] = line + @lines[@row + 1]
      @lines.delete_at(@row + 1)
    end
  end

  def left
    if @col > 0
      @col -= 1
    elsif @row > 0
      @row -= 1
      @col = @lines[@row].length
    end
  end

  def right
    if @col < @lines[@row].length
      @col += 1
    elsif @row < @lines.length - 1
      @row += 1
      @col = 0
    end
  end

  def up
    return if @row.zero?

    @row -= 1
    @col = [@col, @lines[@row].length].min
  end

  def down
    return if @row >= @lines.length - 1

    @row += 1
    @col = [@col, @lines[@row].length].min
  end

  def home
    @col = 0
  end

  def end_of_line
    @col = @lines[@row].length
  end
end
