# Concurrent Download-Upload Architecture Design

## Goal
Create a single `tdl.exe` command that:
1. ✅ Downloads from Telegram channel concurrently
2. ✅ Uploads completed files to Google Drive in background
3. ✅ Maintains 50GB disk usage limit
4. ✅ Auto-deletes after successful upload
5. ✅ Saves progress to Telegram saved messages
6. ✅ Resumes from last message ID

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      TDL Concurrent Engine                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   Download   │───▶│   Upload     │───▶│   Cleanup    │      │
│  │   Worker     │    │   Worker     │    │   Worker     │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  ┌──────────────────────────────────────────────────────┐      │
│  │              Shared File Queue (Channel)              │      │
│  │  • Pending Downloads                                  │      │
│  │  • Downloaded (ready for upload)                      │      │
│  │  • Uploaded (ready for cleanup)                       │      │
│  └──────────────────────────────────────────────────────┘      │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │ Disk Monitor │    │ State Saver  │    │ Progress Bar │      │
│  │ (50GB limit) │    │ (Telegram)   │    │ (Real-time)  │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Download Worker
**Responsibility:** Fetch files from Telegram channel

**Features:**
- Iterates through channel messages
- Downloads files to temp directory
- Marks files as "ready for upload" in queue
- Pauses when disk usage > 50GB
- Saves last processed message ID every 10 messages

**Pseudocode:**
```go
func DownloadWorker(ctx context.Context, opts Options) {
    for msg := range getChannelMessages() {
        // Check disk usage
        if getDiskUsageGB() > opts.MaxDiskGB {
            waitForDiskSpace()
            continue
        }
        
        // Download file
        file := downloadFile(msg)
        
        // Add to upload queue
        uploadQueue <- file
        
        // Save progress every 10 files
        if msg.ID % 10 == 0 {
            saveProgressToTelegram(msg.ID)
        }
    }
}
```

### 2. Upload Worker
**Responsibility:** Upload completed downloads to Google Drive

**Features:**
- Monitors upload queue
- Uploads files to GDrive concurrently (3 parallel uploads)
- Handles API rate limits with exponential backoff
- Adds uploaded files to cleanup queue
- Retries failed uploads (max 3 attempts)

**Pseudocode:**
```go
func UploadWorker(ctx context.Context, gdriveClient *drive.Service) {
    for file := range uploadQueue {
        // Wait if rate limited
        if isRateLimited() {
            backoff()
        }
        
        // Upload to Google Drive
        err := uploadToGDrive(file)
        if err != nil {
            retry(file)
            continue
        }
        
        // Add to cleanup queue
        cleanupQueue <- file
    }
}
```

### 3. Cleanup Worker
**Responsibility:** Delete local files after successful upload

**Features:**
- Monitors cleanup queue
- Deletes files from disk
- Updates disk usage counter
- Logs cleanup operations

**Pseudocode:**
```go
func CleanupWorker(ctx context.Context) {
    for file := range cleanupQueue {
        os.Remove(file.Path)
        updateDiskUsage(-file.Size)
        logCleanup(file.Name)
    }
}
```

### 4. Disk Monitor
**Responsibility:** Track disk usage and enforce 50GB limit

**Features:**
- Real-time disk usage tracking
- Pauses downloads when limit exceeded
- Resumes downloads when space available

**Pseudocode:**
```go
func DiskMonitor(ctx context.Context, maxGB int64) {
    ticker := time.NewTicker(5 * time.Second)
    for {
        <-ticker.C
        usage := getCurrentDiskUsageGB()
        
        if usage > maxGB {
            pauseDownloads()
        } else if isPaused() {
            resumeDownloads()
        }
    }
}
```

### 5. State Saver
**Responsibility:** Persist download progress to Telegram

**Features:**
- Saves state to user's Telegram "Saved Messages"
- Format: JSON with last message ID, timestamp, stats
- Saves every 10 files or every 5 minutes
- Retrieves state on startup for resume

**State Format:**
```json
{
  "channel_id": "123456789",
  "channel_name": "example_channel",
  "last_message_id": 12345,
  "total_downloaded": 250,
  "total_uploaded": 248,
  "total_size_gb": 45.3,
  "timestamp": "2025-12-04T12:30:00Z",
  "status": "running"
}
```

**Pseudocode:**
```go
func StateSaver(ctx context.Context, client *tg.Client) {
    ticker := time.NewTicker(5 * time.Minute)
    for {
        select {
        case <-ticker.C:
            saveStateToTelegram(currentState)
        case <-forceStateUpdate:
            saveStateToTelegram(currentState)
        }
    }
}

func saveStateToTelegram(state State) {
    json := marshalState(state)
    sendToSavedMessages("📊 TDL Progress\n" + json)
}
```

## Command Line Interface

### New Command: `tdl dl-sync`

**Usage:**
```bash
# Start new sync
tdl dl-sync -u https://t.me/channel --max-disk 50 --gdrive

# Resume from saved state
tdl dl-sync -u https://t.me/channel --resume

# Resume from specific message ID
tdl dl-sync -u https://t.me/channel --resume-from 12345
```

**Flags:**
- `--max-disk` (int): Maximum disk usage in GB (default: 50)
- `--gdrive`: Enable Google Drive upload
- `--resume`: Resume from last saved state in Telegram
- `--resume-from` (int): Resume from specific message ID
- `--workers` (int): Number of parallel upload workers (default: 3)
- `--save-interval` (duration): State save interval (default: 5m)

## File Structure

```
pkg/
  sync/
    sync.go           # Main sync orchestrator
    download.go       # Download worker
    upload.go         # Upload worker
    cleanup.go        # Cleanup worker
    disk.go           # Disk monitor
    state.go          # State persistence
    queue.go          # File queue management

cmd/
  dl_sync.go          # CLI command definition

app/
  dlsync/
    dlsync.go         # Application logic
    options.go        # Command options
    progress.go       # Progress tracking
```

## Implementation Plan

### Phase 1: Core Infrastructure
1. Create sync package structure
2. Implement file queue with channels
3. Add disk usage monitor
4. Create state data structures

### Phase 2: Workers
1. Implement download worker
2. Implement upload worker (reuse existing gdrive code)
3. Implement cleanup worker
4. Add worker coordination

### Phase 3: State Persistence
1. Create state save to Telegram saved messages
2. Add state retrieval on startup
3. Implement resume from message ID
4. Add progress tracking

### Phase 4: Integration
1. Create dl-sync command
2. Wire up all components
3. Add error handling and recovery
4. Implement graceful shutdown

### Phase 5: Testing & Optimization
1. Test with small channel
2. Test resume functionality
3. Test disk limit enforcement
4. Test 6-hour interruption recovery
5. Optimize for GitHub Actions runner

## Data Flow

```
1. User runs: tdl dl-sync -u https://t.me/channel --gdrive --max-disk 50

2. System checks for saved state in Telegram
   ├─ Found: Resume from last message ID
   └─ Not found: Start from beginning

3. Download Worker starts fetching messages
   ├─ Downloads file to temp directory
   ├─ Adds to upload queue
   └─ Checks disk usage (pause if > 50GB)

4. Upload Worker (3 parallel instances)
   ├─ Takes file from upload queue
   ├─ Uploads to Google Drive
   ├─ Handles rate limits
   └─ Adds to cleanup queue

5. Cleanup Worker
   ├─ Takes file from cleanup queue
   ├─ Deletes local file
   └─ Updates disk usage counter

6. State Saver (every 5 min or 10 files)
   ├─ Collects current progress
   ├─ Saves to Telegram saved messages
   └─ Includes last message ID for resume

7. User interrupts (6 hour limit reached)
   ├─ Graceful shutdown
   ├─ Save final state
   └─ Exit

8. User resumes next day
   ├─ tdl dl-sync --resume
   ├─ Loads state from Telegram
   └─ Continues from last message ID
```

## Error Handling

### Download Errors
- Network timeout → Retry 3 times with exponential backoff
- File too large → Skip and log
- Permission denied → Skip and log
- Disk full → Wait for cleanup, then retry

### Upload Errors
- Rate limit (403/429) → Backoff and retry
- Quota exceeded (750GB) → Pause 24 hours, save state
- Network error → Retry 3 times
- Authentication error → Re-authenticate and retry

### State Save Errors
- Telegram API error → Retry 3 times
- Can't send message → Log locally to file as backup

## Recovery Scenarios

### Scenario 1: Process Killed Mid-Download
- State was saved 3 minutes ago
- Resume from last saved message ID
- Re-download last file (may be partial)
- Continue normally

### Scenario 2: Hit 750GB Google Drive Quota
- System detects quota error
- Saves current state to Telegram
- Prints: "Quota exceeded, resume in 24 hours"
- Exit gracefully

### Scenario 3: Network Interruption
- Downloads fail with timeout
- Retry mechanism attempts 3 times
- If all fail, pause for 30 seconds
- Resume from same message ID

### Scenario 4: Disk Full (unexpected)
- Monitor detects usage > 50GB
- Pause downloads immediately
- Wait for uploads to complete
- Resume when space available

## Performance Expectations

### For 300GB Channel on GitHub Actions

**Single 6-hour run:**
- Download speed: ~10-20 MB/s (GitHub runner)
- Upload speed: ~5-10 MB/s (to GDrive)
- Bottleneck: Upload (slower than download)
- Expected transfer: ~40-50GB per 6-hour run

**Timeline:**
- Day 1: 45GB (stops at 6 hours, saves state)
- Day 2: 45GB (resumes from message ID)
- Day 3: 45GB
- ...
- Day 7: ~30GB (complete)

**Efficiency:**
- Concurrent operations: ~80% disk utilization
- Sequential (current): ~30% disk utilization
- Improvement: **2.5x faster**

## Safety Features

1. **Disk Protection:** Hard limit at 50GB
2. **API Protection:** Rate limit handling with backoff
3. **State Protection:** Auto-save every 5 min + every 10 files
4. **Resume Protection:** Always save message ID before download
5. **Data Protection:** Only delete after confirmed upload
6. **Error Protection:** Retry mechanisms for transient failures

## Next Steps

1. ✅ Backup current code (DONE)
2. Create sync package structure
3. Implement file queue system
4. Build download worker
5. Build upload worker (integrate existing gdrive code)
6. Build cleanup worker
7. Implement state persistence to Telegram
8. Create dl-sync command
9. Test and iterate
10. Document and deploy
