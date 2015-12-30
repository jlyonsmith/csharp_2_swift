require 'ostruct'
require 'optparse'
require 'colorize'

$VERSION='1.0.0-20151230.1'

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

class Csharp2Swift

  def initialize
    @renamed_vars = {}
    @renamed_methods = {}
  end

  def parse(args)
    options = OpenStruct.new
    options.output_filename = ''
    options.input_filename = nil
    options.convert_simple_for_loops = false

    opt_parser = OptionParser.new do |opts|
      opts.banner = %Q(Roughly Convert C# to Swift. Version #{$VERSION}
Copyright (c) John Lyon-Smith, 2015.
Usage:            #{File.basename(__FILE__)} [options] FILE
)
      opts.separator %Q(Description:
This tool does a rough conversion of C# source code to Swift.  The goal of the tool
is to do most of the easy stuff that simply requires a lot of typing effort, and allow you
to concentrate on the more difficult aspects of the conversion, such as library and
framework usage.
)
      opts.separator %Q(Options:
)

      opts.on("-o", "--output FILE", String, "The output file.  Default is the same as the input file.") do |file|
        options.output_filename = File.expand_path(file)
      end

      opts.on("--convert_simple_for_loops", "Convert simple range based for loops, e.g. for(int i = 0; i < 10; i++) { }",
        "to range based loops of the form for i in 0..<10 { }") do |convert|
        options.convert_simple_for_loops = convert
      end

      opts.on_tail("-?", "--help", "Show this message") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(args)
    options.input_filename = args.pop
    if options.input_filename == nil
      error 'Need to specify a file to process'
      exit
    end
    options.input_filename = File.expand_path(options.input_filename)
    options
  end

  def execute(args)
    options = self.parse(args)

    if !File.exist?(options.input_filename)
      error "File #{options.input_filename} does not exist"
      exit
    end

    if options.output_filename.length == 0
      error "An output file must be specified."
    end

    options.output_filename = File.expand_path(options.output_filename)
    content = read_file(options.input_filename)

    # Things that clean up the code and make other regex's easier
    remove_eol_semicolons(content)
    join_open_brace_to_last_line(content)
    remove_region(content)
    remove_endregion(content)
    remove_namespace_using(content)
    convert_this_to_self(content)
    convert_int_type(content)
    convert_string_type(content)
    convert_bool_type(content)
    convert_float_type(content)
    convert_double_type(content)
    convert_list_list_type(content)
    convert_list_array_type(content)
    convert_list_type(content)
    convert_debug_assert(content)
    remove_new(content)

    # Slightly more complicated stuff
    remove_namespace(content)
    convert_property(content)
    remove_get_set(content)
    convert_const_field(content)
    convert_field(content)
    constructors_to_inits(content)
    convert_method_decl_to_func_decl(content)
    convert_locals(content)
    convert_if(content)
    convert_next_line_else(content)

    # Optional stuff
    convert_simple_range_for_loop(content) if options.convert_simple_for_loops

    # Global search/replace
    @renamed_vars.each { |v, nv|
      content.gsub!(Regexp.new("\\." + v + "\\b"), '.' + nv)
    }
    @renamed_methods.each { |m, nm|
      content.gsub!(Regexp.new('\\b' + m + '\\('), nm + '(')
    }

    write_file(options.output_filename, content)

    puts "\"#{options.input_filename}\" -> \"#{options.output_filename}\""

    @renamed_vars.each {|k,v| puts k + ' -> ' + v}
    @renamed_methods.each {|k,v| puts k + '() -> ' + v + '()'}
  end

  def remove_eol_semicolons(content)
    content.gsub!(/; *$/m, '')
  end

  def join_open_brace_to_last_line(content)
    re = / *\{$/m
    m = re.match(content)
    s = ' {'

    while m != nil do
      offset = m.offset(0)
      start = offset[0]
      content.slice!(offset[0]..offset[1])
      content.insert(start - 1, s)
      m = re.match(content, start - 1 + s.length)
    end
  end

  def convert_this_to_self(content)
    content.gsub!(/this\./, 'self.')
  end

  def remove_region(content)
    content.gsub!(/ *#region.*\n/, '')
  end

  def remove_endregion(content)
    content.gsub!(/ *#endregion.*\n/, '')
  end

  def remove_namespace_using(content)
    content.gsub!(/ *using (?!\().*\n/, '')
  end

  def convert_int_type(content)
    content.gsub!(/\bint\b/, 'Int')
  end

  def convert_string_type(content)
    content.gsub!(/\bstring\b/, 'Int')
  end

  def convert_bool_type(content)
    content.gsub!(/\bbool\b/, 'Bool')
  end

  def convert_float_type(content)
    content.gsub!(/\bfloat\b/, 'Float')
  end

  def convert_double_type(content)
    content.gsub!(/\bdouble\b/, 'Double')
  end

  def convert_list_type(content)
    content.gsub!(/(?:List|IList)<(\w+)>/, '[\\1]')
  end

  def convert_list_list_type(content)
    content.gsub!(/(?:List|IList)<(?:List|IList)<(\w+)>>/, '[[\\1]]')
  end

  def convert_list_array_type(content)
    content.gsub!(/(?:List|IList)<(\w+)>\[\]/, '[[\\1]]')
  end

  def convert_debug_assert(content)
    content.gsub!(/Debug\.Assert\(/, 'assert(')
  end

  def remove_new(content)
    content.gsub!(/new /, '')
  end

  def remove_namespace(content)
    re = / *namespace +.+ *\{$/
    m = re.match(content)
    i = m.end(0) + 1
    n = 1
    while i < content.length do
      c = content[i]
      if c == "{"
        n += 1
      elsif c == "}"
        n -= 1
        if n == 0
          content.slice!(i)
          content.slice!(m.begin(0)..m.end(0))
          break
        end
      end
      i += 1
    end
  end

  def convert_const_field(content)
    content.gsub!(/(^ *)(?:public|private|internal) +const +(.+?) +(.+?)( *= *.*?|)$/) { |m|
      v = $3
      nv = v.lower_camelcase
      @renamed_vars[v] = nv
      $1 + 'let ' + nv + ': ' + $2 + $4
    }
  end

  def convert_field(content)
    content.gsub!(/(^ *)(?:public|private|internal) +(\w+) +(\w+)( *= *.*?|)$/) { |m|
      $1 + 'private var ' + $3 + ': ' + $2 + $4
    }
  end

  def convert_property(content)
    content.gsub!(/(^ *)(?:public|private|internal) +(?!class)([A-Za-z0-9_\[\]<>]+) +(\w+)(?: *\{)/) { |m|
      v = $3
      nv = v.lower_camelcase
      @renamed_vars[v] = nv
      $1 + 'var ' + nv + ': ' + $2 + ' {'
    }
  end

  def remove_get_set(content)
    content.gsub!(/{ *get; *set; *}$/, '')
  end

  def constructors_to_inits(content)
    re = /(?:(?:public|internal|private) +|)class +(\w+)/
    m = re.match(content)
    while m != nil do
      content.gsub!(Regexp.new('(?:(?:public|internal) +|)' + m.captures[0] + " *\\("), 'init(')
      m = re.match(content, m.end(0))
    end

    content.gsub!(/init\((.*)\)/) { |m|
      'init(' + swap_args($1) + ')'
    }
  end

  def convert_method_decl_to_func_decl(content)
    # TODO: Override should be captured and re-inserted
    content.gsub!(/(?:(?:public|internal|private) +(?:override|))(.+) +(.*)\((.*)\) *\{/) { |m|
      f = $2
      nf = f.lower_camelcase
      @renamed_methods[f] = nf
      if $1 == "void"
        'func ' + nf + '(' + swap_args($3) + ') {'
      else
        'func ' + nf + '(' + swap_args($3) + ') -> ' + $1 + ' {'
      end
    }
  end

  def convert_locals(content)
    content.gsub!(/^( *)(?!return)([A-Za-z0-9_\[\]<>]+) +(\w+)(?:( *= *.+)|)$/, '\\1let \\3\\4')
  end

  def convert_if(content)
    content.gsub!(/if *\((.*)\) +\{/, 'if \\1 {')
    content.gsub!(/if *\((.*?)\)\n( +)(.*?)\n/m) { |m|
      s = $2.length > 4 ? $2[0...-4] : s
      'if ' + $1 + " {\n" + $2 + $3 + "\n" + s + "}\n"
    }
  end

  def convert_next_line_else(content)
    content.gsub!(/\}\n +else \{/m, '} else {')
  end

  def convert_simple_range_for_loop(content)
    content.gsub!(/for \(.+ +(\w+) = (.+); \1 < (.*); \1\+\+\)/, 'for \\1 in \\2..<\\3')
    content.gsub!(/for \(.+ +(\w+) = (.+); \1 >= (.*); \1\-\-\)/, 'for \\1 in (\\3...\\2).reverse()')
  end

  def swap_args(arg_string)
    args = arg_string.split(/, */)
    args.collect! { |arg|
      a = arg.split(' ')
      a[1] + ': ' + a[0]
    }
    args.join(', ')
  end

  def read_file(filename)
    content = nil
    File.open(filename, 'rb') { |f| content = f.read() }
    content
  end

  def write_file(filename, content)
    File.open(filename, 'w') { |f| f.write(content) }
  end

  def error(msg)
    STDERR.puts "error: #{msg}".red
  end

end
