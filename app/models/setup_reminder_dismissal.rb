class SetupReminderDismissal < ApplicationRecord
  belongs_to :user

  # Ensure each user can dismiss each task only once
  validates :task_key, presence: true, uniqueness: { scope: :user_id }
end 