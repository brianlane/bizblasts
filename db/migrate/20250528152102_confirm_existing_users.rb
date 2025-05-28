class ConfirmExistingUsers < ActiveRecord::Migration[8.0]
  def up
    # Confirm all existing users so they don't get locked out
    User.where(confirmed_at: nil).update_all(confirmed_at: Time.current)
  end

  def down
    # Don't reverse this - we don't want to unconfirm users
  end
end
