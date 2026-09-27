# frozen_string_literal: true

require_relative 'errors'
require_relative 'nodes'
require_relative 'translater'
require_relative 'evaluator'

# What one cell remembers: what was typed, the tree it became, and the
# primitive that tree last evaluated to.
Cell = Struct.new(:source, :ast, :value)

# The executing program's environment. For now that is just the grid, which
# rvalues and statistical functions need to reach other cells. Variables or
# a call stack would live here later.
class Runtime
  attr_reader :grid

  def initialize(grid)
    @grid = grid
  end
end

class Grid
  def initialize
    # Sparse storage: a Hash keyed by [col, row] only spends memory on cells
    # that exist, and an absent key is exactly what "empty cell" means.
    @cells = {}
    @runtime = Runtime.new(self)
  end

  # Evaluate the tree first, then store. If evaluation raises, the cell keeps
  # whatever it held before, so a bad edit can't corrupt the grid.
  def set(address, ast, source = nil)
    value = Evaluator.new(@runtime).evaluate(ast)
    source ||= Translater.new.translate(ast)
    @cells[[address.col, address.row]] = Cell.new(source, ast, value)
    value
  end

  def get(address)
    cell = @cells[[address.col, address.row]]
    raise EmptyCellError, "Cell (#{address.col}, #{address.row}) is empty" if cell.nil?

    cell.value
  end

  def cell(address)
    @cells[[address.col, address.row]]
  end
end
