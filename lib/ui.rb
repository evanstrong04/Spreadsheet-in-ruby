require 'curses'
require_relative 'grid'
require_relative 'editor'
require_relative 'display'

# Terminal user interface. Three windows are always visible:
#   * grid     (top)          labeled cells, each showing a truncated value
#   * editor   (bottom left)  multiline source of the selected cell
#   * display  (bottom right) the selected cell's value or error, and output
# plus a one-line status bar.
#
# Extra feature 1: color (value types and errors get their own colors).
# Extra feature 2: mouse navigation (click selects, double-click edits,
#                  wheel scrolls).
class SpreadsheetUI
  CELL_W = 10
  LABEL_W = 6
  MIN_LINES = 14
  MIN_COLS = 50

  # With nonl, Enter arrives as 13 and Ctrl-J as 10. Tab and Ctrl-X also
  # commit so the editor still works if a terminal sends Enter as 10.
  COMMIT_KEYS = [13, 9, 24].freeze
  NEWLINE_KEYS = [10, 15].freeze # Ctrl-J, Ctrl-O
  BACKSPACE_KEYS = [127, 8].freeze
  ESCAPE = 27
  CTRL_S = 19
  CTRL_Q = 17
  CTRL_C = 3

  # Some curses builds (notably the Windows one) don't define every key or
  # mouse constant, so look them up safely instead of naming them directly.
  def self.curses_const(name, fallback)
    Curses.const_defined?(name) ? Curses.const_get(name) : fallback
  end

  KEY_UP = curses_const(:KEY_UP, -1)
  KEY_DOWN = curses_const(:KEY_DOWN, -1)
  KEY_LEFT = curses_const(:KEY_LEFT, -1)
  KEY_RIGHT = curses_const(:KEY_RIGHT, -1)
  KEY_PPAGE = curses_const(:KEY_PPAGE, -1)
  KEY_NPAGE = curses_const(:KEY_NPAGE, -1)
  KEY_HOME = curses_const(:KEY_HOME, -1)
  KEY_END = curses_const(:KEY_END, -1)
  KEY_DC = curses_const(:KEY_DC, -1)
  KEY_ENTER = curses_const(:KEY_ENTER, -1)
  KEY_BACKSPACE = curses_const(:KEY_BACKSPACE, -1)
  KEY_RESIZE = curses_const(:KEY_RESIZE, -1)
  KEY_MOUSE = curses_const(:KEY_MOUSE, 539) # 539 is PDCurses' mouse key

  PAIR_NUMBER = 1
  PAIR_STRING = 2
  PAIR_BOOLEAN = 3
  PAIR_ERROR = 4
  PAIR_HEADER = 5

  def initialize(grid, path = nil)
    @grid = grid
    @path = path
    @sel_col = 0
    @sel_row = 0
    @top_col = 0 # column and row drawn in the grid's top-left corner
    @top_row = 0
    @vis_cols = 1
    @vis_rows = 1
    @mode = :grid # or :edit
    @editor = Editor.new
    @message = nil
    @dirty = false
    @quit_armed = false
    @click_mask = @double_mask = @wheel_up = @wheel_down = 0
  end

  def run
    ENV['ESCDELAY'] ||= '25'
    Curses.init_screen
    Curses.raw
    Curses.noecho
    Curses.nonl
    setup_colors
    setup_mouse
    build_windows
    loop do
      draw
      break if handle_key(read_key) == :quit
    end
  ensure
    Curses.close_screen
  end

  private

  # --- Setup ----------------------------------------------------------------

  def setup_colors
    @colors = Curses.has_colors?
    return unless @colors

    Curses.start_color
    background = begin
      Curses.use_default_colors
      -1
    rescue NoMethodError, NotImplementedError, Curses::Error
      Curses::COLOR_BLACK
    end
    Curses.init_pair(PAIR_NUMBER, Curses::COLOR_CYAN, background)
    Curses.init_pair(PAIR_STRING, Curses::COLOR_GREEN, background)
    Curses.init_pair(PAIR_BOOLEAN, Curses::COLOR_YELLOW, background)
    Curses.init_pair(PAIR_ERROR, Curses::COLOR_RED, background)
    Curses.init_pair(PAIR_HEADER, Curses::COLOR_BLUE, background)
  end

  def color(pair)
    @colors ? Curses.color_pair(pair) : 0
  end

  def setup_mouse
    return unless Curses.respond_to?(:mousemask) && Curses.const_defined?(:ALL_MOUSE_EVENTS)

    Curses.mousemask(Curses::ALL_MOUSE_EVENTS)
    @click_mask = mouse_flag(:BUTTON1_CLICKED) | mouse_flag(:BUTTON1_PRESSED)
    @double_mask = mouse_flag(:BUTTON1_DOUBLE_CLICKED)
    @wheel_up = mouse_flag(:BUTTON4_PRESSED)
    @wheel_down = mouse_flag(:BUTTON5_PRESSED)
  end

  def mouse_flag(name)
    Curses.const_defined?(name) ? Curses.const_get(name) : 0
  end

  def build_windows
    [@grid_win, @editor_win, @display_win, @status_win].compact.each(&:close)
    lines = Curses.lines
    cols = Curses.cols
    @small = lines < MIN_LINES || cols < MIN_COLS
    if @small
      @grid_win = @editor_win = @display_win = @status_win = nil
      @input = Curses.stdscr
    else
      bottom_h = [lines / 3, 8].max
      grid_h = lines - bottom_h - 1
      left_w = cols / 2
      @grid_win = Curses::Window.new(grid_h, cols, 0, 0)
      @editor_win = Curses::Window.new(bottom_h, left_w, grid_h, 0)
      @display_win = Curses::Window.new(bottom_h, cols - left_w, grid_h, left_w)
      @status_win = Curses::Window.new(1, cols, lines - 1, 0)
      @input = @grid_win
    end
    @input.keypad(true)
    Curses.clear
    Curses.refresh
    scroll_to_selection
  end

  # --- Input ----------------------------------------------------------------

  # Returns a one-character String for typed characters, or an Integer for
  # control codes and special keys. Newer and older versions of the curses
  # gem disagree on which getch returns, so normalize both here.
  def read_key
    key = @input.getch
    case key
    when String
      code = key.ord
      code >= 32 && code != 127 ? key : code
    when Integer
      if key >= 32 && key < 256 && key != 127
        key.chr(Encoding::UTF_8)
      else
        key
      end
    else
      key
    end
  end

  def handle_key(key)
    was_armed = @quit_armed
    @quit_armed = false
    @message = nil
    if key == KEY_RESIZE
      build_windows
      return nil
    end
    return handle_small_key(key) if @small

    @mode == :edit ? handle_edit_key(key) : handle_grid_key(key, was_armed)
  end

  def handle_small_key(key)
    [CTRL_Q, CTRL_C].include?(key) ? :quit : nil
  end

  def handle_grid_key(key, was_armed)
    case key
    when KEY_UP then move(0, -1)
    when KEY_DOWN then move(0, 1)
    when KEY_LEFT then move(-1, 0)
    when KEY_RIGHT then move(1, 0)
    when KEY_PPAGE then move(0, -@vis_rows)
    when KEY_NPAGE then move(0, @vis_rows)
    when KEY_MOUSE then handle_mouse
    when 13, 10, KEY_ENTER then start_edit
    when KEY_DC, KEY_BACKSPACE, *BACKSPACE_KEYS then clear_cell
    when CTRL_S then save
    when CTRL_Q, CTRL_C then return request_quit(was_armed)
    else
      # Typing any character starts a fresh entry, like a normal spreadsheet.
      start_edit(key) if key.is_a?(String)
    end
    nil
  end

  def handle_edit_key(key)
    case key
    when ESCAPE then @mode = :grid
    when *COMMIT_KEYS, KEY_ENTER then commit
    when *NEWLINE_KEYS then @editor.newline
    when *BACKSPACE_KEYS, KEY_BACKSPACE then @editor.backspace
    when KEY_DC then @editor.delete
    when KEY_LEFT then @editor.left
    when KEY_RIGHT then @editor.right
    when KEY_UP then @editor.up
    when KEY_DOWN then @editor.down
    when KEY_HOME then @editor.home
    when KEY_END then @editor.end_of_line
    else
      @editor.insert(key) if key.is_a?(String)
    end
    nil
  end

  def handle_mouse
    event = read_mouse_event
    return unless event

    if @wheel_up != 0 && (event.bstate & @wheel_up) != 0
      move(0, -3)
    elsif @wheel_down != 0 && (event.bstate & @wheel_down) != 0
      move(0, 3)
    elsif (event.bstate & (@click_mask | @double_mask)) != 0
      target = cell_at_screen(event.x, event.y)
      return unless target

      select_cell(*target)
      start_edit if @double_mask != 0 && (event.bstate & @double_mask) != 0
    end
  end

  # The curses gem prints an allocator warning the first time it builds a
  # mouse event, which would scribble over the screen. Silence it.
  def read_mouse_event
    return nil unless Curses.respond_to?(:getmouse)

    verbose = $VERBOSE
    $VERBOSE = nil
    Curses.getmouse
  ensure
    $VERBOSE = verbose
  end

  # Inverse of the drawing code: which cell is under this screen position?
  def cell_at_screen(x, y)
    return nil if x < 1 + LABEL_W || y < 2

    col_offset = (x - 1 - LABEL_W) / CELL_W
    row_offset = y - 2
    return nil if col_offset >= @vis_cols || row_offset >= @vis_rows

    [@top_col + col_offset, @top_row + row_offset]
  end

  # --- Actions --------------------------------------------------------------

  def move(d_col, d_row)
    select_cell(@sel_col + d_col, @sel_row + d_row)
  end

  # There are no bounds: the sparse grid accepts any integer coordinates, so
  # the viewport can scroll forever in every direction.
  def select_cell(col, row)
    @sel_col = col
    @sel_row = row
    @grid.reevaluate(col, row)
    scroll_to_selection
  end

  def scroll_to_selection
    @top_col = @sel_col if @sel_col < @top_col
    @top_col = @sel_col - @vis_cols + 1 if @sel_col >= @top_col + @vis_cols
    @top_row = @sel_row if @sel_row < @top_row
    @top_row = @sel_row - @vis_rows + 1 if @sel_row >= @top_row + @vis_rows
  end

  def start_edit(initial = nil)
    if initial
      @editor.load('')
      @editor.insert(initial)
    else
      cell = @grid.cell_at(@sel_col, @sel_row)
      @editor.load(cell ? cell.source : '')
    end
    @mode = :edit
  end

  def commit
    @grid.enter(@sel_col, @sel_row, @editor.text)
    @dirty = true
    @mode = :grid
  end

  def clear_cell
    @grid.enter(@sel_col, @sel_row, '')
    @dirty = true
  end

  def save
    @path ||= 'spreadsheet.json'
    @grid.save_file(@path)
    @dirty = false
    @message = "Saved to #{@path}"
  rescue SystemCallError => e
    @message = "Save failed: #{e.message}"
  end

  def request_quit(was_armed)
    return :quit if !@dirty || was_armed

    @quit_armed = true
    @message = 'Unsaved changes. Press Ctrl-Q again to quit without saving, or Ctrl-S to save.'
    nil
  end

  # --- Drawing ----------------------------------------------------------------

  def draw
    if @small
      Curses.clear
      Curses.setpos(0, 0)
      Curses.addstr("Terminal too small (need #{MIN_COLS}x#{MIN_LINES}). Ctrl-Q quits.")
      Curses.refresh
      return
    end

    [@grid_win, @editor_win, @display_win, @status_win].each(&:erase)
    draw_grid
    draw_display
    draw_status
    draw_editor # last, so the text cursor ends up in the editor
    [@grid_win, @display_win, @status_win, @editor_win].each(&:noutrefresh)
    Curses.doupdate
  end

  # Write text at (y, x), clipped so it never touches the window's last
  # column (which holds the border and would make curses complain).
  def put(win, y, x, text, attr = 0)
    room = win.maxx - x - 1
    return if room <= 0 || y < 0 || y >= win.maxy

    win.setpos(y, x)
    win.attron(attr) unless attr.zero?
    win.addstr(text[0, room])
    win.attroff(attr) unless attr.zero?
  end

  def frame(win, title)
    win.box('|', '-')
    put(win, 0, 2, " #{title} ", Curses::A_BOLD)
  end

  def draw_grid
    win = @grid_win
    frame(win, "Grid  (#{@sel_col}, #{@sel_row})")
    @vis_cols = [(win.maxx - 2 - LABEL_W) / CELL_W, 1].max
    @vis_rows = [win.maxy - 3, 1].max
    header = color(PAIR_HEADER) | Curses::A_BOLD

    @vis_cols.times do |i|
      col = @top_col + i
      attr = col == @sel_col ? Curses::A_REVERSE | header : header
      put(win, 1, 1 + LABEL_W + i * CELL_W, col.to_s.center(CELL_W - 1), attr)
    end

    @vis_rows.times do |j|
      row = @top_row + j
      attr = row == @sel_row ? Curses::A_REVERSE | header : header
      put(win, 2 + j, 1, "#{row.to_s.rjust(LABEL_W - 1)} ", attr)
      @vis_cols.times do |i|
        col = @top_col + i
        draw_cell(win, 2 + j, 1 + LABEL_W + i * CELL_W, @grid.cell_at(col, row),
                  col == @sel_col && row == @sel_row)
      end
    end
  end

  def draw_cell(win, y, x, cell, selected)
    text = fit(cell_text(cell), CELL_W - 1)
    text = numeric?(cell) ? text.rjust(CELL_W - 1) : text.ljust(CELL_W - 1)
    attr = cell_color(cell)
    attr |= Curses::A_REVERSE if selected
    put(win, y, x, text, attr)
  end

  def cell_text(cell)
    return '' if cell.nil?
    return '#ERR' if cell.error

    Display.text(cell.value).tr("\n", ' ')
  end

  def fit(text, width)
    text.length > width ? "#{text[0, width - 1]}~" : text
  end

  def numeric?(cell)
    cell && !cell.error && (cell.value.is_a?(Ast::Integer) || cell.value.is_a?(Ast::Float))
  end

  def cell_color(cell)
    return 0 if cell.nil?
    return color(PAIR_ERROR) | Curses::A_BOLD if cell.error

    case cell.value
    when Ast::Integer, Ast::Float then color(PAIR_NUMBER)
    when Ast::Boolean then color(PAIR_BOOLEAN)
    when Ast::String then color(PAIR_STRING)
    else 0
    end
  end

  def draw_editor
    win = @editor_win
    editing = @mode == :edit
    frame(win, editing ? 'Formula editor (editing)' : 'Formula editor')
    inner_h = win.maxy - 2
    inner_w = win.maxx - 2

    if editing
      lines = @editor.lines
      scroll_y = [@editor.row - inner_h + 1, 0].max
      scroll_x = [@editor.col - inner_w + 1, 0].max
    else
      cell = @grid.cell_at(@sel_col, @sel_row)
      lines = (cell ? cell.source : '').split("\n", -1)
      scroll_y = 0
      scroll_x = 0
    end

    (lines[scroll_y, inner_h] || []).each_with_index do |line, i|
      put(win, 1 + i, 1, line[scroll_x, inner_w] || '')
    end

    if editing
      Curses.curs_set(1)
      win.setpos(1 + @editor.row - scroll_y, 1 + @editor.col - scroll_x)
    else
      Curses.curs_set(0)
    end
  end

  def draw_display
    win = @display_win
    frame(win, 'Expanded display')
    inner_h = win.maxy - 2
    inner_w = win.maxx - 2
    shown = display_lines.flat_map do |text, attr|
      wrap(text, inner_w).map { |piece| [piece, attr] }
    end

    shown = shown.first(inner_h - 1) + [['...', 0]] if shown.length > inner_h
    shown.each_with_index { |(text, attr), i| put(win, 1 + i, 1, text, attr) }
  end

  def display_lines
    cell = @grid.cell_at(@sel_col, @sel_row)
    heading = color(PAIR_HEADER) | Curses::A_BOLD
    lines = [["Cell [#{@sel_col}, #{@sel_row}]", heading]]
    return lines + [['(empty)', 0]] if cell.nil?

    if cell.error
      lines << ["Error (#{cell.error.class}): #{cell.error.message}", color(PAIR_ERROR) | Curses::A_BOLD]
    else
      lines << ["Value: #{Display.text(cell.value)}  (#{Display.type_name(cell.value)})", cell_color(cell)]
    end
    lines << ['Output:', heading] << [cell.output.chomp, 0] unless cell.output.to_s.empty?
    lines
  end

  # Break text into pieces no wider than width, keeping explicit newlines.
  def wrap(text, width)
    width = [width, 1].max
    text.split("\n", -1).flat_map do |line|
      line.empty? ? [''] : line.scan(/.{1,#{width}}/)
    end
  end

  def draw_status
    win = @status_win
    if @message
      text = " #{@message}"
    elsif @mode == :edit
      text = ' EDIT  Enter/Tab: commit   Ctrl-J: new line   Esc: cancel'
    else
      file = @path || '(no file)'
      mark = @dirty ? ' [modified]' : ''
      text = " #{file}#{mark}  |  arrows/click: move  type or Enter: edit  Del: clear  ^S: save  ^Q: quit"
    end
    win.attron(Curses::A_REVERSE)
    win.setpos(0, 0)
    win.addstr(text.ljust(win.maxx - 1)[0, win.maxx - 1])
    win.attroff(Curses::A_REVERSE)
  end
end