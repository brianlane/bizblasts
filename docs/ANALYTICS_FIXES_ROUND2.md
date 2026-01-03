# Analytics Fixes - Round 2

Additional analytics errors found and fixed after initial deployment.

## Summary

Fixed 5 additional analytics views that were failing:
- ✅ Bookings Analytics
- ✅ Products Analytics
- ✅ Staff Analytics
- ✅ Inventory Analytics
- ✅ Marketing Analytics

## Issues Fixed

### 1. Bookings: Column `bookings.bookable` Does Not Exist

**Error:**
```
PG::UndefinedColumn: ERROR: column bookings.bookable does not exist
```

**Location:** `app/services/analytics/booking_analytics_service.rb:107, 259`

**Root Cause:** The Booking model uses `staff_member_id`, not a `bookable` column.

**Fix:**
```ruby
# Before:
.where(bookable: staff, created_at: start_date..end_date)
.where(bookable: staff, start_time: start_date..end_date)

# After:
.where(staff_member: staff, created_at: start_date..end_date)
.where(staff_member: staff, start_time: start_date..end_date)
```

**Files Changed:**
- `app/services/analytics/booking_analytics_service.rb` (2 fixes)

---

### 2. Products: Can't Join LineItem to Association Named 'order'

**Error:**
```
ActiveRecord::ConfigurationError: Can't join 'LineItem' to association named 'order'; perhaps you misspelled it?
```

**Location:** `app/services/analytics/product_analytics_service.rb:43, 82, 202, 209`

**Root Cause:** LineItem doesn't have a `belongs_to :order` association. It uses a polymorphic `belongs_to :lineable` association where `lineable` can be an Order or Invoice.

**Fix:**
```ruby
# Before:
LineItem
  .joins(:order)
  .where(orders: { business_id: business.id, created_at: start_date..end_date })

# After:
order_ids = business.orders.where(created_at: start_date..end_date).pluck(:id)
LineItem
  .where(lineable_type: 'Order', lineable_id: order_ids)
```

**Files Changed:**
- `app/services/analytics/product_analytics_service.rb` (4 fixes)

---

### 3. Staff: Undefined Method '[]' for nil

**Error:**
```
ActionView::Template::Error: undefined method '[]' for nil
NoMethodError: undefined method '[]' for nil
```

**Location:** `app/views/business_manager/analytics/staff/index.html.erb:279, 288, 297`

**Root Cause:** Controller sets `@capacity_analysis` but view was trying to access `@capacity` which doesn't exist.

**Fix:**
```ruby
# View trying to access:
@capacity[:underutilized]
@capacity[:optimal]
@capacity[:overbooked]

# Should be:
@capacity_analysis[:summary][:underutilized]
@capacity_analysis[:summary][:optimal]
@capacity_analysis[:summary][:overbooked]
```

**Files Changed:**
- `app/views/business_manager/analytics/staff/index.html.erb` (3 fixes)

---

### 4. Inventory: Undefined Method 'total_stock_quantity' for Product

**Error:**
```
NoMethodError: undefined method 'total_stock_quantity' for an instance of Product
```

**Location:** `app/services/analytics/inventory_intelligence_service.rb:296`

**Root Cause:** Product model didn't have a `total_stock_quantity` method, but the analytics service expected it.

**Fix:** Added new method to Product model
```ruby
# Get total stock quantity (sum of all variants or product stock_quantity)
def total_stock_quantity
  if product_variants.any?
    product_variants.sum(:stock_quantity)
  else
    stock_quantity || 0
  end
end
```

**Files Changed:**
- `app/models/product.rb` (added new method)

---

### 5. Marketing: Column 'conversions_count' Does Not Exist

**Error:**
```
PG::UndefinedColumn: ERROR: column "conversions_count" does not exist
LINE 1: SELECT SUM(conversions_count) FROM "marketing_campaigns" WHE...
```

**Location:** `app/services/analytics/marketing_performance_service.rb:71, 95, 220`

**Root Cause:** The `marketing_campaigns` table was missing counter columns that the analytics service expected.

**Fix:** Created migration to add missing counter columns

**Migration:**
```ruby
class AddCountersToMarketingCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :marketing_campaigns, :conversions_count, :integer, default: 0
    add_column :marketing_campaigns, :sent_count, :integer, default: 0
    add_column :marketing_campaigns, :opened_count, :integer, default: 0
    add_column :marketing_campaigns, :clicked_count, :integer, default: 0
  end
end
```

**Files Changed:**
- `db/migrate/20251229215643_add_counters_to_marketing_campaigns.rb` (new migration)
- Ran migration in both test and development environments

---

## Architecture Notes

### Booking Associations
Bookings belong to `staff_member`, not a generic `bookable`. Use:
- ✅ `.where(staff_member: staff)` or `.where(staff_member_id: staff.id)`
- ❌ NOT `.where(bookable: staff)`

### LineItem Polymorphic Associations
LineItems use a polymorphic `lineable` association:
- `lineable_type` can be 'Order' or 'Invoice'
- `lineable_id` is the ID of the order or invoice

To query line items for orders:
```ruby
# ✅ Correct approach:
order_ids = business.orders.where(...).pluck(:id)
LineItem.where(lineable_type: 'Order', lineable_id: order_ids)

# ❌ Incorrect approach:
LineItem.joins(:order) # This association doesn't exist
```

### Product Stock Management
Products can have stock tracked in two ways:
1. **With variants:** Total stock = sum of all `product_variants.stock_quantity`
2. **Without variants:** Total stock = product's own `stock_quantity`

The `total_stock_quantity` method handles both cases automatically.

### Marketing Campaign Counters
Marketing campaigns track performance with counter columns:
- `sent_count` - Number of messages sent
- `opened_count` - Number of messages opened
- `clicked_count` - Number of links clicked
- `conversions_count` - Number of conversions attributed to campaign

All default to 0 to prevent NULL issues.

---

## Testing

After these fixes, test each analytics view:
1. **Bookings** - `/manage/analytics?period=last_30_days` → Bookings tab
2. **Products** - `/manage/analytics?period=last_30_days` → Products tab
3. **Staff** - `/manage/analytics/staff`
4. **Inventory** - `/manage/analytics/inventory`
5. **Marketing** - `/manage/analytics/marketing`

All views should now load without database errors.

---

## Files Modified Summary

**Services:**
- `app/services/analytics/booking_analytics_service.rb`
- `app/services/analytics/product_analytics_service.rb`

**Models:**
- `app/models/product.rb`

**Views:**
- `app/views/business_manager/analytics/staff/index.html.erb`

**Migrations:**
- `db/migrate/20251229215643_add_counters_to_marketing_campaigns.rb`

**Total: 5 files modified/created**
