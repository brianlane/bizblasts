require "rails_helper"

RSpec.describe EstimateMailer, type: :mailer do
  let(:estimate) { create(:estimate) }

  describe "send_estimate" do
    let(:mail) { EstimateMailer.send_estimate(estimate) }

    it "renders the headers" do
      expect(mail.subject).to eq("Your Estimate ##{estimate.id} from #{estimate.business.name}")
      expect(mail.to).to eq([estimate.customer_email])
      expect(mail.from).to eq([ENV.fetch('MAILER_EMAIL')])
    end

    it "renders the body" do
      expect(mail.body.encoded).to include("Your estimate for #{estimate.business.name} is ready for review.")
    end
  end

  describe "estimate_approved" do
    let(:mail) { EstimateMailer.estimate_approved(estimate) }

    it "renders the headers" do
      expect(mail.subject).to eq("Estimate ##{estimate.id} Approved")
    end
  end
end 