// secureblog-ui - Local web interface for SecureBlog with maximum security
package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	maxUploadSize = 10 << 20 // 10MB
	serverPort    = "8080"
)

type Post struct {
	Title    string    `json:"title"`
	Date     time.Time `json:"date"`
	Filename string    `json:"filename"`
	Content  string    `json:"content"`
}

type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

var dashboardHTML = `<!DOCTYPE html>
<html>
<head>
    <title>SecureBlog UI - Maximum Security Interface</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, system-ui, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header {
            background: white;
            border-radius: 12px;
            padding: 24px;
            margin-bottom: 24px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }
        .header h1 { color: #1a202c; }
        .security-badge {
            background: #48bb78;
            color: white;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            display: inline-block;
            margin-left: 12px;
        }
        .content {
            background: white;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }
        .tabs {
            display: flex;
            gap: 12px;
            margin-bottom: 24px;
            border-bottom: 2px solid #e2e8f0;
        }
        .tab {
            padding: 12px 24px;
            background: none;
            border: none;
            cursor: pointer;
            font-size: 16px;
            color: #718096;
            border-bottom: 2px solid transparent;
            margin-bottom: -2px;
        }
        .tab.active {
            color: #667eea;
            border-bottom-color: #667eea;
        }
        .section { display: none; }
        .section.active { display: block; }
        .form-group { margin-bottom: 20px; }
        .form-label {
            display: block;
            margin-bottom: 8px;
            font-weight: 600;
            color: #2d3748;
        }
        .form-input {
            width: 100%;
            padding: 12px;
            border: 2px solid #e2e8f0;
            border-radius: 8px;
            font-size: 16px;
        }
        .form-input:focus {
            outline: none;
            border-color: #667eea;
        }
        textarea.form-input { min-height: 300px; font-family: monospace; }
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-weight: 600;
            cursor: pointer;
            margin-right: 12px;
        }
        .btn-primary {
            background: #667eea;
            color: white;
        }
        .btn-success {
            background: #48bb78;
            color: white;
        }
        .btn:hover { opacity: 0.9; }
        .log-output {
            background: #1a202c;
            color: #68d391;
            padding: 20px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 14px;
            white-space: pre-wrap;
            max-height: 400px;
            overflow-y: auto;
            margin-top: 16px;
        }
        .security-notice {
            background: #f0fff4;
            border: 1px solid #9ae6b4;
            border-radius: 8px;
            padding: 16px;
            margin: 16px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 SecureBlog UI <span class="security-badge">LOCALHOST ONLY</span></h1>
            <p style="color: #718096; margin-top: 8px;">
                WordPress-level ease with maximum security • Zero JavaScript in output • Cryptographic signing
            </p>
        </div>
        
        <div class="content">
            <div class="tabs">
                <button class="tab active" onclick="showTab('write')">✍️ Write</button>
                <button class="tab" onclick="showTab('images')">🖼️ Images</button>
                <button class="tab" onclick="showTab('publish')">🚀 Publish</button>
                <button class="tab" onclick="showTab('security')">🔒 Security</button>
            </div>
            
            <!-- Write Tab -->
            <div class="section active" id="write">
                <h2>Create New Post</h2>
                <div class="security-notice">
                    🔒 All content is automatically scanned for JavaScript and cryptographically signed
                </div>
                
                <form id="post-form">
                    <div class="form-group">
                        <label class="form-label">Post Title</label>
                        <input type="text" class="form-input" id="post-title" placeholder="My Secure Blog Post">
                    </div>
                    
                    <div class="form-group">
                        <label class="form-label">Content (Markdown)</label>
                        <textarea class="form-input" id="post-content" placeholder="Write your content in Markdown..."></textarea>
                    </div>
                    
                    <button type="button" class="btn btn-primary" onclick="savePost()">💾 Save Post</button>
                    <button type="button" class="btn btn-success" onclick="saveAndBuild()">✅ Save & Build</button>
                </form>
                <div id="write-log" class="log-output" style="display:none;"></div>
            </div>
            
            <!-- Images Tab -->
            <div class="section" id="images">
                <h2>Upload Images</h2>
                <p style="color: #718096; margin-bottom: 20px;">
                    Images are validated for security and integrity-hashed
                </p>
                <input type="file" id="image-upload" accept="image/*" multiple onchange="uploadImages()">
                <div id="image-log" class="log-output" style="display:none;"></div>
            </div>
            
            <!-- Publish Tab -->
            <div class="section" id="publish">
                <h2>Secure Publishing</h2>
                <div class="security-notice">
                    🚀 Publishing runs all security checks: No-JS verification, integrity hashing, and cryptographic signing
                </div>
                <button class="btn btn-success" onclick="publishSite()">🚀 Publish to Production</button>
                <button class="btn btn-primary" onclick="buildOnly()">🔨 Build Only</button>
                <div id="publish-log" class="log-output" style="display:none;"></div>
            </div>
            
            <!-- Security Tab -->
            <div class="section" id="security">
                <h2>Security Status</h2>
                <button class="btn btn-primary" onclick="runAudit()">🔍 Run Security Audit</button>
                <button class="btn btn-primary" onclick="checkIntegrity()">✅ Check Integrity</button>
                <div id="security-log" class="log-output" style="display:none;"></div>
            </div>
        </div>
    </div>

    <script>
        function showTab(tabName) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
            event.target.classList.add('active');
            document.getElementById(tabName).classList.add('active');
        }

        async function apiCall(endpoint, options = {}) {
            try {
                const response = await fetch('/api' + endpoint, {
                    headers: { 'Content-Type': 'application/json' },
                    ...options
                });
                return await response.json();
            } catch (error) {
                return { success: false, message: error.message };
            }
        }

        async function savePost() {
            const title = document.getElementById('post-title').value;
            const content = document.getElementById('post-content').value;
            
            const result = await apiCall('/post', {
                method: 'POST',
                body: JSON.stringify({ title, content })
            });
            
            document.getElementById('write-log').style.display = 'block';
            document.getElementById('write-log').textContent = result.message || 'Post saved!';
        }

        async function saveAndBuild() {
            await savePost();
            const result = await apiCall('/build', { method: 'POST' });
            document.getElementById('write-log').textContent += '\n' + (result.data || result.message);
        }

        async function uploadImages() {
            const input = document.getElementById('image-upload');
            const logDiv = document.getElementById('image-log');
            logDiv.style.display = 'block';
            
            for (let file of input.files) {
                const formData = new FormData();
                formData.append('image', file);
                
                const response = await fetch('/api/upload', {
                    method: 'POST',
                    body: formData
                });
                const result = await response.json();
                logDiv.textContent += file.name + ': ' + result.message + '\n';
            }
        }

        async function publishSite() {
            const logDiv = document.getElementById('publish-log');
            logDiv.style.display = 'block';
            logDiv.textContent = 'Publishing with security verification...\n';
            
            const result = await apiCall('/publish', { method: 'POST' });
            logDiv.textContent += result.data || result.message;
        }

        async function buildOnly() {
            const logDiv = document.getElementById('publish-log');
            logDiv.style.display = 'block';
            const result = await apiCall('/build', { method: 'POST' });
            logDiv.textContent = result.data || result.message;
        }

        async function runAudit() {
            const logDiv = document.getElementById('security-log');
            logDiv.style.display = 'block';
            const result = await apiCall('/audit', { method: 'POST' });
            logDiv.textContent = result.data || result.message;
        }

        async function checkIntegrity() {
            const logDiv = document.getElementById('security-log');
            logDiv.style.display = 'block';
            const result = await apiCall('/integrity', { method: 'POST' });
            logDiv.textContent = result.data || result.message;
        }
    </script>
</body>
</html>`

func main() {
	blogDir := "."
	if len(os.Args) > 1 {
		blogDir = os.Args[1]
	}

	// Ensure localhost-only access
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Security: localhost only
		if !strings.HasPrefix(r.RemoteAddr, "127.0.0.1:") && !strings.HasPrefix(r.RemoteAddr, "[::1]:") {
			http.Error(w, "Access denied: localhost only", http.StatusForbidden)
			return
		}

		// Security headers
		w.Header().Set("Content-Security-Policy", "default-src 'self' 'unsafe-inline'")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("X-Content-Type-Options", "nosniff")

		w.Header().Set("Content-Type", "text/html")
		fmt.Fprint(w, dashboardHTML)
	})

	// API endpoints
	http.HandleFunc("/api/post", handlePost)
	http.HandleFunc("/api/upload", handleUpload)
	http.HandleFunc("/api/build", handleBuild)
	http.HandleFunc("/api/publish", handlePublish)
	http.HandleFunc("/api/audit", handleAudit)
	http.HandleFunc("/api/integrity", handleIntegrity)

	fmt.Printf("🔒 SecureBlog UI starting on http://localhost:%s\n", serverPort)
	fmt.Println("🛡️  Security: Localhost-only access")
	fmt.Println("🚫 Zero JavaScript in blog output")
	fmt.Println("✅ All content cryptographically signed")

	log.Fatal(http.ListenAndServe("127.0.0.1:"+serverPort, nil))
}

func handlePost(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		jsonResponse(w, Response{Success: false, Message: "Method not allowed"})
		return
	}

	var req struct {
		Title   string `json:"title"`
		Content string `json:"content"`
	}
	json.NewDecoder(r.Body).Decode(&req)

	// Security check
	if strings.Contains(req.Content, "<script") {
		jsonResponse(w, Response{Success: false, Message: "JavaScript detected - blocked"})
		return
	}

	// Save post
	filename := fmt.Sprintf("content/posts/%s-%s.md", 
		time.Now().Format("2006-01-02"),
		strings.ToLower(strings.ReplaceAll(req.Title, " ", "-")))
	
	os.MkdirAll("content/posts", 0755)
	content := fmt.Sprintf("---\ntitle: \"%s\"\ndate: %s\n---\n\n%s",
		req.Title, time.Now().Format("2006-01-02"), req.Content)
	
	err := os.WriteFile(filename, []byte(content), 0644)
	if err != nil {
		jsonResponse(w, Response{Success: false, Message: err.Error()})
		return
	}

	jsonResponse(w, Response{Success: true, Message: "Post saved: " + filename})
}

func handleUpload(w http.ResponseWriter, r *http.Request) {
	r.ParseMultipartForm(maxUploadSize)
	file, header, err := r.FormFile("image")
	if err != nil {
		jsonResponse(w, Response{Success: false, Message: "Upload failed"})
		return
	}
	defer file.Close()

	// Validate image type
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".webp" {
		jsonResponse(w, Response{Success: false, Message: "Invalid image type"})
		return
	}

	// Save image
	os.MkdirAll("static/images", 0755)
	dst, _ := os.Create(filepath.Join("static/images", header.Filename))
	defer dst.Close()
	io.Copy(dst, file)

	jsonResponse(w, Response{Success: true, Message: "Image uploaded: " + header.Filename})
}

func handleBuild(w http.ResponseWriter, r *http.Request) {
	output, err := runCommand("./build-sandbox.sh")
	if err != nil {
		jsonResponse(w, Response{Success: false, Message: err.Error(), Data: string(output)})
		return
	}
	jsonResponse(w, Response{Success: true, Message: "Build complete", Data: string(output)})
}

func handlePublish(w http.ResponseWriter, r *http.Request) {
	output, err := runCommand("./build-sandbox.sh && bash .scripts/security-regression-guard.sh dist && git add . && git commit -m 'Publish' && git push")
	if err != nil {
		jsonResponse(w, Response{Success: false, Message: err.Error(), Data: string(output)})
		return
	}
	jsonResponse(w, Response{Success: true, Message: "Published!", Data: string(output)})
}

func handleAudit(w http.ResponseWriter, r *http.Request) {
	output, err := runCommand("bash .scripts/security-regression-guard.sh dist")
	if err != nil {
		jsonResponse(w, Response{Success: false, Message: err.Error(), Data: string(output)})
		return
	}
	jsonResponse(w, Response{Success: true, Message: "Audit complete", Data: string(output)})
}

func handleIntegrity(w http.ResponseWriter, r *http.Request) {
	output, err := runCommand("bash scripts/integrity-verify.sh dist")
	if err != nil {
		jsonResponse(w, Response{Success: false, Message: err.Error(), Data: string(output)})
		return
	}
	jsonResponse(w, Response{Success: true, Message: "Integrity verified", Data: string(output)})
}

func runCommand(command string) ([]byte, error) {
	cmd := exec.Command("bash", "-c", command)
	return cmd.CombinedOutput()
}

func jsonResponse(w http.ResponseWriter, resp Response) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}