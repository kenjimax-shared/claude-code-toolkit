const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const PORT = 9199;

// Generate a random topic at ntfy.sh or use your self-hosted instance
const NTFY_TOPIC = process.env.NTFY_TOPIC || 'YOUR_NTFY_TOPIC_HERE';

const soundFile = path.join(__dirname, 'notify-sound.mp3');
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const countFile = path.join(__dirname, '.notify-count');
let notifyCount = 0;
try { notifyCount = parseInt(fs.readFileSync(countFile, 'utf8'), 10) || 0; } catch(e) {}
let pollClients = {}; // track recent poll clients: ua -> { lastPoll, idleSecs, source }

const IDLE_THRESHOLD = 300; // 5 minutes in seconds

// --- Send ntfy notification (fire-and-forget, throttled) ---
// Sends ntfy UNLESS user is actively at their desktop (code-server polling + not idle).
// Mobile pollers (tmux-mobile) do NOT suppress ntfy: the phone should still get
// push notifications even if tmux-mobile is open, since the screen may be off.
let lastNtfy = 0;
function sendNtfy() {
  const now = Date.now();
  if (now - lastNtfy < 5000) return;
  lastNtfy = now;

  // Only DESKTOP pollers suppress ntfy (not mobile ones)
  const hasActiveDesktop = Object.values(pollClients).some(
    c => (now - c.lastPoll < 10000) && c.idleSecs < IDLE_THRESHOLD && c.source !== 'mobile'
  );

  if (hasActiveDesktop) {
    console.log('[NTFY] Skipping (user active at desktop)');
    return;
  }

  const hasDesktopPoller = Object.values(pollClients).some(c => now - c.lastPoll < 10000 && c.source !== 'mobile');
  const reason = hasDesktopPoller ? 'desktop idle ' + Math.max(...Object.values(pollClients).filter(c => c.source !== 'mobile').map(c => c.idleSecs)) + 's' : 'no desktop browser';
  console.log('[NTFY] Sending priority 4 (' + reason + ')');
  const data = JSON.stringify({
    topic: NTFY_TOPIC,
    title: 'Claude Code',
    message: 'Waiting for your input',
    priority: 4
  });
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
  } else if (req.url === '/img') {
    res.writeHead(200, { ...cors, 'Content-Type': 'text/html', 'Cache-Control': 'no-store' });
    res.end(UPLOAD_HTML);
  } else if (req.url === '/upload' && req.method === 'POST') {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      const buf = Buffer.concat(chunks);
      const ext = (req.headers['content-type'] || '').includes('png') ? '.png' :
                  (req.headers['content-type'] || '').includes('jpeg') ? '.jpg' :
                  (req.headers['content-type'] || '').includes('webp') ? '.webp' : '.png';
      const name = 'img-' + Date.now() + ext;
      const filepath = path.join(uploadDir, name);
      fs.writeFileSync(filepath, buf);
      res.writeHead(200, { ...cors, 'Content-Type': 'text/plain' });
      res.end(filepath);
    });
  } else if (req.url === '/sound2.mp3') {
    try {
      const stat = fs.statSync(soundFile);
      res.writeHead(200, {
        ...cors,
        'Content-Type': 'audio/mpeg',
        'Content-Length': stat.size,
        'Cache-Control': 'no-store'
      });
      fs.createReadStream(soundFile).pipe(res);
    } catch {
      res.writeHead(404, cors); res.end();
    }
  } else if (req.url && req.url.startsWith('/poll')) {
    const ua = (req.headers['user-agent'] || 'unknown').substring(0, 80);
    const urlObj = new URL(req.url, 'http://localhost');
    const idleSecs = parseInt(urlObj.searchParams.get('idle') || '0', 10) || 0;
    const source = urlObj.searchParams.get('source') || 'desktop';
    pollClients[ua] = { lastPoll: Date.now(), idleSecs, source };
    const now2 = Date.now();
    const activeDesktop = Object.values(pollClients).some(
      c => (now2 - c.lastPoll < 10000) && c.idleSecs < IDLE_THRESHOLD && c.source !== 'mobile'
    );
    res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ count: notifyCount, activeDesktop }));
  } else if (req.url === '/debug') {
    const now = Date.now();
    const active = Object.entries(pollClients)
      .filter(([_, c]) => now - c.lastPoll < 10000)
      .map(([ua, c]) => ({ ua, pollAgo: Math.round((now - c.lastPoll) / 1000) + 's', idle: c.idleSecs + 's' }));
    res.writeHead(200, { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ notifyCount, idleThreshold: IDLE_THRESHOLD + 's', activePollers: active }, null, 2));
  } else if (req.url && req.url.startsWith('/notify')) {
    notifyCount++;
    fs.writeFile(countFile, String(notifyCount), function(){});
    sendNtfy();
    res.writeHead(200, cors); res.end('ok');
  } else {
    res.writeHead(404, cors); res.end();
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Notification server on port ' + PORT);
});
