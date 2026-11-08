require 'json'
require 'set'
require_relative 'errors'
require_relative 'ast'
require_relative 'translator'
require_relative 'evaluator'
require_relative 'lexer'
require_relative 'parser'

# What one cell remembers:
#   source - exactly what the user typed (starts with = for code)
#   ast    - the tree it became (a primitive for plain values)
#   value  - the primitive the tree last evaluated to (nil if it failed)
#   output - text collected from print statements during the last evaluation
#   error  - the SpreadsheetError the last evaluation (or parse) raised, if any
Cell = Struct.new(:source, :ast, :value, :output, :error)

# The executing program's environment: the grid (so rvalues and statistical
# functions can reach other cells), the local variables, and the output
# buffer that print writes to. A new Runtime is created for each evaluation,
# so variables and output stay local to that evaluation.
class Runtime
  attr_reader :grid, :variables, :output

  def initialize(grid)
    @grid = grid
    @variables = {}
    @output = +''
  end

  def print_line(text)
    @output << text << "\n"
  end

  def set_variable(name, primitive)
    @variables[name] = primitive
  end

  def get_variable(name)
    @variables.fetch(name) { raise UndefinedVariableError, "Variable '#{name}' is not defined" }
  end
end

class Grid
  def initialize
    # Sparse storage: a Hash keyed by [col, row] only spends memory on cells
    # that exist, and an absent key is exactly what "empty cell" means.
    @cells = {}
    @stale = Set.new      # formula cells that need re-evaluating
    @evaluating = Set.new # formula cells being evaluated right now (cycle detection)
  end

  # --- Programmatic API (Milestone 1) ---------------------------------------

  # Evaluate the tree first, then store. If evaluation raises, the cell keeps
  # whatever it held before, so a bad edit can't corrupt the grid.
  def set(address, ast, source = nil)
    runtime = Runtime.new(self)
    value = Evaluator.new(runtime).evaluate(ast)
    source ||= source_for(ast)
    @cells[[address.col, address.row]] = Cell.new(source, ast, value, runtime.output, nil)
    recalculate
    value
  end

  # Raises EmptyCellError for an empty cell, and EvaluationError if the cell
  # holds an error, so a broken cell breaks everything that reads it.
  def get_primitive(address)
    key = [address.col, address.row]
    cell = @cells[key]
    raise EmptyCellError, "Cell (#{address.col}, #{address.row}) is empty" if cell.nil?

    if @evaluating.include?(key)
      raise CircularReferenceError, "Cell (#{address.col}, #{address.row}) depends on itself"
    end

    refresh(key)
    if cell.error
      raise EvaluationError,
            "Cell (#{address.col}, #{address.row}) contains an error: #{cell.error.message}"
    end

    cell.value
  end

  def cell(address)
    @cells[[address.col, address.row]]
  end

  # --- Text API (Milestone 3: what the user interface calls) -----------------

  def cell_at(col, row)
    @cells[[col, row]]
  end

  # Store whatever the user typed into a cell. Blank text empties the cell.
  # A bad formula is stored too (with its error) so the user can fix it.
  def enter(col, row, text, recalc: true)
    if text.nil? || text.strip.empty?
      @cells.delete([col, row])
    else
      @cells[[col, row]] = build_cell(text)
    end
    recalculate if recalc
  end

  # Re-evaluate every formula. Cells read each other lazily, so a cell is
  # always evaluated after the cells it depends on, however they are laid
  # out. A change anywhere therefore updates every dependent cell.
  def recalculate
    @stale = Set.new(@cells.select { |_, cell| formula?(cell) }.keys)
    @cells.keys.each { |key| refresh(key) }
  end

  # Re-evaluate just one cell's tree (used when it is selected).
  def reevaluate(col, row)
    key = [col, row]
    return unless formula?(@cells[key])

    @stale << key
    refresh(key)
  end

  # --- Files -------------------------------------------------------------------

  def save_file(path)
    cells = @cells.sort.map { |(col, row), cell| { 'col' => col, 'row' => row, 'source' => cell.source } }
    temp = "#{path}.tmp"
    File.write(temp, JSON.pretty_generate({ 'cells' => cells }) + "\n")
    File.rename(temp, path)
  end

  def load_file(path)
    data = JSON.parse(File.read(path))
    entries = data.is_a?(Hash) ? data['cells'] : nil
    raise SpreadsheetError, "#{path} is not a spreadsheet file" unless entries.is_a?(Array)

    entries.each do |entry|
      valid = entry.is_a?(Hash) && entry['col'].is_a?(Integer) && entry['row'].is_a?(Integer) &&
              entry['source'].is_a?(String)
      raise SpreadsheetError, "#{path} has a malformed cell entry" unless valid

      enter(entry['col'], entry['row'], entry['source'], recalc: false)
    end
    recalculate
  rescue JSON::ParserError => e
    raise SpreadsheetError, "#{path} is not valid JSON: #{e.message.lines.first.strip}"
  end

  private

  def formula?(cell)
    !cell.nil? && !cell.ast.nil? && !cell.ast.is_a?(Ast::Primitive)
  end

  def source_for(ast)
    return ast.raw_value if ast.is_a?(Ast::String)
    return Translator.new.translate(ast) if ast.is_a?(Ast::Primitive)

    "=#{Translator.new.translate(ast)}"
  end

  # = starts code; otherwise integer, float, boolean, or plain string.
  def build_cell(text)
    if text.start_with?('=')
      begin
        ast = Parser.new(Lexer.new(text[1..]).lex).parse
        Cell.new(text, ast, nil, '', nil)
      rescue SpreadsheetError => e
        Cell.new(text, nil, nil, '', e)
      end
    else
      primitive = primitive_for(text)
      Cell.new(text, primitive, primitive, '', nil)
    end
  end

  def primitive_for(text)
    stripped = text.strip
    case stripped
    when /\A[+-]?\d+\z/ then Ast::Integer.new(stripped.to_i)
    when /\A[+-]?\d+\.\d+\z/ then Ast::Float.new(stripped.to_f)
    when 'true' then Ast::Boolean.new(true)
    when 'false' then Ast::Boolean.new(false)
    else Ast::String.new(text)
    end
  end

  # Evaluate one stale formula cell. Never raises: failures land in the cell.
  def refresh(key)
    return unless @stale.delete?(key)

    cell = @cells[key]
    runtime = Runtime.new(self)
    @evaluating << key
    begin
      cell.value = Evaluator.new(runtime).evaluate(cell.ast)
      cell.error = nil
    rescue SpreadsheetError, RangeError => e
      cell.value = nil
      cell.error = e
    ensure
      cell.output = runtime.output
      @evaluating.delete(key)
    end
  end
end
