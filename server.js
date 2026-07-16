const express  = require('express');
const http     = require('http');
const { Server } = require('socket.io');
const path     = require('path');

const app    = express();
const server = http.createServer(app);
const io     = new Server(server, { cors: { origin: '*' } });

const MAX_PLAYERS = 30;
const COLORS = [
  '#e74c3c','#3498db','#2ecc71','#f39c12','#9b59b6',
  '#1abc9c','#e67e22','#e91e63','#00bcd4','#8bc34a',
  '#ff5722','#607d8b','#795548','#ff9800','#4caf50',
];

// ─── Spieler-Zustand ────────────────────────────────────────────────────────
// id → { name, color, x, y, z, yaw, hp, isHost }
const players = {};
let hostId = null;

// ─── Statische Dateien (public/ Ordner UND root) ────────────────────────────
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.static(__dirname));

// Fallback: root → game HTML
app.get('/', (req, res) => {
  const candidates = [
    path.join(__dirname, 'public', 'index.html'),
    path.join(__dirname, 'super-shoot.html'),
    path.join(__dirname, 'index.html'),
  ];
  for (const f of candidates) {
    const fs = require('fs');
    if (fs.existsSync(f)) return res.sendFile(f);
  }
  res.status(404).send('Spieldatei nicht gefunden. Lege super-shoot.html in diesen Ordner.');
});

// ─── Geheim-Chat (Schnitzeljagd) ────────────────────────────────────────────
// Zugang nur mit dem geheimen Code. Nachrichten überleben einen Neustart
// (Datei), aber kein Re-Deploy — für die Schnitzeljagd reicht das.
const fs = require('fs');
const CHAT_CODE = 'hallo'; // Vergleich immer kleingeschrieben
const CHAT_FILE = path.join(__dirname, '.geheim-chat.json'); // Punkt-Datei: wird von express.static nicht ausgeliefert
let chatNachrichten = [];
try { chatNachrichten = JSON.parse(fs.readFileSync(CHAT_FILE, 'utf8')); } catch (e) {}

function chatCodeOk(code) {
  return String(code || '').trim().toLowerCase() === CHAT_CODE;
}

app.get('/api/geheim-chat', (req, res) => {
  if (!chatCodeOk(req.query.code)) return res.status(403).json({ fehler: 'Falscher Code!' });
  res.json(chatNachrichten.slice(-8));
});

app.post('/api/geheim-chat', express.json(), (req, res) => {
  const { code, name, text } = req.body || {};
  if (!chatCodeOk(code)) return res.status(403).json({ fehler: 'Falscher Code!' });
  const nachricht = {
    name: String(name || 'Anonym').slice(0, 16).trim() || 'Anonym',
    text: String(text || '').slice(0, 200).trim(),
    zeit: Date.now(),
  };
  if (!nachricht.text) return res.status(400).json({ fehler: 'Leere Nachricht' });
  chatNachrichten.push(nachricht);
  if (chatNachrichten.length > 100) chatNachrichten = chatNachrichten.slice(-100);
  try { fs.writeFileSync(CHAT_FILE, JSON.stringify(chatNachrichten)); } catch (e) {}
  res.json(chatNachrichten.slice(-8));
});

// ─── Helfer: neuen Host vergeben ────────────────────────────────────────────
function assignNewHost() {
  const ids = Object.keys(players);
  if (ids.length === 0) { hostId = null; return; }
  hostId = ids[0];
  players[hostId].isHost = true;
  io.emit('newHost', hostId);
  console.log('Neuer Host:', players[hostId].name, `(${hostId})`);
}

// ─── Socket.io Verbindungen ─────────────────────────────────────────────────
io.on('connection', socket => {
  // Server voll?
  if (Object.keys(players).length >= MAX_PLAYERS) {
    socket.emit('serverFull', `Server ist voll! (max. ${MAX_PLAYERS} Spieler)`);
    socket.disconnect(true);
    return;
  }

  const colorIndex = Object.keys(players).length % COLORS.length;
  const isHost     = Object.keys(players).length === 0;
  if (isHost) hostId = socket.id;

  players[socket.id] = {
    name: 'Spieler', color: COLORS[colorIndex],
    x: 0, y: 1.7, z: 0, yaw: 0, hp: 100, isHost,
  };

  console.log(`+ ${socket.id} verbunden (${Object.keys(players).length}/${MAX_PLAYERS})`);

  // Neuen Spieler willkommen heißen
  socket.emit('welcome', {
    myId:    socket.id,
    isHost,
    players: Object.fromEntries(
      Object.entries(players).map(([id, p]) => [id, { id, ...p }])
    ),
  });

  // Anderen Spielern mitteilen
  socket.broadcast.emit('playerJoined', { id: socket.id, ...players[socket.id] });

  // ── Lobby-Events ──────────────────────────────────────────────────────────
  socket.on('setName', name => {
    if (!players[socket.id]) return;
    players[socket.id].name = String(name).slice(0, 16) || 'Spieler';
    io.emit('playerUpdate', { id: socket.id, name: players[socket.id].name });
  });

  socket.on('worldSeed', seed => {
    socket.broadcast.emit('worldSeed', seed);
  });

  socket.on('goToShop', () => {
    if (socket.id !== hostId) return;
    io.emit('goToShop');
  });

  socket.on('setMode', mode => {
    if (socket.id !== hostId) return;
    socket.broadcast.emit('setMode', mode);
  });

  // ── Spiel-Flow ────────────────────────────────────────────────────────────
  socket.on('gameStart', () => {
    if (socket.id !== hostId) return;
    Object.values(players).forEach(p => { p.hp = 100; });
    socket.broadcast.emit('gameStart');
    console.log('Spiel gestartet (Host:', players[hostId]?.name, ')');
  });

  socket.on('waveStart', data => {
    if (socket.id !== hostId) return;
    socket.broadcast.emit('waveStart', data);
  });

  socket.on('waveEnd', () => {
    if (socket.id !== hostId) return;
    socket.broadcast.emit('waveEnd');
  });

  // ── Bewegung ──────────────────────────────────────────────────────────────
  socket.on('move', data => {
    const p = players[socket.id];
    if (!p) return;
    p.x = data.x; p.y = data.y; p.z = data.z; p.yaw = data.yaw;
  });

  // ── Schüsse ───────────────────────────────────────────────────────────────
  socket.on('shot', data => {
    socket.broadcast.emit('remoteShot', { ...data, id: socket.id });
  });

  // ── Roboter-Sync (Host → Non-Hosts) ──────────────────────────────────────
  socket.on('robotSync', data => {
    if (socket.id !== hostId) return;
    socket.broadcast.emit('robotSync', data);
  });

  socket.on('robotKilled', data => {
    if (socket.id !== hostId) return;
    socket.broadcast.emit('robotKilled', data);
  });

  socket.on('robotBullet', data => {
    if (socket.id !== hostId) return;
    socket.broadcast.emit('robotBullet', data);
  });

  // Non-Host trifft Roboter → an Host weiterleiten
  socket.on('hitRobot', data => {
    if (!hostId || socket.id === hostId) return;
    io.to(hostId).emit('remoteHitRobot', data);
  });

  // ── Spieler-HP ────────────────────────────────────────────────────────────
  socket.on('playerHit', damage => {
    const p = players[socket.id];
    if (!p) return;
    p.hp = Math.max(0, p.hp - damage);
    io.emit('playerHpSync', { id: socket.id, hp: p.hp });
    if (p.hp <= 0) {
      io.emit('playerDied', socket.id);
      console.log(`${p.name} gestorben`);
    }
  });

  socket.on('playerRespawn', () => {
    const p = players[socket.id];
    if (!p) return;
    p.hp = 100;
    io.emit('playerHpSync', { id: socket.id, hp: 100 });
  });

  // ── Trennen ───────────────────────────────────────────────────────────────
  socket.on('disconnect', () => {
    const p = players[socket.id];
    console.log(`- ${p?.name ?? socket.id} getrennt (${Object.keys(players).length - 1}/${MAX_PLAYERS})`);
    delete players[socket.id];
    io.emit('playerLeft', socket.id);

    if (socket.id === hostId) {
      players[hostId] && (players[hostId].isHost = false);
      assignNewHost();
    }
  });
});

// ─── Positions-Tick 20 Hz ───────────────────────────────────────────────────
setInterval(() => {
  const ids = Object.keys(players);
  if (ids.length === 0) return;
  const tick = {};
  for (const [id, p] of Object.entries(players)) {
    tick[id] = { x: p.x, y: p.y, z: p.z, yaw: p.yaw, color: p.color, name: p.name, hp: p.hp };
  }
  io.emit('playersTick', tick);
}, 50);

// ─── Server starten ─────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`\n🔫 SUPER SHOOT Multiplayer-Server`);
  console.log(`   http://localhost:${PORT}`);
  console.log(`   Max. ${MAX_PLAYERS} Spieler\n`);
});
