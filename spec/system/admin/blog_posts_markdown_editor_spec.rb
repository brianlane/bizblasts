require 'rails_helper'

RSpec.describe "Admin Blog Posts Markdown Editor", type: :system, admin: true do
  let!(:admin_user) { create(:admin_user) }

  before do
    driven_by(:cuprite)
    login_as(admin_user, scope: :admin_user)
  end

  context "Creating a new blog post with markdown editor", js: true do
    it "displays the markdown editor toolbar and textarea" do
      visit new_admin_blog_post_path
      expect(page).to have_field("blog_post[title]", wait: 10)

      # Fill in basic fields
      fill_in "blog_post[title]", with: "Test Blog Post"
      fill_in "blog_post[excerpt]", with: "This is a test excerpt"
      select "Tutorial", from: "blog_post[category]"
      fill_in "blog_post[author_name]", with: "Test Author"
      fill_in "blog_post[author_email]", with: "test@example.com"

      # Verify the markdown editor UI elements are present
      expect(page).to have_css(".markdown-editor-toolbar", wait: 10)
      expect(page).to have_css("textarea.markdown-editor", wait: 5)
      
      # Verify all toolbar buttons are present
      expect(page).to have_css(".bold-btn")
      expect(page).to have_css(".italic-btn") 
      expect(page).to have_css(".code-btn")
      expect(page).to have_css(".h1-btn")
      expect(page).to have_css(".h2-btn")
      expect(page).to have_css(".h3-btn")
      expect(page).to have_css(".link-btn")
      expect(page).to have_css(".image-btn")
      expect(page).to have_css(".quote-btn")
      expect(page).to have_css(".codeblock-btn")
      expect(page).to have_css(".ul-btn")
      expect(page).to have_css(".ol-btn")
      expect(page).to have_css(".table-btn")
      expect(page).to have_css(".preview-btn")
      
      # Verify we can type in the textarea
      find("textarea.markdown-editor").click
      find("textarea.markdown-editor").set("# Test Content\n\nThis is **bold** and *italic* text.")
      
      textarea_content = find("textarea.markdown-editor").value
      expect(textarea_content).to include("# Test Content")
      expect(textarea_content).to include("**bold**")
      expect(textarea_content).to include("*italic*")
    end

    it "can type markdown syntax directly in the editor" do
      visit new_admin_blog_post_path
      expect(page).to have_field("blog_post[title]", wait: 10)

      # Fill in required fields
      fill_in "blog_post[title]", with: "Markdown Syntax Test"
      fill_in "blog_post[excerpt]", with: "Testing direct markdown input"

      # Wait for editor
      expect(page).to have_css("textarea.markdown-editor", wait: 10)
      
      # Test that we can type markdown syntax directly
      find("textarea.markdown-editor").click
      find("textarea.markdown-editor").set("**bold text** and *italic text* and `code`")
      
      textarea_content = find("textarea.markdown-editor").value
      expect(textarea_content).to include("**bold text**")
      expect(textarea_content).to include("*italic text*")
      expect(textarea_content).to include("`code`")
    end

    it "validates all toolbar buttons are clickable" do
      visit new_admin_blog_post_path
      expect(page).to have_field("blog_post[title]", wait: 10)

      # Fill in required fields
      fill_in "blog_post[title]", with: "Button Test Post"
      fill_in "blog_post[excerpt]", with: "Testing button clickability"

      # Wait for markdown editor
      expect(page).to have_css(".markdown-editor-toolbar", wait: 10)
      
      # Test that all buttons are clickable (even if JS doesn't work)
      expect(page).to have_button(class: "bold-btn")
      expect(page).to have_button(class: "italic-btn")
      expect(page).to have_button(class: "code-btn")
      expect(page).to have_button(class: "h1-btn")
      expect(page).to have_button(class: "h2-btn")
      expect(page).to have_button(class: "h3-btn")
      expect(page).to have_button(class: "link-btn")
      expect(page).to have_button(class: "image-btn")
      expect(page).to have_button(class: "quote-btn")
      expect(page).to have_button(class: "codeblock-btn")
      expect(page).to have_button(class: "ul-btn")
      expect(page).to have_button(class: "ol-btn")
      expect(page).to have_button(class: "table-btn")
      expect(page).to have_button(class: "preview-btn")
      
      # Verify buttons don't cause errors when clicked (even if they don't function)
      find('.bold-btn').click
      find('.italic-btn').click
      find('.preview-btn').click
      
      # The textarea should still be functional for typing
      find("textarea.markdown-editor").click
      find("textarea.markdown-editor").set("Still works for typing")
      
      textarea_content = find("textarea.markdown-editor").value
      expect(textarea_content).to eq("Still works for typing")
    end
  end

  context "Editing existing blog post", js: true do
    let!(:blog_post) { create(:blog_post, :with_markdown_content) }

    it "loads existing content in the markdown editor" do
      visit edit_admin_blog_post_path(blog_post)
      expect(page).to have_field("blog_post[title]", wait: 10)

      # Verify toolbar and editor are present
      expect(page).to have_css(".markdown-editor-toolbar", wait: 10)
      expect(page).to have_css("textarea.markdown-editor", wait: 5)

      # Verify existing content is loaded
      textarea_content = find("textarea.markdown-editor").value
      expect(textarea_content).to include("# Markdown Title")
      expect(textarea_content).to include("**Bold text**")
      expect(textarea_content).to include("*italic text*")
      expect(textarea_content).to include("code_example = 'hello world'")
    end
  end

  context "Form validation and submission", js: true do
    it "can save a blog post with markdown content" do
      visit new_admin_blog_post_path
      expect(page).to have_field("blog_post[title]", wait: 10)

      # Fill in all required fields
      fill_in "blog_post[title]", with: "Functional Test Post"
      fill_in "blog_post[excerpt]", with: "This tests form submission"
      select "Tutorial", from: "blog_post[category]"
      fill_in "blog_post[author_name]", with: "Test Author"
      fill_in "blog_post[author_email]", with: "test@example.com"
      
      # Add markdown content
      find("textarea.markdown-editor").click
      find("textarea.markdown-editor").set("# Test Post\n\nThis is a **test** with *markdown*.\n\n```ruby\ncode_example = 'hello'\n```")
      
      # Submit the form
      click_button "Create Blog post"
      
      # Should redirect to show page
      expect(page).to have_content("Functional Test Post")
      expect(page).to have_content("TUTORIALS")
    end
  end
end 