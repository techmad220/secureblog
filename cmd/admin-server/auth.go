// auth.go - Ultra-paranoid authentication with Argon2id + 2FA
package main

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"golang.org/x/crypto/argon2"
	"github.com/pquerna/otp"
	"github.com/pquerna/otp/totp"
)

// Argon2id parameters (OWASP recommended)
type ArgonParams struct {
	Memory      uint32 // Memory in KB
	Iterations  uint32 // Number of iterations
	Parallelism uint8  // Number of threads
	SaltLength  uint32 // Length of salt
	KeyLength   uint32 // Length of derived key
}

// Ultra-secure Argon2id parameters
var argonParams = &ArgonParams{
	Memory:      128 * 1024, // 128 MB (paranoid level)
	Iterations:  4,          // 4 iterations (vs 3 standard)
	Parallelism: 4,          // 4 threads
	SaltLength:  32,         // 32 bytes salt (vs 16 standard)
	KeyLength:   64,         // 64 bytes key (vs 32 standard)
}

// Password requirements (paranoid level)
var passwordRequirements = struct {
	MinLength    int
	RequireUpper bool
	RequireLower bool
	RequireNum   bool
	RequireSpec  bool
	NoCommon     bool
}{
	MinLength:    20,   // 20 characters minimum
	RequireUpper: true,
	RequireLower: true,
	RequireNum:   true,
	RequireSpec:  true,
	NoCommon:     true,
}

// Common weak passwords (partial list for demo)
var commonPasswords = []string{
	"password", "123456", "admin", "secure123", "qwerty",
	"letmein", "welcome", "monkey", "dragon", "master",
}

// Session data structure
type Session struct {
	Username    string    `json:"username"`
	LoginTime   time.Time `json:"login_time"`
	LastActive  time.Time `json:"last_active"`
	IPAddress   string    `json:"ip_address"`
	UserAgent   string    `json:"user_agent"`
	TwoFAVerified bool    `json:"two_fa_verified"`
}

// Password hash structure
type PasswordHash struct {
	Hash   string `json:"hash"`
	Salt   string `json:"salt"`
	Params string `json:"params"`
}

// 2FA configuration
type TwoFAConfig struct {
	Secret   string `json:"secret"`
	Enabled  bool   `json:"enabled"`
	BackupCodes []string `json:"backup_codes"`
}

// ValidatePasswordStrength checks password against paranoid requirements
func ValidatePasswordStrength(password string) error {
	// Length check
	if len(password) < passwordRequirements.MinLength {
		return fmt.Errorf("password must be at least %d characters long", passwordRequirements.MinLength)
	}

	// Character class requirements
	var hasUpper, hasLower, hasNum, hasSpec bool
	
	for _, char := range password {
		switch {
		case char >= 'A' && char <= 'Z':
			hasUpper = true
		case char >= 'a' && char <= 'z':
			hasLower = true
		case char >= '0' && char <= '9':
			hasNum = true
		case strings.ContainsRune("!@#$%^&*()_+-=[]{}|;:,.<>?", char):
			hasSpec = true
		}
	}

	if passwordRequirements.RequireUpper && !hasUpper {
		return fmt.Errorf("password must contain at least one uppercase letter")
	}
	if passwordRequirements.RequireLower && !hasLower {
		return fmt.Errorf("password must contain at least one lowercase letter")
	}
	if passwordRequirements.RequireNum && !hasNum {
		return fmt.Errorf("password must contain at least one number")
	}
	if passwordRequirements.RequireSpec && !hasSpec {
		return fmt.Errorf("password must contain at least one special character")
	}

	// Check against common passwords
	if passwordRequirements.NoCommon {
		passwordLower := strings.ToLower(password)
		for _, common := range commonPasswords {
			if strings.Contains(passwordLower, common) {
				return fmt.Errorf("password contains common/weak patterns")
			}
		}
	}

	// Check for keyboard patterns (basic)
	keyboardPatterns := []string{
		"qwerty", "asdf", "zxcv", "12345", "abcde",
		"qwertyuiop", "asdfghjkl", "zxcvbnm",
	}
	
	passwordLower := strings.ToLower(password)
	for _, pattern := range keyboardPatterns {
		if strings.Contains(passwordLower, pattern) && len(pattern) >= 5 {
			return fmt.Errorf("password contains keyboard patterns")
		}
	}

	return nil
}

// GenerateSalt creates a cryptographically secure random salt
func GenerateSalt() ([]byte, error) {
	salt := make([]byte, argonParams.SaltLength)
	_, err := rand.Read(salt)
	if err != nil {
		return nil, fmt.Errorf("failed to generate salt: %w", err)
	}
	return salt, nil
}

// HashPasswordArgon2id creates Argon2id hash of password
func HashPasswordArgon2id(password string, salt []byte) []byte {
	return argon2.IDKey(
		[]byte(password),
		salt,
		argonParams.Iterations,
		argonParams.Memory,
		argonParams.Parallelism,
		argonParams.KeyLength,
	)
}

// CreatePasswordHash generates full password hash with metadata
func CreatePasswordHash(password string) (PasswordHash, error) {
	salt, err := GenerateSalt()
	if err != nil {
		return PasswordHash{}, err
	}

	hash := HashPasswordArgon2id(password, salt)
	
	return PasswordHash{
		Hash: base64.StdEncoding.EncodeToString(hash),
		Salt: base64.StdEncoding.EncodeToString(salt),
		Params: fmt.Sprintf("argon2id$v=19$m=%d,t=%d,p=%d",
			argonParams.Memory, argonParams.Iterations, argonParams.Parallelism),
	}, nil
}

// VerifyPasswordHash verifies password against stored hash
func VerifyPasswordHash(password string, stored PasswordHash) bool {
	salt, err := base64.StdEncoding.DecodeString(stored.Salt)
	if err != nil {
		return false
	}

	storedHash, err := base64.StdEncoding.DecodeString(stored.Hash)
	if err != nil {
		return false
	}

	computedHash := HashPasswordArgon2id(password, salt)
	
	// Constant-time comparison to prevent timing attacks
	return subtle.ConstantTimeCompare(storedHash, computedHash) == 1
}

// InitializeAdminPassword sets up admin password with validation and hashing
func InitializeAdminPassword() (PasswordHash, error) {
	adminPassword := os.Getenv("ADMIN_PASSWORD")
	
	// Default password validation
	if adminPassword == "" {
		return PasswordHash{}, fmt.Errorf(`ADMIN_PASSWORD not set. Set a strong password:
		
Minimum requirements:
- 20+ characters
- Uppercase letters
- Lowercase letters  
- Numbers
- Special characters
- No common passwords or patterns

Example:
export ADMIN_PASSWORD="MyS3cur3B10g!AdminP@ssw0rd2024#Secure"`)
	}

	// Validate password strength
	if err := ValidatePasswordStrength(adminPassword); err != nil {
		return PasswordHash{}, fmt.Errorf("password validation failed: %w", err)
	}

	// Create Argon2id hash
	return CreatePasswordHash(adminPassword)
}

// Setup2FA generates 2FA secret and backup codes
func Setup2FA(username string) (TwoFAConfig, error) {
	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      "SecureBlog",
		AccountName: username,
		Period:      30,
		Digits:      otp.DigitsSix,
		Algorithm:   otp.AlgorithmSHA256, // SHA-256 instead of SHA-1
	})
	if err != nil {
		return TwoFAConfig{}, fmt.Errorf("failed to generate 2FA key: %w", err)
	}

	// Generate backup codes
	backupCodes, err := generateBackupCodes(10)
	if err != nil {
		return TwoFAConfig{}, fmt.Errorf("failed to generate backup codes: %w", err)
	}

	return TwoFAConfig{
		Secret:      key.Secret(),
		Enabled:     false, // Must be explicitly enabled
		BackupCodes: backupCodes,
	}, nil
}

// generateBackupCodes creates cryptographically secure backup codes
func generateBackupCodes(count int) ([]string, error) {
	codes := make([]string, count)
	
	for i := 0; i < count; i++ {
		// Generate 8 random bytes = 64-bit code
		bytes := make([]byte, 8)
		_, err := rand.Read(bytes)
		if err != nil {
			return nil, err
		}
		
		// Convert to base32 for human readability
		code := base64.StdEncoding.EncodeToString(bytes)
		// Take first 8 characters and format
		codes[i] = fmt.Sprintf("%s-%s", 
			code[:4], code[4:8])
	}
	
	return codes, nil
}

// VerifyTOTP validates TOTP code
func VerifyTOTP(secret, token string) bool {
	// Allow for clock drift (±1 period = ±30 seconds)
	return totp.Validate(token, secret)
}

// VerifyBackupCode checks if backup code is valid
func VerifyBackupCode(config *TwoFAConfig, code string) bool {
	for i, backupCode := range config.BackupCodes {
		if subtle.ConstantTimeCompare([]byte(backupCode), []byte(code)) == 1 {
			// Remove used backup code (one-time use)
			config.BackupCodes = append(config.BackupCodes[:i], config.BackupCodes[i+1:]...)
			return true
		}
	}
	return false
}

// IsSessionValid checks if session is still valid (not expired)
func IsSessionValid(session Session, timeout time.Duration) bool {
	// Check if session has timed out
	if time.Since(session.LastActive) > timeout {
		return false
	}
	
	// Check if login is too old (max 24 hours regardless of activity)
	if time.Since(session.LoginTime) > 24*time.Hour {
		return false
	}
	
	return true
}

// UpdateSessionActivity updates the last active time
func UpdateSessionActivity(session *Session) {
	session.LastActive = time.Now()
}

// GetClientIP extracts real client IP (handling proxies)
func GetClientIP(r *http.Request) string {
	// For localhost, this should always be 127.0.0.1
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		// Take the first IP in the chain
		ips := strings.Split(forwarded, ",")
		return strings.TrimSpace(ips[0])
	}
	
	if realIP := r.Header.Get("X-Real-IP"); realIP != "" {
		return realIP
	}
	
	// Split host:port to get just the IP
	ip := strings.Split(r.RemoteAddr, ":")[0]
	return ip
}

// ValidateClientIP ensures connection is from localhost only
func ValidateClientIP(ip string) bool {
	// Only allow localhost connections
	allowedIPs := []string{"127.0.0.1", "::1", "localhost"}
	
	for _, allowed := range allowedIPs {
		if ip == allowed {
			return true
		}
	}
	
	return false
}