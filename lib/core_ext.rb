class String
  def camelcase(*separators)
    case separators.first
      when Symbol, TrueClass, FalseClass, NilClass
        first_letter = separators.shift
    end

    separators = ['_'] if separators.empty?

    str = self.dup

    separators.each do |s|
      str = str.gsub(/(?:#{s}+)([a-z])/){ $1.upcase }
    end

    case first_letter
      when :upper, true
        str = str.gsub(/(\A|\s)([a-z])/){ $1 + $2.upcase }
      when :lower, false
        str = str.gsub(/(\A|\s)([A-Z])/){ $1 + $2.downcase }
    end

    str
  end

  def upper_camelcase(*separators)
    camelcase(:upper, *separators)
  end

  def lower_camelcase(*separators)
    camelcase(:lower, *separators)
  end

end
