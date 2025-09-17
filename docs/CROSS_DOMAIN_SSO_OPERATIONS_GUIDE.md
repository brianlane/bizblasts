# Cross-Domain SSO Operations Guide

## Quick Reference

### Health Check Commands

```bash
# Check token statistics
rake auth_tokens:stats

# Manual cleanup
rake auth_tokens:cleanup

# Test token flow
rake auth_tokens:test

# Start recurring cleanup job
rake auth_tokens:start_cleanup
```

### Log Monitoring

```bash
# Monitor successful authentications
tail -f log/production.log | grep "Successfully authenticated user.*via Redis bridge token"

# Watch for security warnings
tail -f log/production.log | grep "User agent mismatch\|IP address mismatch"

# Track cleanup operations
tail -f log/production.log | grep "AuthTokenCleanup"
```

## Common Issues & Solutions

### "Invalid or expired authentication token" errors

**Symptoms:**
- Users getting authentication errors on custom domains
- High number of failed token consumptions

**Diagnosis:**
```bash
# Check Redis connectivity
redis-cli ping

# Check token statistics
rake auth_tokens:stats

# Look for errors in logs
grep "Invalid or expired authentication token" log/production.log
```

**Common Causes:**
1. **Expired tokens** (>2 minutes old)
2. **Token already used** (single-use enforcement)
3. **IP address mismatch** (user's IP changed)
4. **Redis connectivity issues**

**Solutions:**
1. Check user's network (mobile switching between WiFi/cellular)
2. Verify Redis connectivity and performance
3. Check server clock synchronization
4. Review rate limiting configuration

### High number of orphaned tokens

**Symptoms:**
```
⚠️  Warning: Found 50 tokens without TTL!
```

**Diagnosis:**
```bash
rake auth_tokens:stats
```

**Solutions:**
```bash
# Run manual cleanup
rake auth_tokens:cleanup

# Check Redis TTL configuration
redis-cli TTL auth_token:sample_token

# Verify server time synchronization
ntpq -p
```

### Performance degradation

**Symptoms:**
- Slow authentication bridge responses
- High Redis memory usage
- Cleanup job taking too long

**Diagnosis:**
```bash
# Check Redis memory usage
redis-cli info memory

# Monitor cleanup job performance
grep "AuthTokenCleanup.*Processed.*tokens" log/production.log

# Check Redis performance
redis-cli --latency
```

**Solutions:**
1. Scale Redis instance if needed
2. Increase cleanup job frequency
3. Monitor token generation rate
4. Consider Redis optimization

## Monitoring Setup

### Key Metrics to Track

```ruby
# Example StatsD integration
class AuthToken
  def self.create_for_user!(user, target_url, ip_address, user_agent)
    StatsD.increment('auth_bridge.token_generated')
    StatsD.timing('auth_bridge.token_generation_time') do
      # ... token creation logic
    end
  end
  
  def self.consume!(token_string, current_ip, current_user_agent)
    result = # ... consumption logic
    
    if result
      StatsD.increment('auth_bridge.token_consumed.success')
    else
      StatsD.increment('auth_bridge.token_consumed.failure')
    end
    
    result
  end
end
```

### Alerting Rules

```yaml
# Example alert configuration
alerts:
  - name: "High Auth Token Failure Rate"
    condition: "auth_bridge.token_consumed.failure > 50/hour"
    severity: "warning"
    
  - name: "Redis Connection Issues"
    condition: "auth_bridge.redis_errors > 10/hour"
    severity: "critical"
    
  - name: "High Orphaned Token Count"
    condition: "auth_bridge.orphaned_tokens > 100"
    severity: "warning"
```

## Security Monitoring

### Suspicious Activity Patterns

Monitor for these patterns that may indicate attacks:

1. **High IP mismatch rate** (>10/hour from same user)
2. **Rapid token generation** (>100/minute from same IP)
3. **Token replay attempts** (consuming already-used tokens)
4. **Geographic anomalies** (token generated in US, consumed in different country)

### Security Incident Response

If suspicious activity is detected:

1. **Immediate Actions:**
   ```bash
   # Check recent security events
   grep "IP address mismatch\|User agent mismatch" log/production.log | tail -50
   
   # Check for rapid token generation
   grep "AuthToken.*created" log/production.log | tail -100
   ```

2. **Investigation:**
   - Review user login patterns
   - Check for compromised accounts
   - Analyze IP address ranges
   - Review user agent strings for bots

3. **Mitigation:**
   - Temporary rate limiting if needed
   - Block suspicious IP ranges
   - Force password reset for affected users
   - Review and update security thresholds

## Maintenance Procedures

### Weekly Maintenance

```bash
# Check system health
rake auth_tokens:stats

# Review cleanup job performance
grep "AuthTokenCleanup" log/production.log | tail -20

# Check Redis memory usage
redis-cli info memory | grep used_memory_human
```

### Monthly Review

1. **Performance Analysis:**
   - Review token generation/consumption rates
   - Analyze cleanup job efficiency
   - Check Redis performance metrics

2. **Security Review:**
   - Review security event logs
   - Update monitoring thresholds
   - Test incident response procedures

3. **Capacity Planning:**
   - Project Redis memory growth
   - Plan for traffic increases
   - Review scaling requirements

## Development & Testing

### Local Development Setup

```bash
# Start Redis locally
redis-server

# Test token flow in development
rails console
> user = User.first
> token = AuthToken.create_for_user!(user, 'http://test.com', '127.0.0.1', 'Test')
> AuthToken.consume!(token.token, '127.0.0.1', 'Test')
```

### Staging Environment Testing

```bash
# Test full cross-domain flow
curl -H "Host: staging.bizblasts.com" \
     "https://staging.bizblasts.com/auth/bridge?target_url=https://test-business.com/dashboard"

# Verify token cleanup
rake auth_tokens:cleanup RAILS_ENV=staging
```

## Emergency Procedures

### Complete System Failure

If the cross-domain SSO system fails completely:

1. **Immediate Fallback:**
   - Users can still access businesses directly
   - Authentication still works within each domain
   - Only cross-domain navigation is affected

2. **Quick Fix:**
   ```bash
   # Disable cross-domain SSO (fallback to direct links)
   # This can be done via feature flag or environment variable
   export DISABLE_CROSS_DOMAIN_SSO=true
   ```

3. **Full Recovery:**
   - Check Redis connectivity
   - Verify application deployment
   - Test token generation/consumption
   - Re-enable cross-domain SSO

### Data Recovery

If Redis data is lost:

1. **Impact Assessment:**
   - Only active tokens are lost (2-minute TTL)
   - No permanent user data affected
   - System will self-heal within 2 minutes

2. **Recovery Steps:**
   - Restart Redis if needed
   - No manual intervention required
   - Monitor for normal operation resumption

---

**Last Updated:** January 2025  
**Maintained By:** BizBlasts Engineering Team