#!/usr/bin/env ruby
require 'date'
require 'open-uri'
require 'optparse'
require 'yajl'
require 'zlib'

def github_uri_list(start_date, end_date)
  uri_list = []
  get_day = start_date
  until end_date < get_day # includes start and end dates in the results.
    uri_list << "http://data.githubarchive.org/%d-%02d-%02d-%d.json.gz" % 
                 [get_day.year, get_day.month, get_day.day, get_day.hour]
    get_day += 1
  end

  uri_list
end

# bypass records that we don't care about.
def record_valid?(doc, options)
  return false if doc['type'] != options[:event_name]
  return false if doc['repository'].nil? || 
                  doc['repository']['url'].nil? || 
                  doc['repository']['pushed_at'].nil?
  pushed_at = DateTime.parse(doc['repository']['pushed_at'])
  return false if options[:after] > pushed_at || pushed_at > options[:before]
  return true
end

# get option parameters
options = {}
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby gh_repo_stats.rb [--after DATETIME] [--before DATETIME] [--event EVENT_NAME] [-n COUNT]'
  opts.on('--after DATETIME', 'Start Date') do |after|
    options[:after]      = DateTime.parse(after)
  end

  opts.on('--before DATETIME', 'End Date') do |before|
    # if end date is past yesterday, set to yesterday.
    end_date             = DateTime.parse(before)
    options[:before]     = end_date.day < DateTime.now.day - 1 ? end_date : DateTime.now - 1
  end

  opts.on('--event EVENT_NAME', 'Event Name') do |event_name|
    options[:event_name] = event_name 
  end

  opts.on('-n', '--count COUNT', Integer, 'Limit of results') do |results_count|
    options[:count]      = results_count
  end

  # Defaults
  options[:after]      ||= DateTime.now - 7 # one week
  options[:before]     ||= DateTime.now - 1 # yesterday because today's file may not exist yet.
  options[:event_name] ||= 'PushEvent'
  options[:count]      ||= 20
end.parse!

# notify user error if date-range is invalid.
if options[:before] < options[:after]
  puts 'Begin Date is after the End Date'
  return false
end

# notify user error if limit is 0 or negative.
if options[:count].to_i < 1
  puts 'Count must be a positive number'
  return false
end

# pull day's stat files from github
events = {}
uri_list = github_uri_list(options[:after], options[:before])
uri_list.each do |uri|
  puts "fetching uri: #{uri}"
  packed_info = open(uri)
  # unpack the day's .gz file
  json_info = Zlib::GzipReader.new(packed_info).read
  # parse the unpacked JSON.
  parser = Yajl::Parser.new
  parser.parse(json_info) do |doc|
    if record_valid?(doc, options)
      key = doc['repository']['url'].gsub(/http[s]?:\/\/github.com\//,'')
      if events.key?(key)
        events[key] += 1
      else
        events[key] = 1
      end
    end
  end
end

def display_results(events, limit)
  # is there less records than the limit requested?
  record_limit = events.count < limit ? events.count : limit
  record_limit.times do |row|
    result_line = events[row].join(': ') + ' events'
    puts result_line
  end
end

events = events.sort {|row_a, row_b| row_b[1] <=> row_a[1]}
display_results(events, options[:count])
