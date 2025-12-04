package sync

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"time"
)

// DiskMonitor monitors disk usage and enforces limits
type DiskMonitor struct {
	maxBytes      int64
	currentBytes  atomic.Int64
	downloadDir   string
	paused        atomic.Bool
	checkInterval time.Duration
}

// NewDiskMonitor creates a new disk monitor
func NewDiskMonitor(maxGB int, downloadDir string) *DiskMonitor {
	return &DiskMonitor{
		maxBytes:      int64(maxGB) * 1024 * 1024 * 1024,
		downloadDir:   downloadDir,
		checkInterval: 5 * time.Second,
	}
}

// Start begins monitoring disk usage
func (d *DiskMonitor) Start(ctx context.Context) error {
	// Initial calculation
	if err := d.calculateDiskUsage(); err != nil {
		return fmt.Errorf("initial disk calculation failed: %w", err)
	}
	
	ticker := time.NewTicker(d.checkInterval)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if err := d.calculateDiskUsage(); err != nil {
				fmt.Printf("⚠️ Disk monitor error: %v\n", err)
				continue
			}
			
			currentGB := float64(d.currentBytes.Load()) / (1024 * 1024 * 1024)
			maxGB := float64(d.maxBytes) / (1024 * 1024 * 1024)
			
			if d.currentBytes.Load() > d.maxBytes {
				if !d.paused.Load() {
					fmt.Printf("\n⚠️ Disk limit reached: %.2fGB / %.2fGB\n", currentGB, maxGB)
					fmt.Printf("   ⏸️  Pausing downloads until space is freed...\n")
					d.paused.Store(true)
				}
			} else {
				if d.paused.Load() {
					fmt.Printf("\n✅ Disk space available: %.2fGB / %.2fGB\n", currentGB, maxGB)
					fmt.Printf("   ▶️  Resuming downloads...\n")
					d.paused.Store(false)
				}
			}
		}
	}
}

// calculateDiskUsage calculates current disk usage
func (d *DiskMonitor) calculateDiskUsage() error {
	var totalSize int64
	
	err := filepath.Walk(d.downloadDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip errors
		}
		if !info.IsDir() {
			totalSize += info.Size()
		}
		return nil
	})
	
	if err != nil {
		return err
	}
	
	d.currentBytes.Store(totalSize)
	return nil
}

// AddFile adds file size to tracking
func (d *DiskMonitor) AddFile(size int64) {
	d.currentBytes.Add(size)
}

// RemoveFile removes file size from tracking
func (d *DiskMonitor) RemoveFile(size int64) {
	d.currentBytes.Add(-size)
}

// IsPaused returns whether downloads are paused
func (d *DiskMonitor) IsPaused() bool {
	return d.paused.Load()
}

// GetUsageGB returns current disk usage in GB
func (d *DiskMonitor) GetUsageGB() float64 {
	return float64(d.currentBytes.Load()) / (1024 * 1024 * 1024)
}

// GetMaxGB returns maximum allowed disk usage in GB
func (d *DiskMonitor) GetMaxGB() float64 {
	return float64(d.maxBytes) / (1024 * 1024 * 1024)
}

// WaitForSpace blocks until disk space is available
func (d *DiskMonitor) WaitForSpace(ctx context.Context) error {
	for d.IsPaused() {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
			// Continue checking
		}
	}
	return nil
}
