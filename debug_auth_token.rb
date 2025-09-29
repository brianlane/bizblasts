puts '=== Checking AuthToken Database Schema ==='
begin
  puts 'AuthToken table exists?: ' + AuthToken.table_exists?.to_s
  puts 'AuthToken columns:'
  AuthToken.columns.each do |column|
    puts "  #{column.name}: #{column.type} (null: #{column.null})"
  end

  puts
  puts 'Testing basic AuthToken creation...'
  user = FactoryBot.build(:user)
  puts "User built: #{user.inspect}"

  # Create minimal auth token to test database
  token = AuthToken.new(
    user: user,
    target_url: 'https://example.com/test',
    ip_address: '127.0.0.1',
    user_agent: 'Test Browser'
  )

  puts "Token valid?: #{token.valid?}"
  if !token.valid?
    puts "Token errors: #{token.errors.full_messages}"
  end

rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end