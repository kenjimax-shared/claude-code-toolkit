#!/usr/bin/env python3
"""Manual OAuth flow for workspace-mcp credentials.
Usage: python3 oauth_auth.py [email]
Opens Chrome auth link, captures callback, saves tokens to credentials dir.
Must open the link in Chrome (not Brave)."""
import json
import hashlib
import base64
import secrets
import sys
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlencode, urlparse, parse_qs
import urllib.request
from datetime import datetime, timezone, timedelta

CLIENT_ID = "YOUR_CLIENT_ID.apps.googleusercontent.com"
CLIENT_SECRET = "YOUR_CLIENT_SECRET"
REDIRECT_URI = "http://localhost:8000/oauth2callback"
TOKEN_URI = "https://oauth2.googleapis.com/token"
CREDS_DIR = os.path.expanduser("~/.google_workspace_mcp/credentials")
SCOPES = [
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/docs",
    "https://www.googleapis.com/auth/documents",
    "https://www.googleapis.com/auth/documents.readonly",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/spreadsheets.readonly",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.compose",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.labels",
    "https://www.googleapis.com/auth/gmail.settings.basic",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/tasks.readonly",
    "https://www.googleapis.com/auth/contacts",
    "https://www.googleapis.com/auth/contacts.readonly",
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/presentations.readonly",
    "https://www.googleapis.com/auth/forms.body",
    "https://www.googleapis.com/auth/forms.body.readonly",
    "https://www.googleapis.com/auth/forms.responses.readonly",
    "https://www.googleapis.com/auth/chat.spaces",
    "https://www.googleapis.com/auth/chat.spaces.readonly",
    "https://www.googleapis.com/auth/chat.messages",
    "https://www.googleapis.com/auth/chat.messages.readonly",
    "https://www.googleapis.com/auth/script.projects",
    "https://www.googleapis.com/auth/script.projects.readonly",
    "https://www.googleapis.com/auth/script.deployments",
    "https://www.googleapis.com/auth/script.deployments.readonly",
    "https://www.googleapis.com/auth/script.processes",
    "https://www.googleapis.com/auth/script.metrics",
    "https://www.googleapis.com/auth/cse",
    "https://www.googleapis.com/auth/webmasters",
    "https://www.googleapis.com/auth/tagmanager.edit.containers",
    "https://www.googleapis.com/auth/tagmanager.publish",
]

email = sys.argv[1] if len(sys.argv) > 1 else "user@agency.example.com"

code_verifier = secrets.token_urlsafe(64)
code_challenge = base64.urlsafe_b64encode(
    hashlib.sha256(code_verifier.encode()).digest()
).decode().rstrip("=")

auth_state = secrets.token_hex(16)
auth_code = None

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global auth_code
        parsed = urlparse(self.path)
        if parsed.path == "/oauth2callback":
            params = parse_qs(parsed.query)
            state = params.get("state", [None])[0]
            if state != auth_state:
                self.send_response(400)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(f"State mismatch! Expected {auth_state}, got {state}".encode())
                return
            auth_code = params.get("code", [None])[0]
            if auth_code:
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(f"<h1>Authorization successful for {email}!</h1><p>You can close this window.</p>".encode())
            else:
                error = params.get("error", ["unknown"])[0]
                self.send_response(400)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(f"<h1>Error: {error}</h1>".encode())
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        pass

auth_params = {
    "response_type": "code",
    "client_id": CLIENT_ID,
    "redirect_uri": REDIRECT_URI,
    "scope": " ".join(SCOPES),
    "state": auth_state,
    "code_challenge": code_challenge,
    "code_challenge_method": "S256",
    "access_type": "offline",
    "prompt": "select_account consent",
    "login_hint": email,
}
auth_url = f"https://accounts.google.com/o/oauth2/auth?{urlencode(auth_params)}"
print(f"AUTH_URL={auth_url}")
sys.stdout.flush()

server = HTTPServer(("127.0.0.1", 8000), Handler)
server.timeout = 180
while auth_code is None:
    server.handle_request()
server.server_close()

# Exchange code for tokens
token_data = urlencode({
    "code": auth_code,
    "client_id": CLIENT_ID,
    "client_secret": CLIENT_SECRET,
    "redirect_uri": REDIRECT_URI,
    "grant_type": "authorization_code",
    "code_verifier": code_verifier,
}).encode()

req = urllib.request.Request(
    "https://oauth2.googleapis.com/token",
    data=token_data,
    headers={"Content-Type": "application/x-www-form-urlencoded"},
)
with urllib.request.urlopen(req) as resp:
    tokens = json.loads(resp.read())

# Verify the token belongs to the expected email
userinfo_req = urllib.request.Request(
    "https://www.googleapis.com/oauth2/v3/userinfo",
    headers={"Authorization": f"Bearer {tokens['access_token']}"},
)
with urllib.request.urlopen(userinfo_req) as resp:
    userinfo = json.loads(resp.read())
actual_email = userinfo.get("email", "")
if actual_email.lower() != email.lower():
    print(f"ERROR: Expected {email} but authenticated as {actual_email}. Token NOT saved.")
    print(f"Please re-run and select the correct Google account.")
    sys.exit(1)
print(f"Verified: token belongs to {actual_email}")

# Save in workspace-mcp credential format
os.makedirs(CREDS_DIR, exist_ok=True)
expiry = datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(seconds=tokens.get("expires_in", 3600))
creds_data = {
    "token": tokens["access_token"],
    "refresh_token": tokens["refresh_token"],
    "token_uri": TOKEN_URI,
    "client_id": CLIENT_ID,
    "client_secret": CLIENT_SECRET,
    "scopes": tokens.get("scope", "").split(" "),
    "expiry": expiry.isoformat(),
}
out_path = os.path.join(CREDS_DIR, f"{email}.json")
with open(out_path, "w") as f:
    json.dump(creds_data, f, indent=2)

print(f"SAVED={out_path}")
sys.stdout.flush()
