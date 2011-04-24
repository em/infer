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

  Keyword = Struct.new(:term, :case_sensitive)

  def initialize(arguments)
    arguments = arguments.split(' ') if arguments.is_a? String
    @arguments = arguments
    
    @options = {
      inference_index: 0.1, # 10%
      max_results: 10,
      unlimited_results: false,
      # technique: 'mdfind',

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

    print "Searching #{search_dir}\n\n"

    case @options[:technique]
      when 'grep'
        grep_search search_dir 
      when 'mdfind'
        mdfind_search search_dir
      when 'locate'
        locate_search search_dir
      else
        exhaustive_search search_dir
    end
  end

  def grep_search(keywords)
  end

  def cleanup_path fname
    fname.strip!
  end

  def mdfind_pipe args
    IO.popen args do |out|
      while fname = out.readline rescue nil do
        yield fname
      end
    end
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
      query = "(%s)" % @fname_keywords.collect{|k| "kMDItemFSName = *%s*" % k}.join(' || ')

      pp query
      pp search_dir

      mdfind_pipe ['mdfind', '-onlyin', search_dir, query] do |fname|
        abs_to_rel! fname
        # puts fname
        r = rank_file fname
        results << r unless r.nil?

        if File.directory? fname
          results.concat exhaustive_search(fname)
        end

      end
    end

    c_results = []
    unless @content_keywords.empty?
      query = "(%s)" % @content_keywords.collect{|k| "kMDItemTextContent = '*%s*'cw" % k }.join(' && ')

      pp query
      pp search_dir

      mdfind_pipe ['mdfind', '-onlyin', search_dir, query] do |fname|
        abs_to_rel! fname 
        c_results << fname
      end
    end

    # pp results
    # pp c_results
    #
    if @fname_keywords.any? && @content_keywords.any?
      results = results.keep_if do |r|
        c_results.include? r[0]
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
      opts.banner = "usage: infer [options] keywords"

      opts.separator ""
      opts.separator "options:"

      opts.on("-s", "--[no-]showonly", "show results and never open the inference") do |v|
        @options[:show_only] = v
      end

      opts.on("-n", "--inside [keywords]", "search inside files") do |v|
        @content_keywords << v
      end

      opts.on("-m", "--max-results [num]", "limit results") do |v|
        @options[:max_results] = v
      end

      opts.on("-t", "--technique [mdfind|grep]", "search technique to use") do |v|
        @options[:technique] = v ? 'mdfind' : ''
      end

      opts.on("-v", "--[no-]verbose", "verbose output") do |v|
        @options[:verbose] = v
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
        when /\-[0-9]/
          
        when /^\/.+/
          @content_keywords << a.nibble
        else
          @fname_keywords << a
      end

      @arguments.delete_at(i)
    end

  end

  def run

    load_options('~/.infrc') # load from home dir
    load_options('./.infrc') # load from current dir

    parse_args
   
#     if argv.empty?
#     print <<helpmessage
#     usage: infer [options] [keyword]...
# 
#     recursively searches the current directory based on a set of keywords,
#     launching the best match if it is better than the next by at least #{(@options[:inference_index] * 100).to_i}%.
#     otherwise it offers a choice.
# 
#     search algorithm:
#       * all keywords must be matched in the full relative path of a file
#       * at least one of the keywords must match the filename
# 
#     options:
#       -s    show results and never open the inference 
#       -a    show all results, unlimited
#       -l n  limit number of results by n
#       -c    command to execute the inference with (filename is $)
#       -i    search inside files (may be slow, try using different search tool)
#       -(result_number)  override inference with this result
# 
#       -mdfind  speedy search with mdfind (osx only)
# helpmessage
#     exit
#     end
    # 
    # # apply command line@options
    # argv.each_with_index do |a, i|
    #   opt_list = true if a.match(/^-l/)

    #   a.match /^\\-([a-z]+)/ do |flags|
    #     flags.match
    #     k = match[1]
    #     # v = match[2]

    #     case k
    #       when 's'
    #        @options[:show_only] = true
    #       when 'a'
    #        @options[:unlimited] = true
    #       when 'l'
    #        @options[:limit] = v || argv.delete_at(i+1) || invalid_arg('l')
    #       when 'c'
    #        @options[:command] = v || argv.delete_at(i+1) || invalid_arg('c') 
    #       when 'm'
    #        @options[:searcher] = 'mdfind'
    #     end

    #     # remove arg so it's not treated as keyword
    #     argv.delete_at(i)
    #   end
    # end

    results = []
    num_kw_chars = @fname_keywords.join.length


    p @fname_args

   
    # use first option as search directory if it is a dir and outside of the cwd
    search_dir = (@arguments[0] if @arguments[0] && @arguments[0].match(/^[\~\.\/]/) && file.directory?(@arguments[0])) || './'

    results = search(search_dir)

    results.sort! { |a,b| b[1] <=> a[1] }

    if results.empty?
      puts "Didn't find anything."
      exit
    end

    unless @options[:show_only]
      if results.count == 1 || results[0][1] - results[1][1] > @options[:inference_index]
           exec_result results[0][0]
        exit
      end

      print "\nAmbiguous. Try refining the search.\n\n" 
    end

    results[0..@options[:max_results]-1].each_with_index do |result, i|
      print "#{i}. "

      10.times do |i|
       print (result[1]/results[0][1]*10) < i ? ' ' : "\u2588"
      end

      print " #{result[0]} \n"
    end

    if results.length > 9
      puts "\n%d more hidden." % results.length
    end


    print  "\nPick one of the resuls to launch (0-%d): " % [results.length-1, @options[:max_results]].min 
    sel = Integer(STDIN.gets) rescue nil
    exec_result results[sel][0] unless sel.nil?
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
  i = Infer.new(ARGV)
  i.run
end

