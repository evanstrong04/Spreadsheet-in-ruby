# Usage: ruby main.rb [file.json]
# Loads the grid from the file (if it exists) and saves back to the same file.
require_relative 'lib/ui'

path = ARGV[0]
grid = Grid.new

begin
  grid.load_file(path) if path && File.exist?(path)
rescue SpreadsheetError, SystemCallError => e
  warn "Could not load #{path}: #{e.message}"
  exit 1
end

SpreadsheetUI.new(grid, path).run
