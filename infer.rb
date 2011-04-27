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

  class Keyword
    @term = ''
    @case_sensitive = false
    
    def initialize(term,case_sensitive=false) 

    end

    # Generate apple query expression
    def qe_modifiers
    end 
  end

  def initialize(arguments)
    arguments = arguments.split(' ') if arguments.is_a? String
    @arguments = arguments
    
    @options = {
      inference_index: 0.1, # 10%
      max_results: 10,
      unlimited_results: false,
      technique: 'mdfind',
      display_info: true,
      display_ranks: true,
      display_indices: true,
      prompt: true,

      matchers: {
        graphics: "\.(png|jpeg|jpg|gif|tiff|psd)$",
      },

      handlers: {
        default: "vim $",
        graphics: "open $",
      },
    }

    @content_keywords = []
    @fname_keywords = []


    load_options('~/.infrc') # load from home dir
    load_options('./.infrc') # load from current dir

    parse_args
  end

  def transform_keys_to_symbols(value)
    return value if not value.is_a?(Hash)
    hash = value.inject({}){|memo,(k,v)| memo[k.to_sym] = transform_keys_to_symbols(v); memo}
    return hash
  end

  def load_options(fname)
    fname = File.expand_path(fname)
    yml_options = YAML::load_file(fname) rescue return
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

  def cleanup_path fname
    fname.strip!
  end

  def pipe_lines args
    IO.popen args do |out|
      while fname = out.readline rescue nil do
        yield fname
      end
    end
  end

  def add_result fname
  end

  def mdfind_search search_dir 
    results = []

    @base_path = File.expand_path(search_dir) + '/'

    def abs_to_rel! fname
      fname.strip!
      fname.slice! @base_path
    end
   
    unless @fname_keywords.empty?
      # First we get all files that match any of the filenames (this includes directories)
      # We have to do this so we can recurse the directories, for the desired behavior
      # of searching on path, instead of just filename as mdfind does

      # Note: DisplayName appears to be cached better than FSName, and is the same for files
      query = "(%s)" % @fname_keywords.collect{|k| "kMDItemDisplayName = '*%s*'" % k}.join(' || ')

      # pp query
      # pp search_dir

      pipe_lines ['mdfind', '-onlyin', search_dir, query] do |fname|
        abs_to_rel! fname
        # puts fname
        r = rank_file fname
        results << r unless r.nil?

        if File.directory? fname
          results.concat exhaustive_search(fname)
        end

      end
    end

    # Now we filter the result by any content matches
    c_results = []
    unless @content_keywords.empty?
      query = "(%s)" % @content_keywords.collect{|k| "kMDItemTextContent = '%s'cdw" % k }.join(' && ')

      # pp query
      # pp search_dir

      pipe_lines ['mdfind', '-onlyin', search_dir, query] do |fname|
        abs_to_rel! fname 
        c_results << fname
      end

      # pp results
      # pp c_results

      # We take all content results if no path criteria,
      # as if the default was all inclusive
      if @fname_keywords.any?
        results = results.keep_if do |r|
          c_results.include? r[0]
        end
      else
        results = c_results.map {|r| [r,1] }
      end
    end
    
    results
  end

  def exhaustive_search search_dir
    results = [] 
    Find.find(search_dir) do |fname|
      fname += '/' if File.directory?(fname)
      fname.slice! './'
      r = rank_file fname
      results << r unless r.nil?
    end
    
    results
  end

  def exec_result(fname)
    command = nil

    if @options[:command]
      command = @options[:command]
    else
      @options[:matchers].each do |type, pattern|
        command = @options[:handlers][type] if fname.match(pattern) && @options[:handlers][type] 
      end

      command ||= @options[:handlers][:default]
    end
     
    command = command.gsub /\$/, '"%s"' % fname.gsub('"','\"')
    puts command
    exec command
  end

  def rank_file(fname)
    chars_matched = 0

    @fname_keywords.each do |condition|
      return nil unless fname.include? condition
      chars_matched += condition.length * fname.scan(condition).length
    end

    [fname, chars_matched.to_f / fname.length]
  end
  
  def parse_args
    opts = OptionParser.new do |opts|
      opts.banner = "Usage: i [options] keywords..."

      opts.separator ""
      opts.separator "Options:"

      opts.on("-m", "--max [num]", Integer, "Limit number of results") do |v|
        @options[:max_results] = v
      end

      opts.on("-t", "--technique [mdfind|grep]", "search technique to use") do |v|
        @options[:technique] = v ? 'mdfind' : ''
      end

      opts.on("-s", "--[no-]showonly", "show results and never open the inference") do |v|
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

      opts.on("-v", "--[no-]verbose", "verbose output") do |v|
        @options[:verbose] = v
      end

      opts.on("-[0-9]", "--index", Integer, "verbose output") do |v|
        @override_index = v
      end

      # no argument, shows at tail.  this will print an options summary.
      # try it and see!
      opts.on_tail("-h", "--help", "show this message") do
        puts opts
        exit
      end

      # another typical switch to print the version.
      opts.on_tail("--version", "show version") do
        puts 1.0 
        exit
      end
    end

    opts.parse!(@arguments)

    # inside search special notation
    # parse search keywords

    @arguments.each_with_index do |a, i|
      case a
        when /^\/.+/
          @content_keywords << a.nibble
        else
          @fname_keywords << a
      end

      # @arguments.delete_at(i)
    end

  end

  def run
    results = []
    num_kw_chars = @fname_keywords.join.length

   
    # use first option as search directory if it is a dir and outside of the cwd
    search_dir = (@arguments[0] if @arguments[0] && @arguments[0].match(/^[\~\.\/]/) && File.directory?(@arguments[0])) || './'

    search_dir = '/' if @options[:global_search] 

    results = search(search_dir)

    results.sort! { |a,b| b[1] <=> a[1] }



    if results.empty?
      print "Didn't find anything.\n"
      exit
    end

    unless @options[:show_only] || !@options[:display_info]
      if results.count == 1 || results[0][1] - results[1][1] > @options[:inference_index]
           exec_result results[0][0]
        exit
      end

      print "\nAmbiguous. Try refining the search.\n" 
    end

    print "\n" if @options[:display_info]

    display_count = @options[:max_results] || results.length

    results[0..display_count-1].each_with_index do |result, i|

      if @options[:display_indices]
        print "#{i}. ".rjust((display_count-1).to_s.length+2)
      end

      if @options[:display_ranks]
        rank_ratio = result[1]/results[0][1]*10
        rank_remainder = rank_ratio - Integer(rank_ratio)
        partial_blocks = ["\u258F","\u258E","\u258D","\u258C","\u258B","\u258A","\u2589","\u2588"]
        remainder_block = partial_blocks[rank_remainder * partial_blocks.length]

        print ("\u2588"*(rank_ratio) + remainder_block).ljust(11)
      end

      print "#{result[0]} \n"
    end

    if results.length > display_count
      puts "\n%d more hidden." % (results.length - display_count)
    end

    if @options[:prompt]
      print  "\nPick one of the results to launch (0-%d): " % (display_count-1) 
      sel = Integer(STDIN.gets) rescue nil
      exec_result results[sel][0] unless sel.nil?
    end
  end


  #run_util


  codes = %w[iso-2022-jp shift_jis euc-jp utf8 binary]
  code_aliases = { "jis" => "iso-2022-jp", "sjis" => "shift_jis" }

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

