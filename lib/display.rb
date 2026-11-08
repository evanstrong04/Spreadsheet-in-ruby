require_relative 'ast'

# How a primitive looks as text. Used by print and by the user interface so
# they agree on, e.g., how null and addresses are shown.
module Display
  def self.text(primitive)
    case primitive
    when nil then ''
    when Ast::Null then 'null'
    when Ast::Address then "[#{primitive.col}, #{primitive.row}]"
    else primitive.raw_value.to_s
    end
  end

  def self.type_name(primitive)
    return 'none' if primitive.nil?

    primitive.class.name.split('::').last.downcase
  end
end
