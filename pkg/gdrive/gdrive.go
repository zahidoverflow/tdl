package gdrive

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/drive/v3"
	"google.golang.org/api/option"
)

const (
	credentialsFile = "gdrive_credentials.json"
	tokenFile       = "gdrive_token.json"
)

var (
	folderMu       sync.Mutex
	cachedDate     string
	cachedFolderID string
)

// GetClient retrieves a Google Drive client, handling OAuth2 authentication.
func GetClient(ctx context.Context, configDir string) (*drive.Service, error) {
	credsPath := filepath.Join(configDir, credentialsFile)
	b, err := os.ReadFile(credsPath)
	if err != nil {
		fmt.Printf("\n❌ Google Drive Credentials Not Found!\n")
		fmt.Printf("   Missing: %s\n\n", credsPath)
		fmt.Printf("   Setup steps:\n")
		fmt.Printf("   1. Create Google Cloud project: https://console.cloud.google.com/projectcreate\n")
		fmt.Printf("   2. Enable Drive API: https://console.cloud.google.com/apis/library/drive.googleapis.com\n")
		fmt.Printf("   3. Create OAuth credentials (Desktop app)\n")
		fmt.Printf("   4. Download JSON and save to: %s\n\n", credsPath)
		return nil, fmt.Errorf("unable to read client secret file: %v", err)
	}

	// If modifying these scopes, delete your previously saved token.json.
	config, err := google.ConfigFromJSON(b, drive.DriveFileScope)
	if err != nil {
		fmt.Printf("\n❌ Invalid Google Drive Credentials!\n")
		fmt.Printf("   File: %s\n", credsPath)
		fmt.Printf("   Error: %v\n\n", err)
		fmt.Printf("   Solutions:\n")
		fmt.Printf("   → Re-download OAuth credentials from Google Cloud Console\n")
		fmt.Printf("   → Ensure you selected 'Desktop app' (not Web app)\n")
		fmt.Printf("   → Check JSON file is not corrupted\n\n")
		return nil, fmt.Errorf("unable to parse client secret file to config: %v", err)
	}

	tokenPath := filepath.Join(configDir, tokenFile)
	tok, err := tokenFromFile(tokenPath)
	if err != nil {
		tok, err = getTokenFromWeb(config)
		if err != nil {
			return nil, err
		}
		saveToken(tokenPath, tok)
	}

	client := config.Client(ctx, tok)
	srv, err := drive.NewService(ctx, option.WithHTTPClient(client))
	if err != nil {
		fmt.Printf("\n❌ Failed to Connect to Google Drive!\n")
		fmt.Printf("   Error: %v\n\n", err)
		fmt.Printf("   Troubleshooting:\n")
		fmt.Printf("   → Check internet connection\n")
		fmt.Printf("   → Verify Drive API is enabled\n")
		fmt.Printf("   → Delete token and re-authenticate: rm %s\n\n", tokenPath)
		return nil, fmt.Errorf("unable to retrieve Drive client: %v", err)
	}

	return srv, nil
}

// getTokenFromWeb prompts the user to authorize the application and returns the token.
func getTokenFromWeb(config *oauth2.Config) (*oauth2.Token, error) {
	authURL := config.AuthCodeURL("state-token", oauth2.AccessTypeOffline)
	fmt.Printf("Go to the following link in your browser then type the "+
		"authorization code: \n%v\n", authURL)

	var authCode string
	if _, err := fmt.Scan(&authCode); err != nil {
		return nil, fmt.Errorf("unable to read authorization code: %v", err)
	}

	tok, err := config.Exchange(context.TODO(), authCode)
	if err != nil {
		return nil, fmt.Errorf("unable to retrieve token from web: %v", err)
	}
	return tok, nil
}

// tokenFromFile retrieves a token from a local file.
func tokenFromFile(file string) (*oauth2.Token, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	tok := &oauth2.Token{}
	err = json.NewDecoder(f).Decode(tok)
	return tok, err
}

// saveToken saves a token to a file path.
func saveToken(path string, token *oauth2.Token) {
	fmt.Printf("Saving credential file to: %s\n", path)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		fmt.Printf("Unable to cache oauth token: %v", err)
		return
	}
	defer f.Close()
	json.NewEncoder(f).Encode(token)
}

func getDateFolderID(ctx context.Context, srv *drive.Service) (string, error) {
	today := time.Now().Format("2006-01-02")

	folderMu.Lock()
	defer folderMu.Unlock()

	if cachedDate == today && cachedFolderID != "" {
		return cachedFolderID, nil
	}

	q := fmt.Sprintf("mimeType = 'application/vnd.google-apps.folder' and name = '%s' and 'root' in parents and trashed = false", today)
	res, err := srv.Files.List().
		Q(q).
		PageSize(1).
		Fields("files(id,name)").
		Context(ctx).
		Do()
	if err == nil && len(res.Files) > 0 {
		cachedDate = today
		cachedFolderID = res.Files[0].Id
		return cachedFolderID, nil
	}

	folder := &drive.File{
		Name:     today,
		MimeType: "application/vnd.google-apps.folder",
		Parents:  []string{"root"},
	}

	created, err := srv.Files.Create(folder).Context(ctx).Do()
	if err != nil {
		return "", err
	}

	cachedDate = today
	cachedFolderID = created.Id
	return cachedFolderID, nil
}

// UploadFile uploads a file to Google Drive under a date-based folder (YYYY-MM-DD) at root.
func UploadFile(ctx context.Context, srv *drive.Service, name string, content io.Reader) (*drive.File, error) {
	folderID, err := getDateFolderID(ctx, srv)
	if err != nil {
		return nil, fmt.Errorf("resolve date folder: %w", err)
	}

	file := &drive.File{
		Name:    name,
		Parents: []string{folderID},
	}
	f, err := srv.Files.Create(file).Context(ctx).Media(content).Do()
	if err != nil {
		// Check for common Google Drive API errors and provide helpful messages
		errMsg := err.Error()

		if containsAny(errMsg, "403", "User rate limit exceeded", "userRateLimitExceeded") {
			fmt.Printf("\n⚠️  Google Drive Rate Limit Hit!\n")
			fmt.Printf("   You've exceeded 12,000 requests per minute.\n")
			fmt.Printf("   → Wait 1-2 minutes and try again\n")
			fmt.Printf("   → Add delays between uploads (sleep 5-10 seconds)\n\n")
			return nil, fmt.Errorf("rate limit exceeded (403): wait 1-2 minutes before retrying")
		}

		if containsAny(errMsg, "429", "Too many requests", "rateLimitExceeded") {
			fmt.Printf("\n⚠️  Google Drive API Rate Limit!\n")
			fmt.Printf("   Too many requests in a short time.\n")
			fmt.Printf("   → Wait 60 seconds and retry\n")
			fmt.Printf("   → Reduce upload speed\n\n")
			return nil, fmt.Errorf("too many requests (429): retry after 60 seconds")
		}

		if containsAny(errMsg, "quota", "quotaExceeded", "Daily Limit Exceeded", "dailyLimitExceeded") {
			fmt.Printf("\n🚫 Google Drive Daily Quota Exceeded!\n")
			fmt.Printf("   You've uploaded 750GB in the last 24 hours.\n")
			fmt.Printf("   → Wait 24 hours before uploading more\n")
			fmt.Printf("   → Quota resets automatically\n")
			fmt.Printf("   → Your account is SAFE (no suspension)\n\n")
			return nil, fmt.Errorf("daily upload quota exceeded (750GB): wait 24 hours")
		}

		if containsAny(errMsg, "storageQuotaExceeded", "storage quota", "insufficient storage") {
			fmt.Printf("\n💾 Google Drive Storage Full!\n")
			fmt.Printf("   Your Google Drive storage is full.\n")
			fmt.Printf("   → Delete old files to free up space\n")
			fmt.Printf("   → Upgrade storage plan if needed\n\n")
			return nil, fmt.Errorf("storage quota exceeded: delete files or upgrade storage")
		}

		if containsAny(errMsg, "invalid_grant", "Token has been expired or revoked") {
			fmt.Printf("\n🔑 Google Drive Authentication Expired!\n")
			fmt.Printf("   Your OAuth token is invalid or expired.\n")
			fmt.Printf("   → Delete ~/.tdl/gdrive_token.json\n")
			fmt.Printf("   → Run the upload command again to re-authenticate\n\n")
			return nil, fmt.Errorf("authentication expired: delete token file and re-authenticate")
		}

		if containsAny(errMsg, "connection", "network", "timeout", "i/o timeout") {
			fmt.Printf("\n🌐 Network Connection Error!\n")
			fmt.Printf("   Failed to connect to Google Drive API.\n")
			fmt.Printf("   → Check your internet connection\n")
			fmt.Printf("   → Retry the upload\n\n")
			return nil, fmt.Errorf("network error: check internet connection and retry")
		}

		// Generic error with helpful context
		fmt.Printf("\n❌ Google Drive Upload Failed!\n")
		fmt.Printf("   File: %s\n", name)
		fmt.Printf("   Error: %v\n\n", err)
		fmt.Printf("   Common solutions:\n")
		fmt.Printf("   → Check internet connection\n")
		fmt.Printf("   → Verify API is enabled: https://console.cloud.google.com/apis/library/drive.googleapis.com\n")
		fmt.Printf("   → Re-authenticate if needed (delete ~/.tdl/gdrive_token.json)\n\n")

		return nil, fmt.Errorf("could not create file: %v", err)
	}
	return f, nil
}

// containsAny checks if the string contains any of the substrings (case-insensitive)
func containsAny(s string, substrs ...string) bool {
	lower := strings.ToLower(s)
	for _, substr := range substrs {
		if strings.Contains(lower, strings.ToLower(substr)) {
			return true
		}
	}
	return false
}
