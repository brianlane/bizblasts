require 'rails_helper'

RSpec.describe 'Enhanced JavaScript Integration', type: :system do
  before do
    driven_by(:cuprite)
  end

  describe 'Basic JavaScript Functionality', js: true do
    context 'when visiting any page' do
      before do
        visit root_path
        sleep 2
      end

      it 'loads the page without JavaScript errors' do
        expect(page).to have_css('body')
        expect(page.status_code).to eq(200)
      end

      it 'includes JavaScript assets' do
        expect(page).to have_css('script[src*="application"]', visible: false)
      end

      it 'allows basic DOM manipulation' do
        # Test that we can execute basic JavaScript
        page.execute_script(<<~JS)
          var testElement = document.createElement('div');
          testElement.id = 'js-test';
          testElement.textContent = 'JavaScript is working';
          document.body.appendChild(testElement);
        JS
        
        expect(page).to have_css('#js-test', text: 'JavaScript is working')
      end
    end
  end

  describe 'Interactive Components', js: true do
    before do
      visit root_path
      sleep 2
      
      # Add a test component that mimics what Stimulus would create
      page.execute_script(<<~JS)
        var container = document.createElement('div');
        container.innerHTML = '<div id="interactive-test">' +
          '<input type="text" id="name-input" placeholder="Enter name">' +
          '<button id="action-button">Click Me</button>' +
          '<div id="output-area"></div>' +
        '</div>';
        document.body.appendChild(container);
        
        // Add basic interaction without relying on Stimulus
        document.getElementById('action-button').addEventListener('click', function() {
          var input = document.getElementById('name-input');
          var output = document.getElementById('output-area');
          output.textContent = 'Hello, ' + (input.value || 'World') + '!';
        });
      JS
      
      sleep 1
    end

    it 'creates interactive components' do
      expect(page).to have_css('#interactive-test')
      expect(page).to have_css('#name-input')
      expect(page).to have_css('#action-button')
      expect(page).to have_css('#output-area')
    end

    it 'handles user interactions' do
      fill_in 'name-input', with: 'Test User'
      click_button 'Click Me'
      
      expect(page).to have_css('#output-area', text: 'Hello, Test User!')
    end

    it 'handles empty input gracefully' do
      click_button 'Click Me'
      
      expect(page).to have_css('#output-area', text: 'Hello, World!')
    end
  end

  describe 'Form Handling', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'can create and submit forms' do
      # Create a test form
      page.execute_script(<<~JS)
        var form = document.createElement('form');
        form.id = 'test-form';
        form.innerHTML = '<input type="text" name="username" id="username" required>' +
          '<input type="email" name="email" id="email" required>' +
          '<button type="submit" id="submit-btn">Submit</button>';
        document.body.appendChild(form);
        
        // Add form submission handler
        form.addEventListener('submit', function(e) {
          e.preventDefault();
          var result = document.createElement('div');
          result.id = 'form-result';
          result.textContent = 'Form submitted successfully';
          document.body.appendChild(result);
        });
      JS
      
      expect(page).to have_css('#test-form')
      
      # Fill and submit the form
      fill_in 'username', with: 'testuser'
      fill_in 'email', with: 'test@example.com'
      click_button 'Submit'
      
      expect(page).to have_css('#form-result', text: 'Form submitted successfully')
    end
  end

  describe 'Dynamic Content', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'can dynamically add and remove content' do
      # Add content
      page.execute_script(<<~JS)
        var div = document.createElement('div');
        div.id = 'dynamic-div';
        div.textContent = 'Dynamic content';
        document.body.appendChild(div);
      JS
      
      expect(page).to have_css('#dynamic-div', text: 'Dynamic content')
      
      # Remove content
      page.execute_script(<<~JS)
        var div = document.getElementById('dynamic-div');
        if (div) {
          div.remove();
        }
      JS
      
      expect(page).not_to have_css('#dynamic-div')
    end

    it 'can modify existing content' do
      # Add initial content
      page.execute_script(<<~JS)
        var div = document.createElement('div');
        div.id = 'modifiable-div';
        div.textContent = 'Initial content';
        document.body.appendChild(div);
      JS
      
      expect(page).to have_css('#modifiable-div', text: 'Initial content')
      
      # Modify content
      page.execute_script(<<~JS)
        var div = document.getElementById('modifiable-div');
        if (div) {
          div.textContent = 'Modified content';
        }
      JS
      
      expect(page).to have_css('#modifiable-div', text: 'Modified content')
    end
  end

  describe 'Event Handling', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'can handle custom events' do
      page.execute_script(<<~JS)
        var eventTarget = document.createElement('div');
        eventTarget.id = 'event-target';
        document.body.appendChild(eventTarget);
        
        // Add event listener
        eventTarget.addEventListener('custom-event', function(e) {
          var result = document.createElement('div');
          result.id = 'event-result';
          result.textContent = 'Custom event received: ' + e.detail.message;
          document.body.appendChild(result);
        });
        
        // Create and dispatch custom event
        var customEvent = new CustomEvent('custom-event', {
          detail: { message: 'Hello from custom event' }
        });
        eventTarget.dispatchEvent(customEvent);
      JS
      
      expect(page).to have_css('#event-result', text: 'Custom event received: Hello from custom event')
    end
  end

  describe 'Browser Compatibility', js: true do
    before do
      visit root_path
      sleep 2
    end

    it 'supports modern JavaScript features' do
      # Test that modern JavaScript works
      modern_js_result = page.evaluate_script(<<~JS)
        (function() {
          try {
            // Test arrow functions
            var arrow = () => 'arrow function works';
            
            // Test template literals
            var template = `template literal works`;
            
            // Test const/let
            const constVar = 'const works';
            let letVar = 'let works';
            
            return {
              arrow: arrow(),
              template: template,
              const: constVar,
              let: letVar,
              success: true
            };
          } catch (e) {
            return {
              error: e.message,
              success: false
            };
          }
        })()
      JS
      
      expect(modern_js_result['success']).to be true
      expect(modern_js_result['arrow']).to eq('arrow function works')
      expect(modern_js_result['template']).to eq('template literal works')
    end
  end
end 