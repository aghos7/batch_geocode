#!/usr/bin/env ruby
require 'csv'
require 'date'
require 'yaml'
require 'geocoder'
require 'byebug'
require 'active_support/all'

SEPARATOR = ","

# helper functions
def header(hash)
  hash.keys.join SEPARATOR
end

def to_csv(hash)
  hash.values.map do |value|
    escape value unless value.nil?
  end.join SEPARATOR
end

options = {}

# Load config
begin
  yaml = YAML.load_file("config.yml")
  options[:input_file] = yaml['input_file'] || 'input.csv'
  options[:output_file] = yaml['output_file'] || 'output.csv'
  options[:geocoder_api_key] = yaml['geocoder_api_key']
rescue Errno::ENOENT
  puts "config file not found"
end

# read command line options
OptionParser.new do |opt|
  opt.on('-i input_file', '--input_file input_file', 'Input file') { |o| options[:input_file] = o }
  opt.on('-o output_file', '--output_file output_file', 'Output file') { |o| options[:output_file] = o }
  opt.on('-k api_key', '--api_key api_key', 'Geocoder API Key') { |o| options[:geocoder_api_key] = o }
end.parse!

# Delete output if exists
if File.exist?(options[:output_file])
  puts 'CSV file exists - deleting'
  File.delete(options[:output_file])
end

# config geocoder
Geocoder.configure(
  # geocoding service (see below for supported options):
  lookup: :google,
  use_https: true,
  # to use an API key:
  api_key: options[:geocoder_api_key],
  timeout: 5
)

# read each line of input file, geocode and output results
puts "reading address file"
# write to CSV
CSV.open(options[:output_file], "wb") do |csv|

  id_count = 1
  CSV.foreach(options[:input_file], headers: true, header_converters: :symbol) do |line|

    begin
      if line[:table_company] && line[:address]
        query = "#{line[:table_company]} #{line[:address]}"
        line[:using] = :table_company_and_address
        result = Geocoder.search(query).first
      end

      if result.nil? && line[:address].present?
        query = line[:address]
        line[:using] = :address
        result = Geocoder.search(query).first
      end

      if result.nil? && line[:table_latitude].present? && line[:table_longitude].present?
        query = [line[:table_latitude], line[:table_longitude]]
        line[:using] = :table_lat_lng
        result = Geocoder.search(query).first
      end

      line[:geocoded_place_id] = result.data['place_id']
      line[:geocoded_latitude] = result.latitude
      line[:geocoded_longitude] = result.longitude
      line[:geocoded_address] = result.address
      line[:geocoded_street_address] = result.street_address
      line[:geocoded_city] = result.city
      line[:geocoded_state] = result.state_code
      line[:geocoded_sub_state] = result.sub_state
      line[:geocoded_postal_code] = result.postal_code
      line[:geocoded_country] = result.country_code

      possible_issues = []
      if line[:geocoded_latitude] != (line[:table_latitude] || line[:places_latitude]) ||
        line[:geocoded_longitude] != (line[:table_longitude] || line[:places_longitude])
        possible_issues << :lat_lng_mismatch
      end

      if line[:geocoded_place_id] != [line[:table_place_id].to_s, line[:places_place_id].to_s].max
        possible_issues << :place_id_mismatch
      end

      line[:possible_issues] = possible_issues.compact.join(', ')

      puts "#{line[:table]}:#{line[:table_id]}:#{line[:account_id]} - #{line[:geocoded_address]} " +
        "[#{line[:geocoded_latitude]}, #{line[:geocoded_longitude]}] [#{line[:geocoded_place_id]}]"

      csv << line
    rescue => e
      puts "processing error #{e.to_s}"
      puts line.inspect
    end
    sleep 1
  end
end

puts "done"
nil
