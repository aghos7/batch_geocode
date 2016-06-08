#!/usr/bin/env ruby
require 'csv'
require 'date'
require 'yaml'
require 'geocoder'
# require 'byebug'
require 'optparse'
require 'active_support/all'
require_relative 'wiw'

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

def score_results(results, line, opts = {})
  results.each do |result|
    # Score based on lat/lng
    if result.latitude.present? && result.longitude.present?
      lat = result.latitude.try(:to_f).try(:round, opts[:lat_lng_scale])
      lng = result.longitude.try(:to_f).try(:round, opts[:lat_lng_scale])
      if [lat, lng] == [line[:using_latitude], line[:using_longitude]]
        result.score += 1000
        result.scored_by << :lat_lng
      end

      if line[:using_latitude].present? && line[:using_longitude].present?
        # Penalize lat/lng score based on distance, farther away decreases score
        result.score -= Geocoder::Calculations.distance_between(
          result.coordinates,
          [line[:using_latitude], line[:using_longitude]])
        result.scored_by << :lat_lng_distance
      end
    end
    # Score based on Company
    if result.data['name'].try(:present?) && result.data['name'].try(:downcase) == line[:using_company].try(:downcase)
      result.score += 1500
      result.scored_by << :company
    end
    # Score based on Street Address
    if result.address_result.street_address == result.street_address
      result.score += (result.lookup == :google ? 800 : 1500)
      result.scored_by << :street_address
    end
    # Score based on City
    if result.address_result.city == result.city
      result.score += (result.lookup == :google ? 250 : 500)
      result.scored_by << :city
    end
    # Score based on State
    if result.address_result.state_code == result.state_code
      result.score += 750
      result.scored_by << :state
    end
    # Score based on Postal Code
    if result.address_result.postal_code == result.postal_code
      result.score += 250
      result.scored_by << :postal
    end
    # Score based on Country
    if result.address_result.country_code == result.country_code
      result.score += 100
      result.scored_by << :country
    end
    # Score types
    if ((result.types || []) & [opts[:limit_types]].flatten).any?
      result.score += 1500
      result.scored_by << :place_type
    end
    # Score table_place_id
    if result.place_id.present? && result.place_id == line[:table_place_id]
      result.score += (result.lookup == :google ? 500 : 500000)
      result.scored_by << :table_place_id
    end
    # Score places_place_id
    if result.place_id.present? && result.place_id == line[:places_place_id]
      result.score += (result.lookup == :google ? 1500 : 1000000)
      result.scored_by << :places_place_id
    end
    # Penalize google maps results
    if result.lookup == :google
      result.scored_by << :google_maps_penalty
    end
  end
end

def search(query, opts={})
  results = Geocoder.search(query, opts)
  sleep (opts[:sleep] || @options[:sleep]) # ick
  results
end

def line_defaults(line, opts={})
  line[:using_place_id] ||= ""
  line[:using_latitude] ||= ""
  line[:using_longitude] ||= ""
  line[:using_company] ||= ""
  line[:using_address] ||= ""
  line[:geocoded_company] ||= ""
  line[:geocoded_place_id] ||= ""
  line[:geocoded_latitude] ||= ""
  line[:geocoded_longitude] ||= ""
  line[:geocoded_address] ||= ""
  line[:geocoded_street_address] ||= ""
  line[:geocoded_city] ||= ""
  line[:geocoded_state] ||= ""
  line[:geocoded_sub_state] ||= ""
  line[:geocoded_postal_code] ||= ""
  line[:geocoded_country] ||= ""
  line[:geocoded_types] ||= ""
  line[:geocoded_wiw_industry] ||= ""
  line[:geocoded_score] ||= ""
  line[:geocoded_scored_by] ||= ""
  line[:geocoded_lookup] ||= ""
  line[:possible_issues] ||= ""
  line[:geocoded_status] ||= ""
end

def log_line(line, opts={})
  puts "--------------------------------------------------------------------------------"
  puts "#{line[:table]}:#{line[:table_id]}:#{line[:account_id]}"
  puts "using company: #{line[:using_company]}"
  puts "using address: #{line[:using_address]}"
  puts "using place_id: #{line[:using_place_id]}"
  puts "geo company: #{line[:geocoded_company]}"
  puts "geo address: #{line[:geocoded_address]}"
  puts "geo place_id #{line[:geocoded_place_id]}"
  puts "lookup: #{line[:geocoded_lookup]}"
  puts "score: #{line[:geocoded_score]}"
  puts "scored by: #{line[:geocoded_scored_by]}"
  puts "industry: #{line[:geocoded_wiw_industry]}"
  puts "issues: #{line[:possible_issues]}"
  puts "status: #{line[:geocoded_status]}"
end

def possible_issues(line, result, opts={})
  issues = []
  if line[:using_latitude].present? && line[:using_longitude].present?
    if [line[:geocoded_latitude], line[:geocoded_longitude]] != [line[:using_latitude], line[:using_longitude]]
      issues << :lat_lng_mismatch
    end
  else
    issues << :missing_lat_lng
  end

  if line[:using_place_id].present?
    if line[:geocoded_place_id].to_s != line[:using_place_id].to_s
      issues << :place_id_mismatch
    end
  else
    issues << :missing_place_id
  end

  if line[:geocoded_company].present? && line[:geocoded_company] != line[:using_company]
    issues << :company_mismatch
  end

  if result.try(:street_address).present? && result.street_address != result.address_result.try(:street_address)
    issues << :street_address_mismatch
  end

  if result.try(:city).present? && result.city != result.address_result.try(:city)
    issues << :city_mismatch
  end

  if result.try(:state_code).present? && result.state_code != result.address_result.try(:state_code)
    issues << :state_mismatch
  end

  if result.try(:postal_code).present? && result.postal_code != result.address_result.try(:postal_code)
    issues << :postal_mismatch
  end

  if result.try(:country_code).present? && result.country_code != result.address_result.try(:country_code)
    issues << :country_mismatch
  end
  issues
end

@options = {}

# Load config
begin
  yaml = YAML.load_file("config.yml")
  @options[:input_file] = yaml['input_file'] || 'input.csv'
  @options[:output_file] = yaml['output_file'] || 'output.csv'
  @options[:geocoder_api_key] = yaml['geocoder_api_key']
  @options[:lat_lng_scale] = yaml['lat_lng_scale'].try(:to_i) || 8
  @options[:sleep] = yaml[:sleep].try(:to_f) || 0
  @options[:line_sleep] = yaml[:line_sleep].try(:to_f) || 1
  @options[:always_raise] = yaml[:always_raise] || :all
  @options[:skip_status] = yaml[:skip_status].try(:split, ',') || nil
  @options[:exclude_skipped] = yaml[:exclude_skipped] == "true" || false
rescue Errno::ENOENT
  puts "config file not found"
end

# read command line options
OptionParser.new do |opt|
  opt.on('-i input_file', '--input_file input_file', 'Input file') { |o| @options[:input_file] = o }
  opt.on('-o output_file', '--output_file output_file', 'Output file') { |o| @options[:output_file] = o }
  opt.on('-k api_key', '--api_key api_key', 'Geocoder API Key') { |o| @options[:geocoder_api_key] = o }
  opt.on('-s skip_status', '--skip_status skip_status', 'Statuses to skip') { |o| @options[:skip_status] = o.try(:split, ',') }
  opt.on('-e exclude_skipped', '--exclude_skipped exclude_skipped', 'Exclude skipped from output - true/false') do |o|
    @options[:exclude_skipped] = (o == "true")
  end
end.parse!

# config geocoder
Geocoder.configure(
  use_https: true,
  # to use an API key:
  api_key: @options[:geocoder_api_key],
  timeout: 10,
  always_raise: @options[:always_raise]
)

# read each line of input file, geocode and output results
puts "reading address file"
# write to CSV
CSV.open(@options[:output_file], "wb") do |csv|
  line_number = 0
  CSV.foreach(@options[:input_file], headers: true, header_converters: :symbol) do |line|
    begin
      result = nil
      line_defaults(line)
      if line_number == 0
        csv << line.headers
      end
      line_number += 1
      if @options[:skip_status].present? && @options[:skip_status].include?(line[:geocoded_status])
        csv << line unless @options[:exclude_skipped]
        puts "skipping status: #{line[:geocoded_status]}"
        next
      end

      match_options = {}
      query_params = {}
      if line[:table] == 'accounts'
        match_options[:limit_types] = 'establishment'
        query_params[:types] = 'establishment'
      end
      match_options[:match_place_id] = true

      line[:using_place_id] = (line[:places_place_id] || line[:table_place_id]).to_s
      line[:using_latitude] = (line[:places_latitude] || line[:table_latitude]).try(:to_f).try(:round, @options[:lat_lng_scale])
      line[:using_longitude] = (line[:places_longitude] || line[:table_longitude]).try(:to_f).try(:round, @options[:lat_lng_scale])

      results = []
      [line[:address], line[:account_address]].compact.uniq.each do |address|
        search("#{address}", lookup: :google).each do |address_result|
          [line[:company], line[:account_company]].compact.uniq.each do |company|
            queries = []
            queries << {
              name: :company_address,
              text: "#{company}, #{address}",
              score: 2000 }
            queries << {
              name: :company_postal,
              text: "#{company}, #{address_result.postal_code}",
              score: 1000 }
            queries << {
              name: :company_city_state,
              text: "#{company}, #{address_result.city} #{address_result.state_code}",
              score: 500 }
            queries << {
              name: :company,
              text: "#{company}",
              score: 100 }
            queries << {
              name: :address,
              text: "#{address}",
              score: 100 }
            queries.each do |query|
              search(query[:text], lookup: :google_places_autocomplete, params: query_params).each do |autocomplete_result|
                results += search(autocomplete_result.place_id, lookup: :google_places_details).each do |result|
                  class << result
                    attr_accessor :lookup
                  end
                  result.lookup = :google_places_autocomplete
                end
              end
              results += search(query[:text], lookup: :google, params: query_params).each do |result|
                class << result
                  attr_accessor :lookup
                end
                result.lookup = :google
              end
              results.each do |result|
                class << result
                  attr_accessor :using_company
                  attr_accessor :using_address
                  attr_accessor :address_result
                  attr_accessor :scored_by
                  attr_accessor :query
                  attr_accessor :score
                end
                result.using_company = company
                result.using_address = address
                result.address_result = address_result
                result.scored_by = [query[:name]]
                result.query = query
                result.score = query[:score]
              end
            end
          end
        end
      end
      results.uniq!{ |result| result.place_id }
      score_results(results, line, @options.merge(match_options))
      results.sort_by!{ |result| -result.score }

      result = results.first

      line[:using_company] = result.try(:using_company)
      line[:using_address] = result.try(:using_address)
      line[:geocoded_company] = result.try(:data).try(:[], 'name')
      line[:geocoded_place_id] = result.try(:place_id)
      line[:geocoded_latitude] = result.try(:latitude).try(:to_f).try(:round, @options[:lat_lng_scale])
      line[:geocoded_longitude] = result.try(:longitude).try(:to_f).try(:round, @options[:lat_lng_scale])
      line[:geocoded_address] = result.try(:address)
      line[:geocoded_street_address] = result.try(:street_address)
      line[:geocoded_city] = result.try(:city)
      line[:geocoded_state] = result.try(:state_code)
      line[:geocoded_sub_state] = result.try(:sub_state)
      line[:geocoded_postal_code] = result.try(:postal_code)
      line[:geocoded_country] = result.try(:country_code)
      line[:geocoded_types] = result.try(:types).try(:join, ',')
      line[:geocoded_wiw_industry] = Wiw::google_place_types_to_industry_ids(result.try(:types)).first || Wiw::INDUSTRIES['Other']
      line[:geocoded_score] = result.try(:score)
      line[:geocoded_scored_by] = result.try(:scored_by).try(:join, ',')
      line[:geocoded_lookup] = result.try(:lookup)
      line[:possible_issues] = possible_issues(line, result).compact.join(',')
      line[:geocoded_status] = result.present? ? :success : :geocode_failed

      log_line(line)

      csv << line
    rescue Geocoder::Error => e
      line[:geocoded_status] = e.to_s
      log_line(line)
      csv << line
    rescue => e
      puts "processing error #{e.to_s}"
      puts line.inspect
    end
    sleep @options[:line_sleep]
  end
end

puts "done"
nil
