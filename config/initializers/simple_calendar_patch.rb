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

    # Override td_classes_for to properly handle custom date ranges
    # This prevents current month days from being marked as prev-month or next-month
    unless method_defined?(:orig_td_classes_for)
      alias_method :orig_td_classes_for, :td_classes_for
    end

    def td_classes_for(day)
      if options[:start_date] && options[:end_date] && options[:today]
        # Use original behavior but adjust month logic for custom ranges
        classes = orig_td_classes_for(day)
        
        # Remove incorrect prev-month/next-month classes and add correct ones
        classes = classes.reject { |c| c == 'prev-month' || c == 'next-month' }
        
        target_month = options[:today].to_date.month
        target_year = options[:today].to_date.year
        
        # Only mark as prev/next month if it's from a different month than the target
        if day.year < target_year || (day.year == target_year && day.month < target_month)
          classes << 'prev-month'
        elsif day.year > target_year || (day.year == target_year && day.month > target_month)
          classes << 'next-month'
        end
        
        classes
      else
        # Use original behavior for standard month calendars
        orig_td_classes_for(day)
      end
    end
  end
end 