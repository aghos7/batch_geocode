module Wiw
  INDUSTRIES = {
    "Food Service / Hospitality" => 1,
    "Restaurant / Cafe" => 2,
    "QSR / Fast Casual" => 3,
    "Bar / Club / Sports Bar" => 4,
    "Coffee Shops" => 5,
    "Catering / Events" => 6,
    "Hotel / Resorts" => 7,
    "Other Hospitality" => 8,
    "Professional Service / Education" => 9,
    "Parking / Valet Service" => 10,
    "University / College / School" => 11,
    "Law Enforcement / Security" => 12,
    "Personal Care / Salon / Massage" => 13,
    "Non-profit / Volunteer" => 14,
    "Other Professional Service" => 15,
    "Healthcare / Medical" => 16,
    "Adult Care Agency" => 17,
    "Assisted Living / Care Center" => 18,
    "Hospitalist Organization" => 19,
    "Pharmacy" => 20,
    "Dental Practice" => 21,
    "Other Healthcare / Medical" => 22,
    "Entertainment / Seasonal" => 23,
    "Zoo / Aquarium" => 24,
    "Theme Park / Seasonal" => 25,
    "Ski Area / Seasonal" => 26,
    "Other Entertainment Services" => 27,
    "Retail" => 28,
    "Retail Store" => 29,
    "Wireless Retail Store" => 30,
    "Electronics" => 31,
    "Other Retail" => 32,
    "Fire Department / EMS" => 33,
    "Hardware / Home Improvement" => 34,
    "Food Truck / Mobile" => 35,
    "Cleaning Service" => 36,
    "Music / Dance / Art" => 37,
    "Call Center" => 38,
    "Veterinary / Animal Care" => 39,
    "Pet Care / Boarding" => 40,
    "Parks / Recreation" => 42,
    "Other" => 45,
    "Technology / Software" => 48,
    "Sharing Economy" => 51,
    "Customer Support/Care" => 54,
    "Other Software / Technology" => 57
  }

  def self.google_place_types_to_industry_ids(types)
    result = []
    regexes = Wiw::google_place_types_to_regexes(types)
    regexes.map do |regex|
      Wiw::INDUSTRIES.map do |industry, id|
        result << id if industry.to_s.scan(regex).present?
      end
    end
    result
  end

  def self.google_place_types_to_regexes(types)
    types.map do |type|
      Regexp.new('(?:' + (type.downcase.split('_') - ['of', 'or']).join('|') + ')', Regexp::IGNORECASE)
    end
  end
end
