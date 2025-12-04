# Google Drive API - Mass Upload Safety Guide

## ⚠️ CRITICAL INFORMATION

### Google Drive Upload Limits (Official)

**Daily Upload Quota:**
- **750 GB per day** maximum between My Drive and all shared drives
- This limit applies to all Google Workspace accounts (including Google One AI Premium 2TB)
- **Limit resets after 24 hours** from when you hit the cap

**File Size Limits:**
- Maximum single file size: **5 TB**
- Maximum file size for copy operations: **750 GB**

**API Rate Limits:**
- **12,000 queries per 60 seconds** (per project)
- **12,000 queries per 60 seconds per user**
- No daily request limit if you stay within per-minute quotas

### Account Suspension Risk: ❌ **VERY LOW**

**Good News:**
1. ✅ **No billing or charges** - Exceeding quota limits doesn't incur costs
2. ✅ **No account suspension** - Google doesn't ban accounts for hitting API quotas
3. ✅ **Automatic enforcement** - API returns error codes (403/429), doesn't punish your account
4. ✅ **Built-in protection** - Quotas prevent abuse automatically

**What Actually Happens:**
- Hit 750GB/day → Upload fails with error, wait 24 hours
- Hit rate limit → Get `403: User rate limit exceeded` or `429: Too many requests`
- **Your account stays safe**, you just need to retry later

## 🚨 CURRENT TDL IMPLEMENTATION - CRITICAL ISSUE

### ⚠️ **NO RETRY LOGIC** - Files Will Fail Silently

**Current Code Flow:**
```go
// core/uploader/uploader.go
if elem.Gdrive() {
    if err := u.uploadToGdrive(ctx, elem); err != nil {
        return errors.Wrap(err, "upload to gdrive")  // ❌ FAILS IMMEDIATELY
    }
}
```

**Problems:**
1. ❌ **No exponential backoff** - Required by Google's best practices
2. ❌ **No rate limit handling** - Will fail on 429 errors
3. ❌ **No retry mechanism** - Single failure = file upload skipped
4. ❌ **Silent failures possible** - Error handling in upload loop may skip files

### What Happens During Mass Upload?

**Scenario 1: Hit Daily 750GB Limit**
- Upload 750GB successfully ✅
- Next file hits quota → **FAILS** ❌
- All remaining files **FAIL** ❌
- You lose upload progress
- Must manually retry after 24 hours

**Scenario 2: Hit Rate Limit (12,000/minute)**
- Uploading fast → Hit rate limit
- Get `429: Too many requests` ❌
- **Upload fails immediately** (no retry)
- Need manual intervention

**Scenario 3: Network Glitch**
- Temporary connection issue
- **Upload fails** (no retry)
- File skipped, move to next

## ✅ SAFE USAGE RECOMMENDATIONS

### 1. **Monitor Your Daily Upload**

Keep track manually:
```bash
# Before starting
echo "Starting upload: $(date)" >> upload_log.txt

# Track file sizes
du -sh /path/to/upload/folder

# Stop before 750GB
# Example: If folder is 2TB, split into 3 days:
# Day 1: 750GB
# Day 2: 750GB  
# Day 3: 500GB
```

### 2. **Upload in Batches**

Don't upload continuously for days straight:
```bash
# Day 1: Upload 700GB (leave margin)
tdl up --gdrive --rm /batch1/

# Wait 24+ hours

# Day 2: Upload next 700GB
tdl up --gdrive --rm /batch2/
```

### 3. **Add Delays Between Files**

Use a wrapper script:
```bash
#!/bin/bash
for file in /path/to/files/*; do
    tdl.exe up --gdrive --rm "$file"
    sleep 5  # 5 second delay between uploads
done
```

### 4. **Watch for Errors**

Monitor output for:
- `403: User rate limit exceeded`
- `429: Too many requests`
- `quota exceeded`
- `unable to upload`

**If you see these:** STOP and wait before retrying.

### 5. **Use Separate Projects (Optional)**

For extremely heavy usage:
- Create multiple Google Cloud projects
- Each gets its own 12,000 queries/minute quota
- Rotate between projects
- **Still subject to 750GB/day per Google account**

## 🔧 WORKAROUND: Manual Retry Script

Since tdl doesn't have retry logic, use this wrapper:

```bash
#!/bin/bash
# retry_upload.sh - Upload with automatic retry

MAX_RETRIES=3
DELAY=60  # 1 minute delay

upload_with_retry() {
    local file="$1"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        echo "Uploading: $file (attempt $((retries+1)))"
        
        if tdl.exe up --gdrive --rm "$file" 2>&1 | tee /tmp/tdl_output.log; then
            if grep -q "quota\|rate limit\|429\|403" /tmp/tdl_output.log; then
                echo "Rate limited. Waiting ${DELAY}s..."
                sleep $DELAY
                DELAY=$((DELAY * 2))  # Exponential backoff
                retries=$((retries + 1))
            else
                echo "✅ Success: $file"
                return 0
            fi
        else
            echo "❌ Failed: $file (attempt $((retries+1)))"
            retries=$((retries + 1))
            sleep $DELAY
        fi
    done
    
    echo "❌ FAILED AFTER $MAX_RETRIES ATTEMPTS: $file"
    return 1
}

# Upload all files
for file in /path/to/files/*; do
    upload_with_retry "$file"
    sleep 5  # Small delay between files
done
```

## 📊 ESTIMATED SAFE UPLOAD RATES

### Conservative Approach (Recommended)
- **Files/minute:** ~10 files (with 5s delay)
- **Daily capacity:** ~700GB (leave margin)
- **Upload duration:** Depends on file sizes
  - 1GB files: ~700 files/day
  - 100MB files: ~7,000 files/day
  - 10MB files: ~70,000 files/day

### Aggressive Approach (Risky)
- **Files/minute:** ~30 files (2s delay)
- **Daily capacity:** 750GB (exact limit)
- **Risk:** Higher chance of hitting rate limits

## ⚡ OPTIMIZATION TIPS

### 1. **Compress Before Upload**
```bash
# Reduce upload size
tar -czf archive.tar.gz /large/folder/
tdl up --gdrive --rm archive.tar.gz
```

### 2. **Upload During Off-Peak Hours**
- Less API congestion
- Lower chance of rate limits
- Better network speeds

### 3. **Monitor Quota Usage**
Check Google Cloud Console:
- [Quotas Page](https://console.cloud.google.com/iam-admin/quotas)
- Filter by "Drive API"
- Watch real-time usage

### 4. **Parallel Uploads (Advanced)**
**⚠️ Not Recommended Without Retry Logic**

If you must:
```bash
# Upload 3 files in parallel (stay under rate limit)
find /path -type f | xargs -P 3 -I {} tdl up --gdrive --rm {}
```

But risk of failures increases significantly.

## 🎯 YOUR CASE: 2TB Google One AI Premium

**Storage:** ✅ 2TB is plenty  
**Daily limit:** ⚠️ Still 750GB/day (storage ≠ upload quota)  
**Timeline:** Minimum 3 days to upload 2TB  

**Safest Approach:**
```
Day 1: 700GB
Day 2: 700GB  
Day 3: 600GB
Total: 3 days for 2TB
```

**Account Safety:** ✅✅✅ **VERY SAFE**
- Won't get suspended
- Won't get charged
- Just hit quotas → wait → retry

## ⚠️ WHAT TO AVOID

❌ **DON'T:**
1. Upload 750GB+ without monitoring
2. Ignore error messages
3. Run multiple instances simultaneously
4. Upload sensitive data without encryption
5. Share OAuth credentials across devices

✅ **DO:**
1. Monitor upload progress
2. Use batch uploads (700GB/day max)
3. Add delays between files
4. Keep logs of what uploaded successfully
5. Test with small batches first

## 🆘 IF SOMETHING GOES WRONG

### Hit Daily Quota
```
Error: "quota exceeded" or "daily limit exceeded"
Action: STOP. Wait 24 hours. Resume tomorrow.
Risk: ZERO (account is safe)
```

### Hit Rate Limit
```
Error: "403: User rate limit exceeded" or "429: Too many requests"  
Action: Wait 1-2 minutes. Retry with slower rate.
Risk: ZERO (account is safe)
```

### Upload Failed
```
Error: "unable to upload" or "connection error"
Action: Check internet. Verify credentials. Retry file.
Risk: ZERO (account is safe)
```

### Account Issues
```
Error: "invalid credentials" or "access denied"
Action: Re-authenticate OAuth. Check API is enabled.
Risk: Configuration issue, not quota issue
```

## 📝 SUMMARY

### Can You Upload 2TB Over Several Days?
✅ **YES, 100% SAFE**

### Will Your Account Get Suspended?
❌ **NO, NEVER** (for quota limits)

### What's the Catch?
- ⚠️ **750GB/day limit** - Plan for 3+ days
- ⚠️ **No automatic retry** - Use wrapper script
- ⚠️ **Manual monitoring** - Watch for errors

### Recommendation:
```bash
# Day 1
tdl up --gdrive --rm /batch1_700GB/

# Day 2 (24 hours later)
tdl up --gdrive --rm /batch2_700GB/

# Day 3 (24 hours later)  
tdl up --gdrive --rm /batch3_remaining/
```

**Your account will be fine. Just respect the daily limits and you're golden.** 🎯
