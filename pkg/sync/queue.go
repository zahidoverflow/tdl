package sync

import (
	"context"
	"sync"
	"time"
)

// FileState represents the state of a file in the sync pipeline
type FileState int

const (
	StateQueued FileState = iota
	StateDownloading
	StateDownloaded
	StateUploading
	StateUploaded
	StateCleaned
	StateFailed
)

// FileJob represents a file being processed through the sync pipeline
type FileJob struct {
	MessageID   int
	FileName    string
	FilePath    string
	FileSize    int64
	State       FileState
	Error       error
	RetryCount  int
	QueuedAt    time.Time
	CompletedAt time.Time
}

// SyncState represents the overall sync progress
type SyncState struct {
	ChannelID       int64
	ChannelName     string
	LastMessageID   int
	TotalFiles      int
	Downloaded      int
	Uploaded        int
	Cleaned         int
	Failed          int
	TotalSizeBytes  int64
	StartTime       time.Time
	LastUpdateTime  time.Time
	Status          string // "running", "paused", "completed", "error"
	
	mu sync.RWMutex
}

// UpdateStats updates the sync statistics
func (s *SyncState) UpdateStats(job *FileJob) {
	s.mu.Lock()
	defer s.mu.Unlock()
	
	switch job.State {
	case StateDownloaded:
		s.Downloaded++
	case StateUploaded:
		s.Uploaded++
	case StateCleaned:
		s.Cleaned++
	case StateFailed:
		s.Failed++
	}
	
	s.LastMessageID = job.MessageID
	s.LastUpdateTime = time.Now()
}

// GetStats returns a copy of current stats
func (s *SyncState) GetStats() SyncState {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return *s
}

// ToJSON converts state to JSON string for saving to Telegram
func (s *SyncState) ToJSON() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	
	return `{
  "channel_id": ` + string(rune(s.ChannelID)) + `,
  "channel_name": "` + s.ChannelName + `",
  "last_message_id": ` + string(rune(s.LastMessageID)) + `,
  "total_files": ` + string(rune(s.TotalFiles)) + `,
  "downloaded": ` + string(rune(s.Downloaded)) + `,
  "uploaded": ` + string(rune(s.Uploaded)) + `,
  "cleaned": ` + string(rune(s.Cleaned)) + `,
  "failed": ` + string(rune(s.Failed)) + `,
  "total_size_gb": ` + string(rune(s.TotalSizeBytes/(1024*1024*1024))) + `,
  "timestamp": "` + s.LastUpdateTime.Format(time.RFC3339) + `",
  "status": "` + s.Status + `"
}`
}

// JobQueue manages the file processing queue
type JobQueue struct {
	downloadCh chan *FileJob
	uploadCh   chan *FileJob
	cleanupCh  chan *FileJob
	
	mu sync.RWMutex
}

// NewJobQueue creates a new job queue
func NewJobQueue(bufferSize int) *JobQueue {
	return &JobQueue{
		downloadCh: make(chan *FileJob, bufferSize),
		uploadCh:   make(chan *FileJob, bufferSize),
		cleanupCh:  make(chan *FileJob, bufferSize),
	}
}

// AddDownload adds a file to download queue
func (q *JobQueue) AddDownload(job *FileJob) {
	job.State = StateQueued
	job.QueuedAt = time.Now()
	q.downloadCh <- job
}

// GetDownload gets next file to download
func (q *JobQueue) GetDownload(ctx context.Context) (*FileJob, bool) {
	select {
	case job := <-q.downloadCh:
		return job, true
	case <-ctx.Done():
		return nil, false
	}
}

// AddUpload adds a file to upload queue
func (q *JobQueue) AddUpload(job *FileJob) {
	job.State = StateDownloaded
	q.uploadCh <- job
}

// GetUpload gets next file to upload
func (q *JobQueue) GetUpload(ctx context.Context) (*FileJob, bool) {
	select {
	case job := <-q.uploadCh:
		return job, true
	case <-ctx.Done():
		return nil, false
	}
}

// AddCleanup adds a file to cleanup queue
func (q *JobQueue) AddCleanup(job *FileJob) {
	job.State = StateUploaded
	q.cleanupCh <- job
}

// GetCleanup gets next file to cleanup
func (q *JobQueue) GetCleanup(ctx context.Context) (*FileJob, bool) {
	select {
	case job := <-q.cleanupCh:
		return job, true
	case <-ctx.Done():
		return nil, false
	}
}

// Close closes all channels
func (q *JobQueue) Close() {
	close(q.downloadCh)
	close(q.uploadCh)
	close(q.cleanupCh)
}
