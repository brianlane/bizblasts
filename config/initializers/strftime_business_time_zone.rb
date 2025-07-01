# NOTE: strftime override is disabled in favor of per-request time.zone setting in ApplicationController
# ActiveSupport::TimeWithZone.class_eval do
#   alias_method :orig_strftime, :strftime
#
#   def strftime(fmt)
#     tz = ActsAsTenant.current_tenant&.time_zone.presence || nil
#     if tz && tz != 'UTC'
#       in_time_zone(tz).orig_strftime(fmt)
#     else
#       orig_strftime(fmt)
#     end
#   end
# end 