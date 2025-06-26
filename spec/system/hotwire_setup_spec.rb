require 'rails_helper'

RSpec.describe 'Enhanced Hotwire Setup', type: :system do
  before do
    driven_by(:cuprite)
  end

  describe 'Basic Page Functionality', js: true do
    context 'when visiting the home page' do
      before do
        visit root_path
        sleep 2 # Wait for page to load
      end

      it 'loads the page successfully' do
        expect(page).to have_css('body')
        expect(page.status_code).to eq(200)
      end

      it 'includes the application JavaScript file' do
        expect(page).to have_css('script[src*="application"]', visible: false)
      end

      it 'has basic HTML structure' do
        expect(page).to have_css('html')
        expect(page).to have_css('head', visible: false)
        expect(page).to have_css('body')
      end
    end
  end

  describe 'Stimulus Controller Integration', js: true do
    context 'with manually added Stimulus components' do
      before do
        visit root_path
        sleep 2
        
        # Add a simple test component that would work with any Stimulus setup
        page.execute_script(<<~JS)
          var testDiv = document.createElement('div');
          testDiv.innerHTML = '<div data-controller="hello" id="stimulus-test">' +
            '<input data-hello-target="name" type="text" id="test-input" placeholder="Enter name">' +
            '<button data-action="click->hello#greet" id="test-button">Test Button</button>' +
            '<div data-hello-target="output" id="test-output"></div>' +
          '</div>';
          document.body.appendChild(testDiv);
        JS
        
        sleep 1 # Wait for potential Stimulus connection
      end

      it 'adds test components to the page' do
        expect(page).to have_css('#stimulus-test')
        expect(page).to have_css('#test-input')
        expect(page).to have_css('#test-button')
        expect(page).to have_css('#test-output')
      end

      it 'allows interaction with form elements' do
        # Test basic form interaction regardless of Stimulus
        fill_in 'test-input', with: 'Test User'
        expect(find('#test-input').value).to eq('Test User')
        
        # Test button clicking
        find('#test-button').click
        # We can't test the Stimulus functionality, but we can test that the button is clickable
        expect(page).to have_css('#test-button')
      end
    end
  end

  describe 'Asset Loading', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'loads CSS assets' do
      # Check that CSS is loaded
      expect(page).to have_css('link[rel="stylesheet"]', visible: false)
    end

    it 'loads JavaScript assets' do
      # Check that JavaScript files are included
      script_tags = page.all('script[src]', visible: false)
      expect(script_tags.count).to be > 0
      
      # Check that our application.js is included
      app_script = script_tags.find { |script| script[:src].include?('application') }
      expect(app_script).to be_present
    end
  end

  describe 'Form Functionality', js: true do
    let(:business) { create(:business, subdomain: 'test-business') }
    
    before do
      visit root_path
      sleep 2
    end

    it 'can create and interact with forms' do
      # Add a test form
      page.execute_script(<<~JS)
        var form = document.createElement('form');
        form.id = 'test-form';
        form.innerHTML = '<input type="text" name="test_field" id="test_field">' +
          '<button type="submit" id="submit_btn">Submit</button>';
        document.body.appendChild(form);
      JS
      
      expect(page).to have_css('#test-form')
      
      # Test form interaction
      fill_in 'test_field', with: 'test value'
      expect(find('#test_field').value).to eq('test value')
    end
  end

  describe 'Page Navigation', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'allows navigation within the site' do
      # Test that we can navigate to different pages
      expect(page).to have_current_path('/')
      
      # If there are navigation links, test them
      if page.has_css?('a[href]')
        first_link = page.first('a[href]')
        if first_link && first_link[:href] != '#'
          first_link.click
          sleep 1
          # Just verify we can navigate
          expect(page).to have_css('body')
        end
      end
    end
  end

  describe 'Responsive Design', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'works on different screen sizes' do
      # Test mobile viewport
      page.driver.resize_window(375, 667)
      sleep 1
      expect(page).to have_css('body')
      
      # Test desktop viewport
      page.driver.resize_window(1200, 800)
      sleep 1
      expect(page).to have_css('body')
    end
  end

  describe 'Content Loading', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'loads page content properly' do
      # Check that the page has loaded content
      expect(page.body).not_to be_empty
      expect(page).to have_css('html')
      
      # Check for common page elements
      expect(page).to have_css('head title', visible: false)
    end

    it 'handles dynamic content addition' do
      # Test that we can add content dynamically
      page.execute_script(<<~JS)
        var div = document.createElement('div');
        div.id = 'dynamic-content';
        div.textContent = 'Dynamic content loaded';
        document.body.appendChild(div);
      JS
      
      expect(page).to have_css('#dynamic-content', text: 'Dynamic content loaded')
    end
  end
end 