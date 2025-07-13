# frozen_string_literal: true

class BusinessManager::Settings::SidebarController < BusinessManager::BaseController
  helper Rails.application.routes.url_helpers

  def edit_sidebar
    if current_user.user_sidebar_items.exists?
      defaults = UserSidebarItem.default_items_for(current_user).index_by { |item| item[:key] }
      @sidebar_items = current_user.user_sidebar_items.order(:position).map do |item|
        defaults[item.item_key] || { key: item.item_key, label: item.item_key.humanize }
      end
      missing = UserSidebarItem.default_items_for(current_user).reject { |item| current_user.user_sidebar_items.exists?(item_key: item[:key]) }
      @sidebar_items += missing
    else
      @sidebar_items = UserSidebarItem.default_items_for(current_user)
    end
    @user_sidebar_items = current_user.user_sidebar_items.index_by(&:item_key)

  end

  def update_sidebar
    items = params[:sidebar_items] || []
    items = items.to_unsafe_h.values if items.is_a?(ActionController::Parameters)
    items = items.to_a unless items.is_a?(Array)
    default_keys = UserSidebarItem.default_items_for(current_user).map { |item| item[:key] }
    submitted_keys = items.map { |i| i[:key] }
    ActiveRecord::Base.transaction do
      items.each_with_index do |item, idx|
        sidebar_item = current_user.user_sidebar_items.find_or_initialize_by(item_key: item[:key])
        sidebar_item.position = idx
        sidebar_item.visible = ActiveModel::Type::Boolean.new.cast(item[:visible])
        sidebar_item.save!
      end
      (default_keys - submitted_keys).each do |key|
        sidebar_item = current_user.user_sidebar_items.find_or_initialize_by(item_key: key)
        sidebar_item.position ||= UserSidebarItem.default_items_for(current_user).index { |i| i[:key] == key } || 0
        sidebar_item.visible = false
        sidebar_item.save!
      end
    end
    respond_to do |format|
      format.html { redirect_to edit_sidebar_business_manager_settings_sidebar_path, notice: 'Sidebar updated.' }
      format.json { render json: { success: true } }
    end
  end
end 