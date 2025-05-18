# Patches SimpleCalendar to allow month_calendar to use custom date ranges when start_date and end_date options are provided
Rails.application.config.to_prepare do
  SimpleCalendar::MonthCalendar.class_eval do
    # Alias the original date_range method to preserve month-based behavior
    unless method_defined?(:orig_date_range)
      alias_method :orig_date_range, :date_range
    end

    # Override date_range to use custom range if end_date option is present
    def date_range
      if options[:start_date] && options[:end_date]
        # Use the exact range provided by options
        (options[:start_date].to_date..options[:end_date].to_date).to_a
      else
        # Fallback to the original month-based range
        orig_date_range
      end
    end
  end
end 