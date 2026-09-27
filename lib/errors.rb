# One base class so later milestones can `rescue SpreadsheetError` and show a
# message in the cell instead of crashing, while real bugs still blow up.
class SpreadsheetError < StandardError; end

# An operation got operand types it can't work on (e.g. 7.5 << 2).
class TypeMismatchError < SpreadsheetError; end

# An rvalue or range pointed at a cell that has nothing in it.
class EmptyCellError < SpreadsheetError; end

# Types were fine but the operation itself is undefined (divide by zero, ...).
class EvaluationError < SpreadsheetError; end
