const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const PORT = 9199;
const NTFY_TOPIC = 'your-ntfy-topic-here'; // Replace with your ntfy.sh topic

const soundFile = path.join(__dirname, 'notify-sound.mp3');
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const countFile = path.join(__dirname, '.notify-count');
const browserPlayFile = path.join(__dirname, '.browser-play-count');
const snoozeFile = path.join(__dirname, '.snooze-pending');
let notifyCount = 0;
try { notifyCount = parseInt(fs.readFileSync(countFile, 'utf8'), 10) || 0; } catch(e) {}
let browserPlayCount = 0;
try { browserPlayCount = parseInt(fs.readFileSync(browserPlayFile, 'utf8'), 10) || 0; } catch(e) {}
let pollClients = {}; // track recent poll clients: ua -> { lastPoll, idleSecs, source }

const MOBILE_IDLE_THRESHOLD = 20; // 20 seconds (phone screen likely off)
const POLL_STALE_MS = 90000; // 90 seconds - survives browser background-tab throttling

// --- Send ntfy notification (fire-and-forget, per-session throttled) ---
// Called by the cascade logic in /notify handler only when neither desktop
// nor laptop can handle the notification. Per-session throttle prevents
// duplicates from idle_prompt + Stop debounce (20s apart) while allowing
// legitimate notifications from different sessions.
const ntfyThrottles = {}; // sessionName -> lastSendTime
const NTFY_THROTTLE_MS = 30000; // 30 seconds per session
function sendNtfy(sessionName) {
  const now = Date.now();
  const key = sessionName || '__global__';
  if (now - (ntfyThrottles[key] || 0) < NTFY_THROTTLE_MS) return;
  ntfyThrottles[key] = now;
  // Clean old entries every 50 calls
  if (Object.keys(ntfyThrottles).length > 50) {
    for (const k of Object.keys(ntfyThrottles)) {
      if (now - ntfyThrottles[k] > 120000) delete ntfyThrottles[k];
    }
  }

  console.log('[NTFY] Sending priority 4 (session: ' + (sessionName || 'unknown') + ')');
  const payload = {
    topic: NTFY_TOPIC,
    title: 'Claude Code' + (sessionName ? ' :: ' + sessionName : ''),
    message: 'Waiting for your input',
    priority: 4
  };
  if (sessionName) {
    // Replace with your actual remote access URL (e.g., Tailscale, Cloudflare Tunnel, etc.)
    payload.click = 'https://YOUR_REMOTE_HOST:8443?session=' + encodeURIComponent(sessionName);
  }
  const data = JSON.stringify(payload);
  const req = https.request('https://ntfy.sh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
  }, (res) => {
    if (res.statusCode !== 200) console.log('[NTFY] Status:', res.statusCode);
  });
  req.on('error', (e) => console.log('[NTFY] Error:', e.message));
  req.write(data);
  req.end();
}

const UPLOAD_HTML = `<!DOCTYPE html>
<html><head><title>Claude Upload</title></head>
<body style="background:#1a1a1a;color:#ccc;font-family:monospace;padding:20px;text-align:center">
<h2>Paste or Drop Image</h2>
<div id="drop" style="border:2px dashed #555;padding:60px 20px;margin:20px auto;max-width:600px;border-radius:8px;cursor:pointer">
  Paste (Ctrl+V) or drag an image here
</div>
<p id="status"></p>
<script>
const drop = document.getElementById('drop');
const status = document.getElementById('status');

document.addEventListener('paste', (e) => {
  const items = e.clipboardData.items;
  for (let i = 0; i < items.length; i++) {
    if (items[i].type.startsWith('image/')) {
      upload(items[i].getAsFile());
      return;
    }
  }
  status.textContent = 'No image found in clipboard';
});

drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.style.borderColor = '#4a9'; });
drop.addEventListener('dragleave', () => { drop.style.borderColor = '#555'; });
drop.addEventListener('drop', (e) => {
  e.preventDefault();
  drop.style.borderColor = '#555';
  if (e.dataTransfer.files.length) upload(e.dataTransfer.files[0]);
});

function upload(file) {
  status.textContent = 'Uploading...';
  const reader = new FileReader();
  reader.onload = () => {
    fetch('/upload', {
      method: 'POST',
      headers: { 'Content-Type': file.type, 'X-Filename': file.name || 'screenshot.png' },
      body: reader.result
    }).then(r => r.text()).then(p => {
      status.innerHTML = 'Saved: <code>' + p + '</code><br>Tell Claude: <code>look at ' + p + '</code>';
    }).catch(e => { status.textContent = 'Error: ' + e; });
  };
  reader.readAsArrayBuffer(file);
}
</script>
</body></html>`;

const NOTIFY_HTML = `<!DOCTYPE html>
<html><head><title>Claude Notification</title></head>
<body style="background:#1a1a1a;color:#aaa;font-family:monospace;padding:20px;text-align:center">
<h2>Claude Code Notifications</h2>
<button id="btn" style="font-size:24px;padding:20px 40px;cursor:pointer;background:#4a9;color:#fff;border:none;border-radius:8px">Click to Enable Audio</button>
<p id="status" style="margin-top:20px"></p>
<script>
var enabled = false;
document.getElementById('btn').addEventListener('click', function() {
  var a = new Audio('/sound2.mp3');
  a.play().then(function() {
    enabled = true;
    document.getElementById('btn').style.display = 'none';
    document.getElementById('status').textContent = 'Listening for notifications...';
    startPolling();
  });
});

function startPolling() {
  var lastCount = -1;
  setInterval(function() {
    fetch('/poll').then(function(r) { return r.json(); }).then(function(d) {
      if (lastCount === -1) { lastCount = d.count; return; }
      if (d.count > lastCount) {
        lastCount = d.count;
        document.getElementById('status').textContent = 'Notification at ' + new Date().toLocaleTimeString();
        new Audio('/sound2.mp3').play();
      }
    }).catch(function() {});
  }, 800);
}
</script>
</body></html>`;

const server = http.createServer((req, res) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, X-Filename'
  };

  if (req.method === 'OPTIONS') {
    res.writeHead(200, cors);
    res.end();
    return;
  }

  if (req.url === '/') {
    res.writeHead(200, { ...cors, 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    res.end(NOTIFY_HTML);
  } else if (req.url && req.url.startsWith('/img/') && req.method === 'GET') {
    // Static file serving for uploaded images
    const filename = decodeURIComponent(req.url.slice(5));
    if (filename.includes('..') || filename.includes('/')) {
      res.writeHead(400, cors); res.end('Bad request');
      return;
    }
    const filepath = path.join(uploadDir, filename);
    const extMap = { '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif' };
    const ext = path.extname(filename).toLowerCase();
    const contentType = extMap[ext] || 'application/octet-stream';
    try {
      const stat = fs.statSync(filepath);
      res.writeHead(200, { ...cors, 'Content-Type': contentType, 'Content-Length': stat.size, 'Cache-Control': 'public, max-age=3600' });
      fs.createReadStream(filepath).pipe(res);
    } catch(e) {
      res.writeHead(404, cors); res.end('Not found');
    }
  } else if (req.url === '/img') {
    res.writeHead(200, { ...cors, 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    res.end(UPLOAD_HTML);
  } else if (req.url === '/upload' && req.method === 'POST') {
    const MAX_UPLOAD = 10 * 1024 * 1024; // 10 MB
    const chunks = [];
    let size = 0;
    req.on('data', c => {
      size += c.length;
      if (size > MAX_UPLOAD) { req.destroy(); res.writeHead(413, cors); res.end('Too large'); return; }
      chunks.push(c);
    });
    req.on('end', () => {
      if (res.writableEnded) return;
      const buf = Buffer.concat(chunks);
      const ext = (req.headers['content-type'] || '').includes('png') ? '.png' :
                  (req.headers['content-type'] || '').includes('jpeg') ? '.jpg' :
                  (req.headers['content-type'] || '').includes('webp') ? '.webp' : '.png';
      const name = 'img-' + Date.now() + ext;
      const filepath = path.join(uploadDir, name);
      fs.writeFileSync(filepath, buf);
      res.writeHead(200, { ...cors, 'Content-Type': 'text/plain' });
      res.end('/img/' + name);
    });
  } else if (req.url === '/sound2.mp3') {
    const stat = fs.statSync(soundFile);
    res.writeHead(200, {
      ...cors,
      'Content-Type': 'audio/mpeg',
      'Content-Length': stat.size,
      'Cache-Control': 'no-store'
    });
    fs.createReadStream(soundFile).pipe(res);
  } else if (req.url && req.url.startsWith('/poll')) {
    const ua = (req.headers['user-agent'] || 'unknown').substring(0, 80);
    const urlObj = new URL(req.url, 'http://localhost');
    const idleSecs = parseInt(urlObj.searchParams.get('idle') || '0', 10) || 0;
    const source = urlObj.searchParams.get('source') || 'desktop';
    const session = urlObj.searchParams.get('session') || '';
    pollClients[ua] = { lastPoll: Date.now(), idleSecs, source, session };
    const now2 = Date.now();
    const activeDesktop = Object.values(pollClients).some(
      c => (now2 - c.lastPoll < POLL_STALE_MS) && c.source !== 'mobile'
    );
    res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ count: notifyCount, browserPlayCount, activeDesktop }));
  } else if (req.url === '/debug') {
    const now = Date.now();
    const active = Object.entries(pollClients)
      .filter(([_, c]) => now - c.lastPoll < POLL_STALE_MS)
      .map(([ua, c]) => ({ ua, pollAgo: Math.round((now - c.lastPoll) / 1000) + 's', idle: c.idleSecs + 's', source: c.source || 'desktop', session: c.session || '' }));
    res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ notifyCount, browserPlayCount, activePollers: active }, null, 2));
  } else if (req.url && req.url.startsWith('/log?')) {
    const msg = decodeURIComponent(req.url.replace('/log?', ''));
    const ua = (req.headers['user-agent'] || '').substring(0, 60);
    console.log('[CLIENT] ' + ua + ' :: ' + msg);
    res.writeHead(200, cors); res.end('ok');
  } else if (req.url === '/snooze' && req.method === 'POST') {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString();
      fs.writeFileSync(snoozeFile, body);
      console.log('[SNOOZE] Queued:', body.substring(0, 100));
      res.writeHead(200, cors); res.end('ok');
    });
  } else if (req.url === '/snooze' && req.method === 'GET') {
    try {
      const data = fs.readFileSync(snoozeFile, 'utf8');
      fs.unlinkSync(snoozeFile);
      console.log('[SNOOZE] Delivered and cleared');
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(data);
    } catch(e) {
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end('null');
    }
  } else if (req.url === '/lucy/event' && req.method === 'POST') {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      try {
        const event = JSON.parse(Buffer.concat(chunks).toString());
        const type = event.type || 'unknown';
        const taskId = event.task_id || '';
        const message = event.message || '';
        console.log('[LUCY] ' + type + ' ' + taskId + ': ' + message);

        // Sub-agent events are logged but do NOT trigger user notifications.
        // Only the Lucy orchestrator (lucy-orch-*) notifies the user via the
        // normal stop hook when it has something to report.
        res.writeHead(200, cors); res.end('ok');
      } catch(e) {
        console.log('[LUCY] Parse error:', e.message);
        res.writeHead(400, cors); res.end('bad request');
      }
    });
  } else if (req.url === '/lucy/status' && req.method === 'GET') {
    // Quick status endpoint: read tasks.json
    try {
      const tasksPath = path.join(process.env.HOME || '', '.claude', 'lucy', 'tasks.json');
      const tasks = JSON.parse(fs.readFileSync(tasksPath, 'utf8'));
      const summary = tasks.map(t => ({ id: t.id, status: t.status, pr: t.pr }));
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify(summary, null, 2));
    } catch(e) {
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end('[]');
    }
  } else if (req.url && req.url.startsWith('/notify')) {
    notifyCount++;
    fs.writeFile(countFile, String(notifyCount), function(){});
    const notifyUrl = new URL(req.url, 'http://localhost');
    const sessionName = notifyUrl.searchParams.get('session') || '';
    const playedLocal = notifyUrl.searchParams.get('played') === 'local';

    if (playedLocal) {
      // Desktop PowerShell handled audio. No browser play, no ntfy.
      console.log('[NOTIFY] Desktop handled (PowerShell), session: ' + (sessionName || 'unknown'));
    } else {
      // Cascade: check for active laptop browser, else ntfy to phone
      const now = Date.now();
      const hasLaptop = Object.values(pollClients).some(
        c => (now - c.lastPoll < POLL_STALE_MS) && c.source === 'laptop'
      );
      if (hasLaptop) {
        browserPlayCount++;
        fs.writeFile(browserPlayFile, String(browserPlayCount), function(){});
        console.log('[NOTIFY] Laptop browser active, browserPlayCount=' + browserPlayCount);
      } else {
        console.log('[NOTIFY] No desktop or laptop, sending ntfy');
        sendNtfy(sessionName);
      }
    }
    res.writeHead(200, cors); res.end('ok');
  } else {
    res.writeHead(404, cors); res.end();
  }
});

const BIND_HOST = process.env.NOTIFY_BIND_HOST || '127.0.0.1';
server.listen(PORT, BIND_HOST, () => {
  console.log('Notification server on ' + BIND_HOST + ':' + PORT);
});
