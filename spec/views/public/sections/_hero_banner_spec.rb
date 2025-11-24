require 'rails_helper'

RSpec.describe "public/sections/_hero_banner", type: :view do
  let(:business) do
    create(
      :business,
      city: 'Mesa',
      state: 'Arizona',
      phone: '480-555-1234',
      industry: :consulting
    )
  end

  let(:page) { create(:page, business: business, page_type: :home) }

  let(:section) do
    create(
      :page_section,
      page: page,
      section_type: :hero_banner,
      content: {
        'title' => 'Consult LLC',
        'subtitle' => 'Consulting test company',
        'button_text' => 'Book Now'
      },
      section_config: {
        'theme' => 'dark_showcase'
      }
    )
  end

  before do
    allow(view).to receive(:book_now_path_with_service_area).and_return('/book-now')
    allow(view).to receive(:tenant_calendar_path).and_return('/calendar')
  end

  it 'renders the business phone number when present' do
    render partial: "public/sections/hero_banner", locals: { section: section, business: business }

    expect(rendered).to include(business.phone)
  end
end



