# Account Deletion Bidirectional Implementation Summary

## Overview
Implemented bidirectional deletion between `StaffMember` and `User` models, and enhanced business deletion prompts for managers. This ensures that when either a `StaffMember` or its associated `User` is deleted, both records are removed to maintain data consistency.

## Key Changes

### 1. Bidirectional StaffMember-User Deletion

#### StaffMember Model (`app/models/staff_member.rb`)
- **Added before_destroy callback**: When a `StaffMember` is deleted, it automatically deletes the associated `User`
- **Added safeguard**: Nullifies the association before deletion to prevent infinite loops

```ruby
# Bidirectional deletion: when staff member is deleted, delete associated user
before_destroy :delete_associated_user, if: -> { user.present? }

private

def delete_associated_user
  return unless user.present?
  
  # Temporarily store the user and remove the association to prevent infinite loops
  user_to_delete = self.user
  self.user = nil
  user_to_delete.destroy
end
```

#### User Model (`app/models/user.rb`)
- **Updated deletion methods**: Both `destroy_staff_account` and `destroy_manager_account` now delete associated `StaffMember` records instead of nullifying them
- **Added safeguards**: Nullifies user associations before destroying `StaffMember` to prevent infinite loops

```ruby
def destroy_staff_account
  ActiveRecord::Base.transaction do
    staff_members_to_delete = StaffMember.where(user_id: id)
    
    staff_members_to_delete.each do |staff_member_record|
      # Nullify bookings that reference this staff member before deleting
      staff_member_record.bookings.update_all(staff_member_id: nil)
      # Nullify the user association to prevent infinite loops, then delete
      staff_member_record.update_column(:user_id, nil)
      staff_member_record.destroy!
    end

    destroy!
  end
  
  { deleted: true, business_deleted: false }
end
```

### 2. Enhanced Business Deletion Prompts

#### Controller Enhancement (`app/controllers/business_manager/settings/profiles_controller.rb`)
- **Added business deletion impact calculation**: Provides detailed information about what will be deleted
- **Enhanced edit action**: Calculates and displays business deletion impact for sole users

```ruby
def edit
  authorize @user, policy_class: Settings::ProfilePolicy
  @account_deletion_info = @user.can_delete_account?
  @business_deletion_info = calculate_business_deletion_impact if @user.manager? && @account_deletion_info[:can_delete]
end

private

def calculate_business_deletion_impact
  business = current_user.business
  return nil unless business.present?

  # Only show business deletion info if user is sole user
  other_users = business.users.where.not(id: current_user.id)
  return nil unless other_users.empty?

  {
    business_name: business.name,
    data_counts: {
      services: business.services.count,
      staff_members: business.staff_members.count,
      customers: business.tenant_customers.count,
      bookings: business.bookings.count,
      orders: business.orders.count,
      products: business.products.count,
      invoices: business.invoices.count,
      payments: business.payments.count
    },
    warning_message: "This action will permanently delete your business and all associated data. This cannot be undone."
  }
end
```

### 3. Test Updates

#### Model Tests (`spec/models/user_deletion_spec.rb`)
- **Updated expectations**: Tests now expect `StaffMember` records to be deleted along with `User` records
- **Added bidirectional deletion tests**: Comprehensive test coverage for both directions of deletion

```ruby
describe "Bidirectional StaffMember-User deletion" do
  context "when deleting a StaffMember with an associated User" do
    it "deletes the associated User" do
      expect {
        staff_member.destroy
      }.to change(User, :count).by(-1)
       .and change(StaffMember, :count).by(-1)
    end
  end

  context "when deleting a User with an associated StaffMember" do
    it "deletes the associated StaffMember" do
      expect {
        staff_user.destroy_account
      }.to change(User, :count).by(-1)
       .and change(StaffMember, :count).by(-1)
    end
  end
end
```

#### Request Tests (`spec/requests/business_manager/settings/account_deletion_spec.rb`)
- **Updated account deletion tests**: Expectations now align with bidirectional deletion
- **Added staff member deletion test**: Verifies that deleting a staff member through the business interface also works correctly

### 4. Data Consistency Improvements

#### Foreign Key Handling
- **Booking associations**: Before deleting a `StaffMember`, all associated bookings have their `staff_member_id` nullified to prevent foreign key constraint violations
- **Orphaned data preservation**: Bookings, invoices, and orders remain in the database but lose their staff member associations

#### Infinite Loop Prevention
- **Association nullification**: Both models nullify the association before triggering the cascade deletion
- **Transaction safety**: All deletion operations are wrapped in database transactions

## Benefits

### 1. Data Consistency
- **No orphaned records**: Eliminates scenarios where a `User` exists without a corresponding `StaffMember` or vice versa
- **Referential integrity**: Maintains proper relationships between entities

### 2. Enhanced User Experience
- **Better business deletion prompts**: Managers get detailed information about what will be deleted
- **Clear warnings**: Users understand the impact of their deletion actions

### 3. Administrative Efficiency
- **Simplified cleanup**: Administrators don't need to manually clean up orphaned records
- **Reduced data bloat**: System automatically maintains clean data relationships

## Test Coverage

### Comprehensive Test Suite
- **16 model tests**: Cover all deletion scenarios including bidirectional deletion
- **10 request tests**: Verify controller behavior and user interface flows
- **Edge cases**: Handle scenarios like staff without users, sole managers, sole users, etc.

### All Tests Passing
```
User Account Deletion: 16 examples, 0 failures
BusinessManager Account Deletion: 10 examples, 0 failures
```

## Security Considerations

### Authorization
- **Policy enforcement**: All deletion actions require proper authorization
- **Role-based restrictions**: Different rules for managers, staff, and clients
- **Password verification**: Account deletion requires current password confirmation

### Data Protection
- **Transaction safety**: All operations are atomic
- **Cascade prevention**: Safeguards prevent unintended data loss
- **Audit trail**: Proper logging of deletion activities

## Future Enhancements

### Potential Improvements
- **Soft deletion**: Consider implementing soft deletion for audit purposes
- **Backup creation**: Automatic backup before major deletions
- **Notification system**: Email confirmations for deletion actions
- **Recovery mechanism**: Time-limited recovery for accidentally deleted accounts

This implementation provides a robust, user-friendly, and secure account deletion system with bidirectional consistency between `StaffMember` and `User` entities. 