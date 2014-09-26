#!/usr/bin/env ruby

require 'find'
require 'yaml'
require 'optparse'
require 'optparse/time'
require 'ostruct'
require 'pp'

class String
   def nibble(fixnum=1)
     range_end = self.length - 1
     slice(fixnum..range_end)
   end
end

class Infer
  attr :results, :options

  class Keyword
    attr :term, :case_sensitive
 
    def initialize(term,case_sensitive=false) 
      @term = term
      @case_sensitive = case_sensitive
    end

    # Generate apple query expression
    def qe_modifiers
    end 
  end
  
  class Result
    include Comparable
    attr_accessor :path, :rank

    def <=>(other)
      r = other.rank <=> rank
      if r == 0
        return other.path <=> path
      end 
      r
    end

    def initialize(path, rank)
      @path = path
      @rank = rank
    end
  end

  def initialize(arguments)
    arguments = arguments.split(' ') if arguments.is_a? String
    @arguments = arguments
    @results = []
    
    @options = {
      inference_index: 0.01, # 10%
      max_results: 40,
      unlimited_results: false,
      technique: 'exhaustive',
      include_dirs: false,
      display_info: true,
      display_ranks: true,
      display_indices: true,
      prompt: true,
      ignore: "(^\\.|log/)",

      matchers: {
        graphics: "\\.(png|jpeg|jpg|gif|tiff|psd)$",
      },

      handlers: {
        default: "vim $",
        graphics: "open $",
      },
    }

    @content_keywords = []
    @path_keywords = []


    load_options('~/.infrc') # load from home dir
    load_options('./.infrc') # load from current dir

    parse_args
  end

  def term_lines
    `tput lines`.to_i
  end

  def term_cols
    `tput lines`.to_i
  end

  def transform_keys_to_symbols(value)
    return value if not value.is_a?(Hash)
    hash = value.inject({}){|memo,(k,v)| memo[k.to_sym] = transform_keys_to_symbols(v); memo}
    return hash
  end

  def load_options(path)
    path = File.expand_path(path)
    yml_options = YAML::load_file(path) rescue return
    yml_options = transform_keys_to_symbols(yml_options)
    # yml_options = yml_options.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
    @options.merge! yml_options
  end

  def invalid_arg(name)
    print "Options '#{name}' requires an argument.\n"
    exit
  end

  def search search_dir

    print "Searching #{search_dir}\n\n" if @options[:verbose]

    case @options[:technique]
      when 'grep'
        grep_search search_dir 
      when 'mdfind'
        begin
          mdfind_search search_dir
        rescue Errno::ENOENT
          exhaustive_search search_dir
        end
      else
        exhaustive_search search_dir
    end
  end

  # Grep for content search
  def grep_search search_dir
    args = ['-r']
  end

  def cleanup_path path
    path.strip!
  end

  def pipe_lines args
    IO.popen args do |out|
      while path = out.readline rescue nil do
        yield path
      end
    end
  end

  def process_path path
    rank = rank_path(path)
    result = Result.new(path,rank)
    # return false if @results.include? result
    @results << result unless rank < 0
    true
  end

  def rerank_results
    c_kw = @path_keywords + @filter.split(' ')

    @results.each { |r|
      r.rank = rank_path r.path, c_kw
    }

    @results.sort!
  end

  def mdfind_search search_dir 
    results = []

    @base_path = File.expand_path(search_dir) + '/'

    def abs_to_rel! path
      path.strip!
      path.slice! @base_path
    end
   
    unless @path_keywords.empty?
      # First we get all files that match any of the filenames (this includes directories)
      # We have to do this so we can recurse the directories, for the desired behavior
      # of searching on path, instead of just filename as mdfind does

      # Note: DisplayName appears to be cached better than FSName, and is the same for files
      query = "(%s)" % @path_keywords.collect{|k| "kMDItemDisplayName = '*%s*'" % k}.join(' || ')

      # pp query
      # pp search_dir

      pipe_lines ['mdfind', '-onlyin', search_dir, query] do |path|
        abs_to_rel! path
        # puts path
        r = rank_path path
        results << r unless r.nil?

        if File.directory? path
          exhaustive_search(path)
        end

      end
    end

    # Now we filter the result by any content matches
    c_results = []
    if @content_keywords.any?
      query = "(%s)" % @content_keywords.collect{|k| "kMDItemTextContent = '%s'cdw" % k }.join(' && ')

      # pp query
      # pp search_dir

      pipe_lines ['mdfind', '-onlyin', search_dir, query] do |path|
        abs_to_rel! path 
        c_results << path
      end

      # pp results
      # pp c_results

      # We take all content results if no path criteria,
      # as if the default was all inclusive
      if @path_keywords.any?
        results = results.keep_if do |r|
          c_results.include? r[0]
        end
      else
        results = c_results.map {|r| Result.new(r,1) }
      end
    end
 
    results
  end


  def exhaustive_search search_dir
    Find.find(search_dir) do |path|
      path.slice! './'

      if @options[:ignore] && File.basename(path).match(@options[:ignore])
        Find.prune if File.directory?(path) # Don't recurse this dir
        next # Don't save result
      end

      path += '/' if File.directory?(path)
      # rank = rank_path(path)
      process_path path
    end
    
  end

  def exec_result(result)
    command = nil

    if @options[:command]
      command = @options[:command]
      command += ' $' unless command.match /\$/
    else
      @options[:matchers].each do |type, pattern|
        command = @options[:handlers][type] if result.path.match(pattern) && @options[:handlers][type] 
      end

      command ||= @options[:handlers][:default]
    end
     
    command = command.gsub /\$/, '"%s"' % result.path.gsub('"','\"')
    puts command
    exec command
  end

  def rank_path(path, p_kw=@path_keywords)

    unless @case_sensitive
      path = path.downcase
      p_kw = p_kw.map {|kw| kw.downcase }
    end

    if p_kw.empty? && !path.empty?
      return 1
    end


    chars_matched = 0
    content_matched = 0


    if !@options[:include_dirs] && File.directory?(path)
      return -1
    end

    p_kw.each do |condition|
      return -1 unless path.include? condition 
      chars_matched += condition.length * path.scan(condition).length
    end

    c_kw = @content_keywords
    
    if c_kw.any? && File.exists?(path) && !File.directory?(path)
      File.open(path, "r") do |infile|
        while (line = infile.gets)
          c_kw.each do |kw|
            if line.include? kw
              content_matched += kw.length * line.scan(kw).length
            end
          end
        end
      end
    end
    
    # pp content_matched
    return -1 if chars_matched == 0 && content_matched == 0

    # puts
    # puts chars_matched.to_f / path.length
    chars_matched.to_f / path.length
  end
  
  def parse_args


    opts = OptionParser.new do |opts|
      opts.banner = "Usage: i [options] keywords..."

      opts.separator ""
      opts.separator "Options:"

      opts.on("-m", "--max [num]", Integer, "Limit number of results") do |v|
        @options[:max_results] = v
      end

      opts.on("-t", "--technique [mdfind|grep]", "Search technique to use") do |v|
        @options[:technique] = v ? 'mdfind' : ''
      end

      opts.on("-s", "--[no-]showonly", "Show results and never open the inference") do |v|
        @options[:show_only] = v
      end

      opts.on("-a", "--all", "Do not truncate the results") do |v|
        @options[:max_results] = nil 
      end

      opts.on("--[no-]prompt", "Prompt for result selection") do |v|
        @options[:prompt] = v
      end

      opts.on("-p", "--plain", "Plain filename output; no indices, ranks, prompting, or unnecessary info.") do |v| 
        @options[:display_info] = false 
        @options[:display_ranks] = false 
        @options[:display_indices] = false 
        @options[:prompt] = false 
      end

      opts.on("-z", "--null", "Separate results with a null character instead of newline.") do |v|
        @options[:terminator] = "\x00" 
      end

      opts.on("-g", "--global", "Global filesystem search") do |v|
        @options[:global_search] = v
      end

      opts.on("-c [COMMAND]", "--command", "Execute command on inference") do |v|
        @options[:command] = v
      end

      opts.on("-v", "--[no-]verbose", "Verbose output") do |v|
        @options[:verbose] = v
      end

      opts.on("-[0-9]", "--index", Integer, "Force open result n") do |v|
        @override_index = v
      end

      # no argument, shows at tail.  this will print an options summary.
      # try it and see!
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end
    end

    @options[:command] = @arguments.shift if File.basename($0) == 'I'

    opts.parse!(@arguments)


    # inside search special notation
    # parse search keywords

    @arguments.each_with_index do |a, i|
      case a
        when /^\/.+/
          @content_keywords << a.nibble
        else
          @path_keywords << a
      end

      # @arguments.delete_at(i)
    end

  end

  def read_char
    system "stty raw -echo"
    STDIN.getc
  ensure
    system "stty -raw echo"
  end

  BACKSPACE = "\u007F"

  def filtering_loop
    @selection  ||= 0

    @filter = ''

    begin
      c = read_char
      # pp c
      # return

      case c
      when "\u0003" # ^C
        puts 'quit'
        return
      
      when BACKSPACE
        next if @filter.length == 0
        @filter.chop!
        print "\33[1D\33[K"

        rerank_results
      when "\33"
        # pp STDIN.getc
        #
        # exit unless STDIN.stat.size > 0
        
        if STDIN.getc == '['
          d = STDIN.getc
          if d == 'A'
            @selection = [0, @selection-1].max
            print "\33[1D\33[K"
          end
          if d == 'B' && @selection+1 < @display_count
            @selection += 1
            print "\33[1D\33[K"
          end
        end

      when "\r"
        exec_result @results[@selection]

      when /[0-9]/
        @selection = Integer(c)
        
      when "\n"
        exit 
      else
        @filter += c
        print c
        rerank_results
        # print "\\33[1C"
      end

      print_results(@filter)

    end until c == "\n" || c == "\r"

    exit

  end


  def print_results(filter=nil)

    width = `tput cols`.to_i
    height = `tput lines`.to_i

    flen = filter ? filter.length : 0

    results = @results

    if filter
      print  "\33[1B\33[%dD" % (19 + flen)

      c_kw = @path_keywords + filter.split(' ')
    else
      print  "Filter: \n"
      # print  "\\33[7mFilter 100 files: \\n\\n"
    end
  

    # Erase to end of screen
    print "\33[J\n"


    if @options[:max_results]
      @display_count = [@options[:max_results], results.length, height-5].min
    else
      @display_count = results.length
    end

    selection = @selection || 0
    outputted = 0
    first_result = nil 
    results.each_with_index do |result, i|

      # next unless !filter || result.path.include?(filter)

      next if result.rank < 0

      break if outputted >= @display_count

      selected = (selection == outputted)

      first_result ||= result

      outputted += 1

      if !selected 
        # print "\\33[37m"
      end
      
      if @options[:display_indices]
        print selected ? "\u25B6" : ' '
        print " #{i} ".rjust((@display_count-1).to_s.length+2)
      end

      if @options[:display_ranks]
        rank_ratio = result.rank / first_result.rank * 5
        rank_remainder = rank_ratio - Integer(rank_ratio)
        partial_blocks = ["\u258F","\u258E","\u258D","\u258C","\u258B","\u258A","\u2589","\u2588"]
        remainder_block = partial_blocks[rank_remainder * partial_blocks.length]


        print ("\u2588"*(rank_ratio) + remainder_block).ljust(6)
      end

      print "#{result.path}".ljust(40).slice(0,width-13)
      
      if selected
        # print " <- launch with <enter>"
      else
        print "\33[0m"
      end

      print "\n"
      
    end


    # print "\\33[J"
  
    # count = results.reduce(0) {|r,c| c += 1; break if r.rank.nil? }
    count = results.find_index {|r| r.rank.nil?} || results.length

    if count > @display_count
      puts "\n%d more hidden.\n" % (count - @display_count)
      outputted += 2
    end


    # Move cursor up to filter
    print "\33[%dA\33[%dC" % [outputted+2,8 + flen]





    if @options[:prompt]
      # print  "\\nPick one of the results to launch (0-%d): " % (display_count-1) 

      # puts "\\33[%dA" % 5
      # puts "\\33[J"
      #

      # filtering_loop

      # sel = Integer(read_char) rescue nil
      # exec_result @results[sel] unless sel.nil?
    end

  end

  def run
    # use first option as search directory if it is a dir and outside of the cwd
    # search_dir = (@arguments[0] if @arguments[0] && @arguments[0].match(/^[\\~\\.\\/]/) && File.directory?(@arguments[0])) || './'
    search_dir = './'

    search_dir = '/' if @options[:global_search] 
    

    search(search_dir)

    @results.sort!


    if @results.empty?
      print "Didn't find anything.\n"
      exit
    end

    unless @options[:show_only] || !@options[:display_info]
      if @results.count == 1 || @results[0].rank - @results[1].rank > @options[:inference_index]
           exec_result @results[0]
        exit
      end

      # print "\\Too vague. Try refining the search.\\n" 
    end

    print "\n" if @options[:display_info]

    print_results
    filtering_loop
  end
 
  #
  # return a structure describing the options.
  #
  def self.parse(args)
    # the options specified on the command line will be collected in *options*.
    # we set default values here.

  end  # parse()

end  # class Infer

# options = Infer.parse(@arguments)
# pp options

if __FILE__ == $0
  trap("SIGINT") { puts " ya"; exit!; }

  begin
    i = Infer.new(ARGV)
    i.run
  rescue OptionParser::InvalidOption => e
    puts e.message
  end
end


[0,1,2].map {|i| i + 1 }
