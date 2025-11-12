RSpec.configure do |config|
  config.before(:each) do
    logger = Rails.logger
    next unless logger

    %i[debug info warn error fatal unknown].each do |level|
      next unless logger.respond_to?(level)

      allow(logger).to receive(level).and_call_original
    end
  end
end

