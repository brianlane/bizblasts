require "rails_helper"

RSpec.describe EstimateMailer, type: :mailer do
  let(:business) { create(:business) }
  let(:estimate) { create(:estimate, business: business) }

  describe "send_estimate" do
    let(:mail) { EstimateMailer.send_estimate(estimate) }

    it "renders the headers" do
      expected_subject = "#{estimate.business.name} - Estimate #{estimate.estimate_number || "##{estimate.id}"}"
      expect(mail.subject).to eq(expected_subject)
      expect(mail.to).to eq([estimate.customer_email])
      expect(mail.from).to eq([ENV.fetch('MAILER_EMAIL')])
    end

    it "renders the body" do
      expect(mail.body.encoded).to include("Your estimate for #{estimate.business.name} is ready for review.")
    end
  end

  describe "estimate_approved" do
    let!(:manager) { create(:user, role: :manager, business: business) }
    let(:mail) { EstimateMailer.estimate_approved(estimate) }

    it "renders the headers" do
      expected_subject = "Estimate #{estimate.estimate_number || "##{estimate.id}"} Approved by Customer"
      expect(mail.subject).to eq(expected_subject)
      expect(mail.to).to include(manager.email)
    end
  end
end 