# frozen_string_literal: true

# Helper methods for ServiceAreaChecker specs to properly mock geocoding
module ServiceAreaCheckerTestHelpers
  def mock_geocoding_for_zip(zip, coordinates, use_structured_search: true)
    if use_structured_search
      # Mock structured search response
      result = OpenStruct.new(
        coordinates: coordinates,
        latitude: coordinates[0],
        longitude: coordinates[1],
        country_code: 'us'
      )

      allow_any_instance_of(ServiceAreaChecker).to receive(:geocode_with_structured_search)
        .with(zip).and_return([result])
    else
      # Mock fallback to regular Geocoder.search
      allow(Geocoder).to receive(:search).with("#{zip}, USA").and_return([
        double(coordinates: coordinates)
      ])
    end
  end

  def mock_coordinates_for(checker_instance, zip, coordinates)
    unless checker_instance.instance_variable_defined?(:@__original_coordinates_for__)
      checker_instance.instance_variable_set(:@__original_coordinates_for__, checker_instance.method(:coordinates_for))
    end

    mapped_coordinates = checker_instance.instance_variable_get(:@__mock_coordinates_map__) || {}
    mapped_coordinates[zip] = coordinates
    checker_instance.instance_variable_set(:@__mock_coordinates_map__, mapped_coordinates)

    allow(checker_instance).to receive(:coordinates_for) do |arg|
      mapping = checker_instance.instance_variable_get(:@__mock_coordinates_map__) || {}
      if mapping.key?(arg)
        mapping[arg]
      else
        checker_instance.instance_variable_get(:@__original_coordinates_for__).call(arg)
      end
    end
  end
end

RSpec.configure do |config|
  config.include ServiceAreaCheckerTestHelpers, type: :service
end
