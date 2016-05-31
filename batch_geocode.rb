#!/usr/bin/env ruby
require 'csv'
require 'date'
require 'yaml'
require 'geocoder'
# require 'byebug'
require 'optparse'
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
  use_https: true,
  # to use an API key:
  api_key: options[:geocoder_api_key],
  timeout: 5
)

def matches(line, result)
  (result.present? && (line[:original_place_id].present? && line[:original_place_id] == result.try(:place_id)))
end

# read each line of input file, geocode and output results
puts "reading address file"
# write to CSV
CSV.open(options[:output_file], "wb") do |csv|

  id_count = 1
  CSV.foreach(options[:input_file], headers: true, header_converters: :symbol) do |line|

    begin
      line[:original_place_id] = [line[:table_place_id].to_s, line[:places_place_id].to_s].max
      line[:original_latitude] = (line[:table_latitude] || line[:places_latitude])
      line[:original_longitude] = (line[:table_longitude] || line[:places_longitude])

      if line[:company] && line[:address]
        line[:using] = :google_places_autocomplete_company_city_and_state
        address_result = Geocoder.search("#{line[:address]}", lookup: :google).first
        if address_result.present?
          query = "#{line[:company]}, #{address_result.city} #{address_result.state_code}"
          autocomplete_result = Geocoder.search(query, lookup: :google_places_autocomplete).first
          result = Geocoder.search(autocomplete_result.place_id, lookup: :google_places_details).first if autocomplete_result.present?
        end
      end

      if !matches(line, result) && line[:company] && line[:address]
        line[:using] = :google_places_autocomplete_company_and_postal
        address_result = Geocoder.search("#{line[:address]}", lookup: :google).first
        if address_result.present?
          query = "#{line[:company]}, #{address_result.postal_code}"
          autocomplete_result = Geocoder.search(query, lookup: :google_places_autocomplete).first
          result = Geocoder.search(autocomplete_result.place_id, lookup: :google_places_details).first if autocomplete_result.present?
        end
      end

      if !matches(line, result) && line[:company] && line[:address]
        line[:using] = :google_places_autocomplete_company_and_address
        query = "#{line[:company]}, #{line[:address]}"
        autocomplete_result = Geocoder.search(query, lookup: :google_places_autocomplete).first
        result = Geocoder.search(autocomplete_result.place_id, lookup: :google_places_details).first if autocomplete_result.present?
      end

      if !matches(line, result) && line[:address].present?
        query = line[:address]
        line[:using] = :google_places_autocomplete_address
        result = Geocoder.search(query, lookup: :google_places_autocomplete).first
        result = Geocoder.search(result.place_id, lookup: :google_places_details).first if result.present?
      end

      if !matches(line, result) && line[:company] && line[:address]
        query = "#{line[:company]}, #{line[:address]}"
        line[:using] = :google_company_and_address
        result = Geocoder.search(query, lookup: :google).first
      end

      if !matches(line, result) && line[:address].present?
        query = line[:address]
        line[:using] = :google_address
        result = Geocoder.search(query, lookup: :google).first
      end

      if !matches(line, result) && line[:table_latitude].present? && line[:table_longitude].present?
        query = [line[:table_latitude], line[:table_longitude]]
        line[:using] = :google_table_lat_lng
        result = Geocoder.search(query, lookup: :google).first
      end

      possible_issues = []
      if result.present?
        line[:geocoded_company] = result.data['name']
        line[:geocoded_place_id] = result.place_id
        line[:geocoded_latitude] = result.latitude
        line[:geocoded_longitude] = result.longitude
        line[:geocoded_address] = result.address
        line[:geocoded_street_address] = result.street_address
        line[:geocoded_city] = result.city
        line[:geocoded_state] = result.state_code
        line[:geocoded_sub_state] = result.sub_state
        line[:geocoded_postal_code] = result.postal_code
        line[:geocoded_country] = result.country_code


        if (line[:original_latitude].present? && line[:original_longitude].present?) &&
          (line[:geocoded_latitude] != line[:original_latitude] || line[:geocoded_longitude] != line[:original_longitude])
          possible_issues << :lat_lng_mismatch
        else
          possible_issues << :missing_lat_lng
        end

        if line[:original_place_id].present? && line[:geocoded_place_id] != line[:original_place_id]
          possible_issues << :place_id_mismatch
        end
      else
        possible_issues << :geocode_failed
      end

      line[:possible_issues] = possible_issues.compact.join(", ")

      puts "#{line[:table]}:#{line[:table_id]}:#{line[:account_id]} - #{line[:geocoded_address]}" +
        " [#{line[:geocoded_latitude]}, #{line[:geocoded_longitude]}]" +
        " [#{line[:geocoded_place_id]}, #{line[:original_place_id]}]" +
        " using #{line[:using]}"

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
