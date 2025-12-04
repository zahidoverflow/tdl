package sync

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/gotd/td/telegram/message"
	"github.com/gotd/td/tg"
)

const (
	StateMessagePrefix = "🔄 TDL Sync State"
)

// StateSaver handles saving and loading sync state to/from Telegram saved messages
type StateSaver struct {
	client       *tg.Client
	saveInterval time.Duration
	state        *SyncState
}

// NewStateSaver creates a new state saver
func NewStateSaver(client *tg.Client, state *SyncState, saveInterval time.Duration) *StateSaver {
	return &StateSaver{
		client:       client,
		saveInterval: saveInterval,
		state:        state,
	}
}

// Start begins periodic state saving
func (s *StateSaver) Start(ctx context.Context, forceSave <-chan struct{}) error {
	ticker := time.NewTicker(s.saveInterval)
	defer ticker.Stop()
	
	fileCount := 0
	
	for {
		select {
		case <-ctx.Done():
			// Save final state before exit
			if err := s.SaveState(ctx); err != nil {
				fmt.Printf("⚠️ Failed to save final state: %v\n", err)
			}
			return ctx.Err()
			
		case <-ticker.C:
			if err := s.SaveState(ctx); err != nil {
				fmt.Printf("⚠️ Failed to save state: %v\n", err)
			}
			
		case <-forceSave:
			if err := s.SaveState(ctx); err != nil {
				fmt.Printf("⚠️ Failed to force-save state: %v\n", err)
			}
			fileCount++
			
			// Save every 10 files
			if fileCount%10 == 0 {
				if err := s.SaveState(ctx); err != nil {
					fmt.Printf("⚠️ Failed to save state (file milestone): %v\n", err)
				}
			}
		}
	}
}

// SaveState saves current state to Telegram saved messages
func (s *StateSaver) SaveState(ctx context.Context) error {
	stats := s.state.GetStats()
	
	// Create JSON representation
	stateJSON, err := json.MarshalIndent(map[string]interface{}{
		"channel_id":       stats.ChannelID,
		"channel_name":     stats.ChannelName,
		"last_message_id":  stats.LastMessageID,
		"total_files":      stats.TotalFiles,
		"downloaded":       stats.Downloaded,
		"uploaded":         stats.Uploaded,
		"cleaned":          stats.Cleaned,
		"failed":           stats.Failed,
		"total_size_gb":    float64(stats.TotalSizeBytes) / (1024 * 1024 * 1024),
		"timestamp":        stats.LastUpdateTime.Format(time.RFC3339),
		"status":           stats.Status,
		"elapsed_minutes":  time.Since(stats.StartTime).Minutes(),
	}, "", "  ")
	
	if err != nil {
		return fmt.Errorf("failed to marshal state: %w", err)
	}
	
	// Format message
	messageText := fmt.Sprintf("%s\n\n```json\n%s\n```\n\n📊 Progress: %d/%d uploaded (%.1f%%)\n💾 Size: %.2fGB\n⏱️ Runtime: %s",
		StateMessagePrefix,
		string(stateJSON),
		stats.Uploaded,
		stats.TotalFiles,
		float64(stats.Uploaded)/float64(max(stats.TotalFiles, 1))*100,
		float64(stats.TotalSizeBytes)/(1024*1024*1024),
		time.Since(stats.StartTime).Round(time.Minute),
	)
	
	// Send to saved messages
	sender := message.NewSender(s.client)
	_, err = sender.Self().Text(ctx, messageText)
	if err != nil {
		return fmt.Errorf("failed to send state to saved messages: %w", err)
	}
	
	fmt.Printf("💾 State saved to Telegram (msg %d)\n", stats.LastMessageID)
	return nil
}

// LoadState loads the most recent state from Telegram saved messages
func (s *StateSaver) LoadState(ctx context.Context) (*SyncState, error) {
	// Get saved messages (self chat)
	api := tg.NewClient(s.client)
	
	// Get self user
	self, err := api.UsersGetFullUser(ctx, &tg.InputUserSelf{})
	if err != nil {
		return nil, fmt.Errorf("failed to get self user: %w", err)
	}
	
	// Get messages from saved messages
	fullUser, ok := self.(*tg.UserFull)
	if !ok {
		return nil, fmt.Errorf("unexpected type for self user")
	}
	
	// Search for state messages
	messages, err := api.MessagesSearch(ctx, &tg.MessagesSearchRequest{
		Peer: &tg.InputPeerSelf{},
		Q:    StateMessagePrefix,
		Filter: &tg.InputMessagesFilterEmpty{},
		Limit: 1,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to search saved messages: %w", err)
	}
	
	// Parse messages
	switch msgs := messages.(type) {
	case *tg.MessagesMessages:
		if len(msgs.Messages) == 0 {
			return nil, fmt.Errorf("no saved state found")
		}
		
		// Get the most recent state message
		msg, ok := msgs.Messages[0].(*tg.Message)
		if !ok {
			return nil, fmt.Errorf("unexpected message type")
		}
		
		// Extract JSON from message text
		text := msg.Message
		
		// Parse JSON (extract from code block)
		start := indexOf(text, "```json\n")
		end := indexOf(text[start+8:], "\n```")
		if start == -1 || end == -1 {
			return nil, fmt.Errorf("invalid state message format")
		}
		
		jsonStr := text[start+8 : start+8+end]
		
		var stateData map[string]interface{}
		if err := json.Unmarshal([]byte(jsonStr), &stateData); err != nil {
			return nil, fmt.Errorf("failed to parse state JSON: %w", err)
		}
		
		// Reconstruct SyncState
		state := &SyncState{
			ChannelID:      int64(stateData["channel_id"].(float64)),
			ChannelName:    stateData["channel_name"].(string),
			LastMessageID:  int(stateData["last_message_id"].(float64)),
			TotalFiles:     int(stateData["total_files"].(float64)),
			Downloaded:     int(stateData["downloaded"].(float64)),
			Uploaded:       int(stateData["uploaded"].(float64)),
			Cleaned:        int(stateData["cleaned"].(float64)),
			Failed:         int(stateData["failed"].(float64)),
			TotalSizeBytes: int64(stateData["total_size_gb"].(float64) * 1024 * 1024 * 1024),
			Status:         stateData["status"].(string),
		}
		
		timestamp, _ := time.Parse(time.RFC3339, stateData["timestamp"].(string))
		state.LastUpdateTime = timestamp
		
		fmt.Printf("📥 Loaded saved state from Telegram\n")
		fmt.Printf("   Last message ID: %d\n", state.LastMessageID)
		fmt.Printf("   Progress: %d/%d uploaded\n", state.Uploaded, state.TotalFiles)
		
		return state, nil
	}
	
	return nil, fmt.Errorf("no saved state found")
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func indexOf(s, substr string) int {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
