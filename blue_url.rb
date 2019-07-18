#!/usr/bin/ruby

#require "json"   # inline instead

#########################

unless defined?(JSON)
class JSON
  def self.generate(obj)
    obj.inspect.gsub(/([{,]):/){|m|m[0]}.gsub(/=>/,":")
  end
end
end # ifdef

#########################

class BlueJeansUrlGenerator
  def generate(meeting_id, passcode = nil)
    "bjnb://meet/id/#{meeting_id}#{ "/#{passcode}" if passcode}"
  end
end

##########################

class BjUrl
  class Num
    attr_accessor :num, :aliases

    def initialize(num, *aliases)
      @num = num
      @aliases = aliases
    end

    def name
      aliases.first
    end

    def matching_phrase(phrase)
      phrase = /^#{phrase}/ if phrase.kind_of?(String)
      if @num =~ phrase
        @num
      else
        @aliases.detect { |a| a =~ phrase }
      end
    end
    alias =~ matching_phrase

    def url
      @url ||= BlueJeansUrlGenerator.new.generate(num)
    end

    def to_hash(phrase = nil)
      # TODO: phrase matches number
      # 
      # uid helps with sorting,
      m_phrase = matching_phrase(phrase)
      ret = {
        "uid" => num,
        "autocomplete" => m_phrase,
        "arg" => url,
        "title" => (m_phrase == num || m_phrase == name) ? name : "#{m_phrase} (#{name})",
        "subtitle" => num, 
        "text" => { "copy" => "https://bluejeans.com/#{num}", "largetype" => num},
      }
#         "icon": { "type": "fileicon", "path": "~/Desktop"}
#         "mods": {
#           "alt": {"arg": "AAA", "subtitle": "AAA"},
#           "cmd": { }
#         },
# # "text" => {"quicklookurl": "http://x.com/"}
      ret.merge!("title" => @alias, "subtitle" => name) if @alias
      ret
    end

    def inspect
      ([num] + aliases).join(",").inspect
    end

    def to_csv
      ([num] + aliases).join(",")
    end
  end

  def clean_url(args)
    args[0]
  end

  def search(phrase, extra = false)
    db = db_from_file
    regex = phrase.kind_of?(String) ? /^#{phrase}/ : phrase
    items = db.select { |db| db =~ regex }
    if extra && items.empty? # allow a person to dial the number as is
      num_phrase = phrase.gsub(/[^0-9]/,'')
      items = [Num.new(num_phrase, "unknown")] unless num_phrase == ''
    end

    items
  end

  def clean_search(phrase, extra = false)
    search(clean_url(phrase), extra)
  end

  # thinking about merge option
  # TODO: if the name is with another entry, remove it
  def add(num, *aliases)
    # for alfred, ARGV comes in as one blob
    # have since updated input bash script, but leaving this here anyway
    num, *aliases = num.split if aliases.empty?

    data = db_from_file
    # if the number already exists, we will add this alias to that entry
    # TODO: be able to add an alias to an existing alias e.g.: n.aliases.include?(num)
    old_data = data.detect { |n| n.num == num }
    data.reject! { |n| n.num == num }
    # merge old data and new data
    aliases = (old_data.aliases + aliases).uniq if old_data && !old_data.aliases.empty?

    new_num = BjUrl::Num.new(num, *aliases)
    data.push(new_num)

    db_to_file(data)
    new_num
  end

  def urls(argv)
    clean_search(argv, true).map(&:url)
  end

  def numbers(argv)
    clean_search(argv, true).map(&:id)
  end

  def alfred(argv)
    phrase = clean_url(argv)
    items = search(phrase, true)
    JSON.generate("items" => items.map {|i| i.to_hash(phrase)})
  end

  private

  def db_from_file(filename = db_file_name)
    data_from_file(filename).map do |line|
      Num.new(*line.split(","))
    end
  end

  def db_to_file(db, filename = db_file_name)
    data_to_file(db.map(&:to_csv).join("\n") + "\n", filename)
  end

  def data_from_file(filename = db_file_name)
    File.read(filename).split(/\n/).map(&:chomp)
  end

  def data_to_file(data, filename = db_file_name)
    File.write(filename, data)
  end

  def db_file_name
    "numbers.csv" # #{File.dirname(__FILE__)}/numbers.csv"
  end
end

if __FILE__ == $0
  bu = BjUrl.new

  case ARGV[0]
  when "--url" # debugging the url generated
    ARGV.shift
    puts bu.urls(ARGV)
  when "--id" # debugging the id lookup in the address book
    ARGV.shift
    puts bu.numbers(ARGV)
  when "--add" # adding the record to the address book
    ARGV.shift
    item = bu.add(*ARGV)
    puts "#{item.num}: #{item.aliases.join(", ")}"
  else
    puts bu.alfred(ARGV)
  end
end
