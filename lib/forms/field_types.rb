module Forms
  class FieldTypes
    TYPES = {
      text: "Text",
      number: "Number",
      date: "Date",
      select: "Select",
      checkbox: "Checkbox",
      radio: "Radio",
      textarea: "Text Area",
      file: "File Upload"
    }
    
    def self.all
      TYPES
    end
    
    def self.valid_type?(type)
      # Return false early if type is not a string or symbol
      return false unless type.is_a?(String) || type.is_a?(Symbol)
      TYPES.key?(type.to_sym)
    end
  end
end
