#!/usr/bin/ruby

#require "base32" # inline instead
#require "json"   # inline instead

################# BASE32 ###################
# https://github.com/stesla/base32/blob/master/lib/base32.rb

unless defined?(Base32)
module Base32
  TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze
  @table = TABLE

  class << self
    attr_reader :table
  end

  class Chunk
    def initialize(bytes)
      @bytes = bytes
    end

    def decode
      bytes = @bytes.take_while {|c| c != 61} # strip padding
      n = (bytes.length * 5.0 / 8.0).floor
      p = bytes.length < 8 ? 5 - (n * 8) % 5 : 0
      c = bytes.inject(0) do |m,o|
        i = Base32.table.index(o.chr)
        raise ArgumentError, "invalid character '#{o.chr}'" if i.nil?
        (m << 5) + i
      end >> p
      (0..n-1).to_a.reverse.collect {|i| ((c >> i * 8) & 0xff).chr}
    end

    def encode
      n = (@bytes.length * 8.0 / 5.0).ceil
      p = n < 8 ? 5 - (@bytes.length * 8) % 5 : 0
      c = @bytes.inject(0) {|m,o| (m << 8) + o} << p
      [(0..n-1).to_a.reverse.collect {|i| Base32.table[(c >> i * 5) & 0x1f].chr},
       ("=" * (8-n))]
    end
  end

  def self.chunks(str, size)
    result = []
    bytes = str.bytes
    while bytes.any? do
      result << Chunk.new(bytes.take(size))
      bytes = bytes.drop(size)
    end
    result
  end

  def self.encode(str)
    chunks(str, 5).collect(&:encode).flatten.join
  end

  def self.decode(str)
    chunks(str, 8).collect(&:decode).flatten.join
  end

  # def self.random_base32(length=16, padding=true)
  #   random = ''
  #   OpenSSL::Random.random_bytes(length).each_byte do |b|
  #     random << self.table[b % 32]
  #   end
  #   padding ? random.ljust((length / 8.0).ceil * 8, '=') : random
  # end

  def self.table=(table)
    raise ArgumentError, "Table must have 32 unique characters" unless self.table_valid?(table)
    @table = table
  end

  def self.table_valid?(table)
    table.bytes.to_a.size == 32 && table.bytes.to_a.uniq.size == 32
  end
end
end # ifdef

#########################

unless defined?(JSON)
class JSON
  def self.generate(obj)
    obj.inspect.gsub(/([{,]):/){|m|m[0]}.gsub(/=>/,":")
  end
end
end # ifdef

#########################
# https://github.com/Aldaviva/ruby-bjn-app-url-generator

Base32.table = "0123456789abcdefghjkmnpqrtuvwxyz"
class BlueJeansUrlGenerator
  CTXVER = "1.0.0"

  def createLaunchContext(meetingId, passcode=nil)
    context = {
      "meeting_id" => meetingId
#    :user_full_name => nil, # optional, defaults to the name of the logged-in user
#    :user_email => nil, # optional, defaults to the email address of the logged-in user
#    :user_token => nil, # optional, if you've already logged into Blue Jeans and received an API access token and want the app to be logged in as the same user
    
#    :meeting_api => "https://bluejeans.com", # optional, always https://bluejeans.com
#    :release_channel => "live" # optional, always live
    }
    context["role_passcode"] = passcode.to_s.rjust(4, '0') if passcode
    context
  end

  def createLaunchUrl(launchContext)
    launchContextJson = JSON.generate(launchContext)
    encodedContext = Base32.encode(launchContextJson).sub(/=+$/, '')
    "bjn://meeting/#{encodedContext}?ctxver=#{CTXVER}"
  end

  def cleanMeetingId(meetingId)
    meetingId
  end

  def generate(meetingId, passcode = nil)
    createLaunchUrl(createLaunchContext(cleanMeetingId(meetingId), passcode))
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
        "text" => { "copy" => num, "largetype" => num}
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

  # thinking about merge option
  # TODO: if the name is with another entry, remove it
  def add(num, *aliases)
    # for alfred, ARGV comes in as one blob
    # have since updated input bash script, but leaving this here anyway
    num, *aliases = num.split if aliases.empty?

    data = db_from_file
    # if the number already exists, we will add this alias to that entry
    old_data = data.detect { |n| n.num == num }
    data.reject! { |n| n.num == num }
    # merge old data and new data
    aliases = (old_data.aliases + aliases).uniq if old_data && !old_data.aliases.empty?

    new_num = BjUrl::Num.new(num, *aliases)
    data.push(new_num)

    db_to_file(data)
    new_num
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
  # output mode
  action = :retrieve
  case ARGV[0]
  when "--url" # debugging
    ARGV.shift
    mode = :url
  when "--id" # debugging
    ARGV.shift
    mode = :id
  when "--add"
    ARGV.shift
    action = :create
  else
    mode = :alfred
  end

  case action
  when :create
    bu = BjUrl.new
    item = bu.add(*ARGV)
    puts "#{item.num}: #{item.aliases.join(", ")}"
  when :retrieve
    bu = BjUrl.new
    phrase = bu.clean_url(ARGV)
    items = bu.search(phrase, true)
    case mode
    when :url
      puts items.map { |item| item.url }
    when :id
      puts items.map { |item| item.num }
    when :alfred
      puts JSON.generate("items" => items.map {|i| i.to_hash(phrase)}) # unless items.empty?
    end
  end
end
