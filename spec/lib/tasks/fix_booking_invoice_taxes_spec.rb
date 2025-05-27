require 'rails_helper'
require 'rake'

RSpec.describe 'invoices:fix_booking_taxes rake task' do
  before do
    Rake.application.rake_require 'tasks/fix_booking_invoice_taxes'
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['invoices:fix_booking_taxes'] }
  let!(:business) { create(:business) }
  let!(:default_tax_rate) { create(:tax_rate, business: business, name: 'Default Tax', rate: 0.098) }
  let!(:service) { create(:service, business: business, price: 100.00) }
  let!(:staff_member) { create(:staff_member, business: business) }
  let!(:tenant_customer) { create(:tenant_customer, business: business) }
  let!(:booking) { create(:booking, business: business, service: service, staff_member: staff_member, tenant_customer: tenant_customer) }

  before do
    # Clear any previous invocations
    task.reenable
  end

  context 'when there are booking-based invoices without tax rates' do
    let!(:invoice_without_tax) do
      create(:invoice, 
        business: business, 
        tenant_customer: tenant_customer, 
        booking: booking,
        tax_rate: nil,
        original_amount: 100.00,
        amount: 100.00,
        tax_amount: 0.00,
        total_amount: 100.00
      )
    end

    it 'fixes invoices by adding tax rates and recalculating totals' do
      expect(invoice_without_tax.tax_rate).to be_nil
      expect(invoice_without_tax.tax_amount).to eq(0.00)
      expect(invoice_without_tax.total_amount).to eq(100.00)

      expect { task.invoke }.to output(/Fixed: 1 invoices/).to_stdout

      invoice_without_tax.reload
      expect(invoice_without_tax.tax_rate).to eq(default_tax_rate)
      expect(invoice_without_tax.tax_amount).to be_within(0.01).of(9.80) # 9.8% of $100
      expect(invoice_without_tax.total_amount).to be_within(0.01).of(109.80) # $100 + $9.80 tax
    end
  end

  context 'when business has no default tax rate' do
    let!(:business_without_tax) { create(:business) }
    let!(:service_without_tax) { create(:service, business: business_without_tax, price: 50.00) }
    let!(:staff_without_tax) { create(:staff_member, business: business_without_tax) }
    let!(:customer_without_tax) { create(:tenant_customer, business: business_without_tax) }
    let!(:booking_without_tax) { create(:booking, business: business_without_tax, service: service_without_tax, staff_member: staff_without_tax, tenant_customer: customer_without_tax) }
    let!(:invoice_no_business_tax) do
      create(:invoice, 
        business: business_without_tax, 
        tenant_customer: customer_without_tax, 
        booking: booking_without_tax,
        tax_rate: nil
      )
    end

    it 'warns about businesses without default tax rates' do
      expect { task.invoke }.to output(/Warning: Business .* has no default tax rate/).to_stdout
    end
  end

  context 'when all booking-based invoices already have tax rates' do
    let!(:invoice_with_tax) do
      create(:invoice, 
        business: business, 
        tenant_customer: tenant_customer, 
        booking: booking,
        tax_rate: default_tax_rate
      )
    end

    it 'reports no invoices to fix' do
      expect { task.invoke }.to output(/Found 0 booking-based invoices without tax rates/).to_stdout
    end
  end
end 