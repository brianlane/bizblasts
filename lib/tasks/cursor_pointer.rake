# frozen_string_literal: true

namespace :lint do
  desc 'Check ERB templates for missing cursor-pointer classes'
  task :cursor_pointer do
    require_relative '../linters/cursor_pointer_linter'
    
    puts "🔍 Running cursor-pointer linter..."
    linter = CursorPointerLinter.new(verbose: true)
    exit_code = linter.run
    
    if exit_code == 0
      puts "✅ All checks passed!"
    else
      puts "❌ Linting failed. See errors above."
      exit(1) if ENV['RAILS_ENV'] == 'test' || ENV['CI']
    end
  end

  desc 'Automatically fix missing cursor-pointer classes'
  task :cursor_pointer_fix do
    require_relative '../linters/cursor_pointer_linter'
    
    puts "🔧 Auto-fixing cursor-pointer issues..."
    linter = CursorPointerLinter.new(fix: true, verbose: true)
    linter.run
    puts "✅ Auto-fix complete!"
  end

  desc 'Check specific files for cursor-pointer issues'
  task :cursor_pointer_file, [:file_path] do |t, args|
    require_relative '../linters/cursor_pointer_linter'
    
    unless args[:file_path]
      puts "❌ Please provide a file path: rake lint:cursor_pointer_file[app/views/some_file.html.erb]"
      exit(1)
    end

    linter = CursorPointerLinter.new(files: [args[:file_path]], verbose: true)
    linter.run
  end
end

# Add to default lint task if it exists
if Rake::Task.task_defined?('lint')
  Rake::Task['lint'].enhance(['lint:cursor_pointer'])
end