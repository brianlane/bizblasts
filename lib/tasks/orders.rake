namespace :orders do
  desc 'Auto cancel unpaid product orders after tier-specific deadlines'
  task auto_cancel_unpaid: :environment do
    AutoCancelUnpaidProductOrdersJob.perform_now
  end
end 