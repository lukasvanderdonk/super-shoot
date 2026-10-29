// Online-Bestenliste für die Spiele-App.
//
// Ablauf: Die App legt für jedes neue persönliche Bestergebnis ein Issue an
//   Titel:  score: <spiel>/<liste>
//   Inhalt: {"v":1,"game":"solitaer","board":"easy","better":"low","value":312,"uid":"abc123xyz","nick":"MutigerFuchs42"}
// Dieses Skript (läuft in GitHub Actions) liest alle offenen score-Issues von dir selbst, prüft sie,
// trägt sie in scores/<spiel>.json ein und schließt die Issues wieder. Die Seite liefert die Dateien dann
// über GitHub Pages aus: https://lukasvanderdonk.github.io/super-shoot/scores/<spiel>.json
//
// Nur Issues vom Besitzer des Repos zählen (der Schlüssel in der App gehört ihm). Alles wird geprüft,
// damit niemand mit erfundenen Werten die Liste füllen kann.

'use strict';
const fs = require('fs');
const path = require('path');

const GAMES = ['solitaer', 'labyrinth', 'strand', 'leukas', 'room', 'lantern', 'rpg'];
const TOP = 100;                // so viele Plätze pro Liste werden gespeichert
const MAX_BOARDS = 30;          // so viele Listen pro Spiel (Schutz gegen Müll)

// ───────── Prüfen eines Eintrags ─────────
// Liefert { game, board, better, value, uid, nick } oder null.
function parseIssue(issue) {
  if (!issue || typeof issue.title !== 'string' || !issue.title.startsWith('score:')) return null;
  let d;
  try { d = JSON.parse(String(issue.body || '').trim()); } catch (e) { return null; }
  if (!d || typeof d !== 'object' || d.v !== 1) return null;
  const game = String(d.game), board = String(d.board);
  if (!GAMES.includes(game)) return null;
  if (!/^[a-z0-9_-]{1,24}$/.test(board)) return null;
  if (d.better !== 'low' && d.better !== 'high') return null;
  let value = d.value;
  if (typeof value !== 'number' || !isFinite(value)) return null;
  value = Math.round(value * 100) / 100;
  if (!(value > 0) || value >= 1e9) return null;
  if (d.better === 'low' && value < 5) return null;                 // Zeiten unter 5 Sekunden gibt es nicht
  if (typeof d.uid !== 'string' || !/^[a-z0-9]{6,20}$/.test(d.uid)) return null;
  const nick = typeof d.nick === 'string' ? d.nick.trim() : '';
  if (!/^[\p{L}\p{N} _-]{2,24}$/u.test(nick)) return null;
  return { game, board, better: d.better, value, uid: d.uid, nick };
}

// ───────── Eintragen ─────────
function emptyFile() { return { v: 1, updated: '', boards: {} }; }

// file = Inhalt von scores/<spiel>.json, e = geprüfter Eintrag, date = 'YYYY-MM-DD'. Liefert true, wenn sich etwas geändert hat.
function applyEntry(file, e, date) {
  if (!file.boards[e.board]) {
    if (Object.keys(file.boards).length >= MAX_BOARDS) return false;
    file.boards[e.board] = { better: e.better, top: [] };
  }
  const b = file.boards[e.board];
  if (b.better !== e.better) return false;                           // Richtung einer Liste steht ab dem ersten Eintrag fest
  const better = (x, y) => (b.better === 'low' ? x < y : x > y);
  const mine = b.top.find(t => t.u === e.uid);
  if (mine) {
    if (!better(e.value, mine.v)) return false;                      // nur echte Verbesserungen
    mine.v = e.value; mine.n = e.nick; mine.t = date;
  } else {
    b.top.push({ u: e.uid, n: e.nick, v: e.value, t: date });
  }
  b.top.sort((x, y) => (x.v === y.v ? (x.t < y.t ? -1 : x.t > y.t ? 1 : 0) : better(x.v, y.v) ? -1 : 1));
  b.top = b.top.slice(0, TOP);
  return true;
}

// ───────── Ein/Aus ─────────
async function main() {
  const API = process.env.GH_API || 'https://api.github.com';
  const repo = process.env.REPO, owner = process.env.OWNER, token = process.env.GITHUB_TOKEN;
  const dir = process.env.SCORES_DIR || path.join(process.cwd(), 'scores');
  if (!repo || !owner || !token) throw new Error('REPO, OWNER und GITHUB_TOKEN fehlen');

  async function gh(method, url, body) {
    const res = await fetch(API + url, {
      method,
      headers: { Authorization: 'Bearer ' + token, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json', 'User-Agent': 'scores-action' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) throw new Error(method + ' ' + url + ' -> ' + res.status + ' ' + (await res.text()).slice(0, 200));
    return res.status === 204 ? null : res.json();
  }

  // alle offenen Issues des Besitzers (Pull Requests tauchen hier auch auf und werden übersprungen)
  const issues = [];
  for (let page = 1; page <= 10; page++) {
    const part = await gh('GET', `/repos/${repo}/issues?state=open&creator=${encodeURIComponent(owner)}&per_page=100&page=${page}`);
    issues.push(...part.filter(i => !i.pull_request && typeof i.title === 'string' && i.title.startsWith('score:')));
    if (part.length < 100) break;
  }
  issues.sort((a, b) => a.number - b.number);                        // in der Reihenfolge, in der sie gekommen sind
  console.log('Offene score-Issues:', issues.length);

  fs.mkdirSync(dir, { recursive: true });
  const files = {}, changed = new Set();
  function load(game) {
    if (!files[game]) {
      try { files[game] = JSON.parse(fs.readFileSync(path.join(dir, game + '.json'), 'utf8')); } catch (e) { files[game] = emptyFile(); }
      if (!files[game].boards) files[game].boards = {};
    }
    return files[game];
  }

  let accepted = 0, rejected = 0;
  for (const issue of issues) {
    const e = parseIssue(issue);
    if (e) {
      const date = String(issue.created_at || new Date().toISOString()).slice(0, 10);
      if (applyEntry(load(e.game), e, date)) { changed.add(e.game); accepted++; }
    } else {
      rejected++;
      console.log('Abgelehnt: Issue #' + issue.number);
    }
    await gh('PATCH', `/repos/${repo}/issues/${issue.number}`, { state: 'closed', state_reason: e ? 'completed' : 'not_planned' });
  }

  const now = new Date().toISOString();
  for (const game of changed) {
    files[game].updated = now;
    fs.writeFileSync(path.join(dir, game + '.json'), JSON.stringify(files[game]) + '\n');
  }
  console.log(`Fertig: ${accepted} eingetragen, ${rejected} abgelehnt, Dateien geändert: ${[...changed].join(', ') || '-'}`);
}

module.exports = { parseIssue, applyEntry, emptyFile, GAMES };
if (require.main === module) main().catch(err => { console.error(err); process.exit(1); });
