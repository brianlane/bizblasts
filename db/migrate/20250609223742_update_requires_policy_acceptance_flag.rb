class UpdateRequiresPolicyAcceptanceFlag < ActiveRecord::Migration[8.0]
  def up
    say "Updating requires_policy_acceptance flag for existing users..."
    
    # Update flag in batches for performance
    User.in_batches(of: 1000) do |batch|
      batch.each do |user|
        # Calculate if user actually needs policy acceptance
        missing_policies = user.missing_required_policies
        needs_acceptance = missing_policies.any?
        
        # Update flag only if it doesn't match current state
        if user.requires_policy_acceptance? != needs_acceptance
          user.update_column(:requires_policy_acceptance, needs_acceptance)
          say "Updated User ##{user.id}: requires_policy_acceptance = #{needs_acceptance}"
        end
      end
    end
    
    say "Completed updating requires_policy_acceptance flags"
  end

  def down
    # This is a data migration - no reversal needed
    say "This migration only updates data - no reversal action needed"
  end
end
