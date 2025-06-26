# System Tests Splitting - Future-Proof Approach

## Overview

Our CI pipeline automatically splits system tests into 3 parallel jobs to reduce test execution time. The system is designed to be completely self-maintaining and future-proof.

## How It Works

### Automatic Test Discovery

The `bin/split_system_tests.rb` script automatically:

1. **Discovers all system tests** in `spec/system/` (including subdirectories)
2. **Analyzes file sizes** to estimate test complexity
3. **Distributes tests evenly** across 3 groups using a greedy algorithm
4. **Balances workload** to minimize the time for the slowest group

### Dynamic Distribution

Tests are distributed by file size (larger files typically have more/slower tests):

```bash
# Get tests for a specific group
./bin/split_system_tests.rb 1  # Returns space-separated test files for group 1
./bin/split_system_tests.rb 2  # Returns space-separated test files for group 2  
./bin/split_system_tests.rb 3  # Returns space-separated test files for group 3

# View all groups
./bin/split_system_tests.rb    # Shows how tests are distributed
```

## GitHub Actions Integration

Each system test job (`test_system_1`, `test_system_2`, `test_system_3`) uses:

```yaml
- name: Run system tests 1
  run: |
    TESTS=$(./bin/split_system_tests.rb 1)
    if [ -n "$TESTS" ]; then
      echo "Running system tests group 1..."
      bundle exec rspec $TESTS --format documentation
    else
      echo "No system tests found for group 1"
    fi
```

## Future-Proof Benefits

### ✅ **Automatic New Test Inclusion**
- Add any new system test file → it's automatically included in the next CI run
- No manual workflow updates needed
- Tests are automatically balanced across groups

### ✅ **Smart Load Balancing**
- Larger test files are distributed first to balance execution time
- Prevents one group from becoming significantly slower
- Adapts as test files grow or shrink

### ✅ **Robust Error Handling**
- Gracefully handles empty test directories
- Works even if new subdirectories are added
- Fails gracefully if no tests are found

### ✅ **Easy Maintenance**
- Single script handles all distribution logic
- Clear logging shows which tests run in each group
- No hardcoded test lists to maintain

## Adding New System Tests

To add new system tests:

1. **Create your test file** anywhere in `spec/system/` (including subdirectories)
2. **That's it!** The next CI run will automatically include it

Example:
```bash
# Add a new test file
touch spec/system/new_feature_spec.rb

# The script automatically finds it
./bin/split_system_tests.rb
# Group 1 (16 tests):
#   spec/system/new_feature_spec.rb  # <- Automatically included!
#   ...
```

## Manual Test Distribution

If you ever need to see or debug the test distribution:

```bash
# See all groups and their tests
./bin/split_system_tests.rb

# Get help
./bin/split_system_tests.rb --help

# Test a specific group locally  
bundle exec rspec $(./bin/split_system_tests.rb 1)
```

## Configuration

The script is designed to work out-of-the-box, but you can modify:

- **Number of groups**: Change `num_groups = 3` in the script
- **Distribution algorithm**: Modify the `split_tests_evenly` function
- **File discovery**: Modify the `find_system_tests` function

## Troubleshooting

### Tests not appearing in CI?
- Ensure your test file ends with `_spec.rb`
- Ensure it's in `spec/system/` or a subdirectory
- Check the script output: `./bin/split_system_tests.rb`

### Unbalanced test execution times?
- The script balances by file size, not actual execution time
- Consider splitting large test files into smaller ones
- Monitor CI job execution times to identify bottlenecks

### Need to force a specific test grouping?
- The current approach prioritizes automatic balance
- For manual control, you could modify the script or use tags/metadata

## Benefits Over Static Approach

| Static (Old) | Dynamic (New) |
|-------------|---------------|
| ❌ Manual updates needed | ✅ Automatic inclusion |
| ❌ Hardcoded file lists | ✅ Dynamic discovery |
| ❌ Manual load balancing | ✅ Smart distribution |
| ❌ Easy to forget updates | ✅ Self-maintaining |
| ❌ Brittle maintenance | ✅ Robust & flexible |

This approach ensures your CI pipeline scales automatically as your test suite grows! 