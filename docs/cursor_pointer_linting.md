# Cursor Pointer Linting

This project includes a custom linter to ensure all interactive elements have the `cursor-pointer` CSS class for better user experience.

## What It Checks

The linter identifies interactive elements that should have `cursor-pointer`:

- `button_to` helpers
- `link_to` helpers with button-like classes (`btn`, `button`)
- HTML `<button>` elements  
- Form submit buttons (`form.submit`)
- Input buttons (`type="submit"` or `type="button"`)

## Usage

### Command Line

```bash
# Check all view files
ruby lib/linters/cursor_pointer_linter.rb

# Check with verbose output
ruby lib/linters/cursor_pointer_linter.rb --verbose

# Auto-fix issues
ruby lib/linters/cursor_pointer_linter.rb --fix

# Check specific files
ruby lib/linters/cursor_pointer_linter.rb app/views/some_file.html.erb
```

### Rake Tasks

```bash
# Check for issues
rake lint:cursor_pointer

# Auto-fix issues
rake lint:cursor_pointer_fix

# Check specific file
rake lint:cursor_pointer_file[app/views/some_file.html.erb]
```

### Git Integration

#### Pre-commit Hook
The linter runs automatically on staged ERB files before commits:

```bash
# Install git hooks
git config core.hooksPath .githooks

# The hook will run automatically on git commit
git commit -m "Your changes"
```

To bypass the hook (not recommended):
```bash
git commit --no-verify
```

#### GitHub Actions
The linter runs on all PRs and pushes to main/develop branches that modify view files. Check the "Actions" tab for results.

## Example Output

When issues are found:
```
❌ Found 2 interactive elements missing cursor-pointer:

📄 app/views/some_file.html.erb:
  Line 15:
    Current: <%= button_to "Click Me", some_path, class: "btn btn-primary" %>
    Classes: 'btn btn-primary'
    Context:
       14:   <div class="actions">
    >  15:     <%= button_to "Click Me", some_path, class: "btn btn-primary" %>
       16:   </div>
```

## Auto-Fix

The linter can automatically add `cursor-pointer` to class attributes:

```bash
# Before
<%= button_to "Click", path, class: "btn btn-primary" %>

# After auto-fix
<%= button_to "Click", path, class: "cursor-pointer btn btn-primary" %>
```

## Configuration

### Excluding Elements

The linter automatically excludes elements that already have cursor classes:
- `cursor-pointer` (already correct)
- `cursor-not-allowed` (disabled states)
- `cursor-default` (non-interactive)
- `cursor-wait` (loading states)

### Adding New Patterns

To check additional element types, modify `BUTTON_PATTERNS` in `lib/linters/cursor_pointer_linter.rb`:

```ruby
BUTTON_PATTERNS = [
  # Add new regex patterns here
  /your_custom_pattern/,
].freeze
```

## Best Practices

1. **Run before committing**: The pre-commit hook helps catch issues early
2. **Use auto-fix**: The `--fix` flag safely adds cursor-pointer classes
3. **Check CI**: Monitor GitHub Actions for linting results on PRs
4. **Regular audits**: Run `rake lint:cursor_pointer` periodically

## Troubleshooting

### Common Issues

**"Command not found" error:**
```bash
# Ensure you're in the Rails root directory
cd /path/to/your/rails/app
ruby lib/linters/cursor_pointer_linter.rb
```

**Permission denied:**
```bash
# Make the script executable
chmod +x lib/linters/cursor_pointer_linter.rb
```

**Git hook not running:**
```bash
# Configure git to use the hooks directory
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit
```

### False Positives

If the linter flags an element that shouldn't have `cursor-pointer`, you can:

1. Add an explicit cursor class like `cursor-default`
2. Modify the exclude patterns in the linter
3. Use the `--no-verify` flag for specific commits (discouraged)

## Integration with Other Tools

### VS Code Extension
Add to `.vscode/tasks.json`:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Lint Cursor Pointer",
      "type": "shell",
      "command": "ruby lib/linters/cursor_pointer_linter.rb --verbose",
      "group": "build",
      "presentation": {
        "echo": true,
        "reveal": "always",
        "focus": false,
        "panel": "shared"
      }
    }
  ]
}
```

### RubyMine
Add as an External Tool:
- Program: `ruby`
- Arguments: `lib/linters/cursor_pointer_linter.rb --verbose`
- Working directory: `$ProjectFileDir$`