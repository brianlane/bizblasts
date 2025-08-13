#!/bin/bash
# Setup script for cursor-pointer linting

echo "🔧 Setting up cursor-pointer linting..."

# Make linter executable
chmod +x lib/linters/cursor_pointer_linter.rb
echo "✅ Made linter executable"

# Make git hooks executable
chmod +x .githooks/pre-commit
echo "✅ Made git hooks executable"

# Configure git to use custom hooks directory
git config core.hooksPath .githooks
echo "✅ Configured git hooks path"

# Test the linter
echo ""
echo "🧪 Testing linter..."
ruby lib/linters/cursor_pointer_linter.rb --help > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Linter is working correctly"
else
  echo "❌ Linter test failed"
  exit 1
fi

# Check if rake tasks are available
echo ""
echo "🧪 Testing rake tasks..."
rake -T | grep cursor_pointer > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Rake tasks are available"
  echo "   - rake lint:cursor_pointer"
  echo "   - rake lint:cursor_pointer_fix"
else
  echo "⚠️  Rake tasks not found (you may need to restart your Rails server)"
fi

echo ""
echo "🎉 Cursor-pointer linting setup complete!"
echo ""
echo "📋 Available commands:"
echo "   ruby lib/linters/cursor_pointer_linter.rb          # Check all files"
echo "   ruby lib/linters/cursor_pointer_linter.rb --fix    # Auto-fix issues"
echo "   rake lint:cursor_pointer                           # Check via rake"
echo "   rake lint:cursor_pointer_fix                       # Auto-fix via rake"
echo ""
echo "🚀 The pre-commit hook will now check for cursor-pointer issues automatically!"
echo "   To bypass: git commit --no-verify (not recommended)"