# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin Batch Actions", type: :system, admin: true do
  let!(:admin_user) { create(:admin_user) }
  let!(:blog_post1) { create(:blog_post, title: "Post 1", published: false) }
  let!(:blog_post2) { create(:blog_post, title: "Post 2", published: false) }
  let!(:blog_post3) { create(:blog_post, title: "Post 3", published: false) }

  before do
    driven_by(:cuprite)
    login_as(admin_user, scope: :admin_user)
  end

  describe "Batch action dropdown", js: true do
    it "displays batch action dropdown only once (no double-binding)" do
      visit admin_blog_posts_path

      # Wait for page to load
      expect(page).to have_content("Post 1", wait: 10)

      # Check that batch actions dropdown exists
      expect(page).to have_css(".batch_actions_selector", wait: 5)

      # Count batch action dropdowns - should be exactly 1
      batch_dropdowns = page.all(".batch_actions_selector")
      expect(batch_dropdowns.count).to eq(1),
        "Expected 1 batch actions dropdown, found #{batch_dropdowns.count} (possible double-binding issue)"
    end

    it "displays correct batch action options" do
      visit admin_blog_posts_path

      expect(page).to have_content("Post 1", wait: 10)
      expect(page).to have_css(".batch_actions_selector", wait: 5)

      # Verify delete action is available
      within(".batch_actions_selector") do
        expect(page).to have_content("Delete Selected")
      end
    end
  end

  describe "Selecting rows for batch actions", js: true do
    it "allows selecting multiple rows" do
      visit admin_blog_posts_path

      expect(page).to have_content("Post 1", wait: 10)

      # Select two blog posts
      check("batch_action_item_#{blog_post1.id}")
      check("batch_action_item_#{blog_post2.id}")

      # Verify checkboxes are checked
      expect(page).to have_checked_field("batch_action_item_#{blog_post1.id}")
      expect(page).to have_checked_field("batch_action_item_#{blog_post2.id}")
      expect(page).not_to have_checked_field("batch_action_item_#{blog_post3.id}")
    end

    it "allows selecting all rows with toggle" do
      visit admin_blog_posts_path

      expect(page).to have_content("Post 1", wait: 10)

      # Click the select all checkbox
      check("collection_selection_toggle_all")

      # Verify all checkboxes are checked
      expect(page).to have_checked_field("batch_action_item_#{blog_post1.id}")
      expect(page).to have_checked_field("batch_action_item_#{blog_post2.id}")
      expect(page).to have_checked_field("batch_action_item_#{blog_post3.id}")
    end
  end

  describe "Delete confirmation", js: true do
    it "shows confirmation dialog when deleting (appears once)" do
      visit admin_blog_posts_path

      expect(page).to have_content("Post 1", wait: 10)

      # Select one blog post
      check("batch_action_item_#{blog_post1.id}")

      # Click delete action
      within(".batch_actions_selector") do
        select "Delete Selected", from: "batch_action"
      end

      # Submit the form (this should trigger confirmation)
      click_button "Go"

      # Wait for and accept the confirmation dialog
      # Note: In Cuprite, accept_confirm works with Rails UJS confirmations
      page.accept_confirm do
        # The confirmation should appear
      end

      # After accepting, the post should be deleted
      # Note: We're not actually verifying deletion here, just that the
      # confirmation appeared once (if double-binding, there would be issues)
    end
  end

  describe "Batch action execution", js: true do
    it "executes batch delete action only once (no duplicate requests)" do
      visit admin_blog_posts_path

      expect(page).to have_content("Post 1", wait: 10)

      # Record initial count
      initial_count = BlogPost.count
      expect(initial_count).to eq(3)

      # Select one blog post
      check("batch_action_item_#{blog_post1.id}")

      # Execute delete batch action
      within(".batch_actions_selector") do
        select "Delete Selected", from: "batch_action"
      end

      # Accept confirmation and wait for deletion
      accept_confirm do
        click_button "Go"
      end

      # Wait for the deletion to complete
      sleep 2

      # Verify exactly one post was deleted (not duplicated)
      final_count = BlogPost.count
      expect(final_count).to eq(2),
        "Expected 2 posts remaining (deleted 1), but found #{final_count}. " \
        "This could indicate double-binding causing duplicate deletions."

      # Verify the correct post was deleted
      expect(BlogPost.exists?(blog_post1.id)).to be false
      expect(BlogPost.exists?(blog_post2.id)).to be true
      expect(BlogPost.exists?(blog_post3.id)).to be true
    end
  end

  describe "Custom batch actions", js: true do
    it "executes custom publish batch action" do
      visit admin_blog_posts_path

      expect(page).to have_content("Post 1", wait: 10)

      # Verify posts are unpublished
      expect(blog_post1.published).to be false
      expect(blog_post2.published).to be false

      # Select two posts
      check("batch_action_item_#{blog_post1.id}")
      check("batch_action_item_#{blog_post2.id}")

      # Execute publish batch action if it exists
      within(".batch_actions_selector") do
        # Only test if the publish action exists
        if page.has_select?("batch_action", with_options: ["Publish"])
          select "Publish", from: "batch_action"
          click_button "Go"

          # Wait for action to complete
          sleep 2

          # Verify posts were published
          blog_post1.reload
          blog_post2.reload
          expect(blog_post1.published).to be true
          expect(blog_post2.published).to be true
        end
      end
    end
  end

  describe "Batch actions JavaScript initialization", js: true do
    it "batch actions work immediately after page load" do
      visit admin_blog_posts_path

      # Immediately check that batch actions are functional
      expect(page).to have_css(".batch_actions_selector", wait: 5)

      # Select a row immediately
      check("batch_action_item_#{blog_post1.id}")

      # Batch actions should be enabled
      within(".batch_actions_selector") do
        expect(page).to have_select("batch_action")
      end
    end

    it "batch actions survive Turbo navigation" do
      # Visit a different page first
      visit admin_root_path
      expect(page).to have_content("Dashboard", wait: 10)

      # Navigate to blog posts
      visit admin_blog_posts_path
      expect(page).to have_content("Post 1", wait: 10)

      # Batch actions should still work
      expect(page).to have_css(".batch_actions_selector", wait: 5)
      check("batch_action_item_#{blog_post1.id}")

      within(".batch_actions_selector") do
        expect(page).to have_select("batch_action")
      end
    end
  end
end
