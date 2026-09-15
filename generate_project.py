"""
generate_project.py
--------------------
Generates the full web-game project (Zombie Survival, pixel-art style)
that will later be wrapped into an Android app via Capacitor in the
GitHub Actions build workflow (build.yml).

Run this file (python generate_project.py) inside the repo root.
It writes:
  - package.json
  - capacitor.config.json
  - www/index.html
  - www/style.css
  - www/game.js
"""

import os

INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
<title>Zombie Survival</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<canvas id="game"></canvas>

<div id="hud">
  <div id="health-bar"><div id="health-fill"></div></div>
  <div id="wave-label">Score: 0</div>
</div>

<button id="weapon-switch">Switch Weapon</button>
<button id="jump-btn" style="display:none;">JUMP!</button>

<div id="gameover" style="display:none;">
  <h1>GAME OVER</h1>
  <p id="final-score"></p>
  <button id="restart-btn">Restart</button>
</div>

<script src="game.js"></script>
</body>
</html>
"""

STYLE_CSS = """html, body {
  margin: 0; padding: 0; overflow: hidden;
  background: #000;
  font-family: 'Courier New', monospace;
  touch-action: none;
  -webkit-user-select: none;
  user-select: none;
}
canvas {
  display: block;
  background: #0a0a0d;
}
#hud {
  position: fixed; top: 10px; left: 10px; right: 10px;
  display: flex; justify-content: space-between; align-items: center;
  color: #eee; pointer-events: none; z-index: 5;
  font-size: 14px;
}
#health-bar {
  width: 140px; height: 14px; background: rgba(0,0,0,0.5);
  border: 1px solid #700; border-radius: 3px; overflow: hidden;
}
#health-fill {
  height: 100%; width: 100%;
  background: linear-gradient(90deg,#c0392b,#e74c3c);
  transition: width 0.15s;
}
#weapon-switch {
  position: fixed; bottom: 24px; right: 20px;
  padding: 12px 18px; border-radius: 8px; border: none;
  background: rgba(255,255,255,0.15); color: #fff; font-weight: bold;
  z-index: 6;
}
#jump-btn {
  position: fixed; bottom: 24px; left: 20px;
  padding: 16px 26px; border-radius: 8px; border: none;
  background: #e74c3c; color: #fff; font-weight: bold; font-size: 18px;
  z-index: 6; animation: pulse 0.6s infinite alternate;
}
@keyframes pulse {
  from { transform: scale(1); }
  to { transform: scale(1.08); }
}
#gameover {
  position: fixed; inset: 0; background: rgba(0,0,0,0.88);
  color: #fff; display: flex; flex-direction: column;
  align-items: center; justify-content: center; z-index: 10;
}
#gameover h1 { color: #e74c3c; letter-spacing: 4px; }
#restart-btn {
  margin-top: 16px; padding: 12px 24px; border-radius: 8px; border: none;
  background: #e74c3c; color: #fff; font-weight: bold;
}
"""

GAME_JS = """// Zombie Survival - Core Game Engine (MVP)
// Pixel-art style rendering via Canvas 2D - no external image assets.

const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
}
window.addEventListener('resize', resize);
resize();

// ---------- Game State ----------
const state = {
  running: true,
  startTime: performance.now(),
  lastSpawn: 0,
  scrollOffset: 0,
  score: 0,
};

const player = {
  x: 0, y: 0,
  radius: 14,
  health: 100,
  maxHealth: 100,
  weapon: 'pistol',
  lastFire: 0,
};

function placePlayer() {
  player.x = canvas.width / 2;
  player.y = canvas.height * 0.75;
}
window.addEventListener('resize', placePlayer);
placePlayer();

const bullets = [];
const zombies = [];
const particles = [];

// ---------- Weapons ----------
const WEAPONS = {
  pistol:  { fireRate: 260, bulletSpeed: 9, damage: 34, spread: [0] },
  shotgun: { fireRate: 650, bulletSpeed: 8, damage: 20, spread: [-0.28, -0.09, 0.09, 0.28] },
};

let aiming = false;
let aimX = 0, aimY = 0;

function screenToAngle(tx, ty) {
  return Math.atan2(ty - player.y, tx - player.x);
}

function fireWeapon(now) {
  const w = WEAPONS[player.weapon];
  if (now - player.lastFire < w.fireRate) return;
  player.lastFire = now;
  const baseAngle = screenToAngle(aimX, aimY);
  w.spread.forEach(offset => {
    const angle = baseAngle + offset;
    bullets.push({
      x: player.x, y: player.y - 18,
      vx: Math.cos(angle) * w.bulletSpeed,
      vy: Math.sin(angle) * w.bulletSpeed,
      damage: w.damage,
      life: 90,
    });
  });
}

// ---------- Input ----------
function pointerDown(x, y) { aiming = true; aimX = x; aimY = y; }
function pointerMove(x, y) { if (aiming) { aimX = x; aimY = y; } }
function pointerUp() { aiming = false; }

canvas.addEventListener('touchstart', e => {
  const t = e.touches[0];
  pointerDown(t.clientX, t.clientY);
  e.preventDefault();
}, { passive: false });

canvas.addEventListener('touchmove', e => {
  const t = e.touches[0];
  pointerMove(t.clientX, t.clientY);
  e.preventDefault();
}, { passive: false });

canvas.addEventListener('touchend', () => pointerUp(), { passive: false });

// Mouse fallback for desktop testing
canvas.addEventListener('mousedown', e => pointerDown(e.clientX, e.clientY));
canvas.addEventListener('mousemove', e => pointerMove(e.clientX, e.clientY));
window.addEventListener('mouseup', pointerUp);

document.getElementById('weapon-switch').addEventListener('click', () => {
  player.weapon = player.weapon === 'pistol' ? 'shotgun' : 'pistol';
});

// ---------- Zombies ----------
function spawnZombie() {
  const side = Math.random();
  let x, y;
  if (side < 0.5) { x = Math.random() * canvas.width; y = -30; }
  else { x = Math.random() < 0.5 ? -30 : canvas.width + 30; y = Math.random() * canvas.height * 0.6; }

  const elapsedMin = (performance.now() - state.startTime) / 60000;
  const speedBonus = Math.min(elapsedMin * 0.15, 1.2);
  const hpBonus = Math.min(elapsedMin * 8, 60);

  zombies.push({
    x, y,
    speed: 0.6 + Math.random() * 0.4 + speedBonus,
    hp: 40 + hpBonus,
    maxHp: 40 + hpBonus,
    hitFlash: 0,
  });
}

function updateZombies(dt) {
  zombies.forEach(z => {
    const dx = player.x - z.x, dy = player.y - z.y;
    const dist = Math.hypot(dx, dy) || 1;
    z.x += (dx / dist) * z.speed * dt;
    z.y += (dy / dist) * z.speed * dt;
    if (z.hitFlash > 0) z.hitFlash -= dt;

    if (dist < player.radius + 14) {
      player.health -= 0.35 * dt;
      z.x -= (dx / dist) * 3;
      z.y -= (dy / dist) * 3;
    }
  });
}

// ---------- Obstacles (appear behind the retreating player) ----------
const obstacle = {
  active: false,
  warning: false,
  timer: 0,
  nextIn: 12000 + Math.random() * 6000,
};

document.getElementById('jump-btn').addEventListener('click', () => {
  if (obstacle.active) {
    obstacle.active = false;
    document.getElementById('jump-btn').style.display = 'none';
  }
});

function updateObstacle(dt) {
  if (!obstacle.active && !obstacle.warning) {
    obstacle.timer += dt * 16.6;
    if (obstacle.timer > obstacle.nextIn) {
      obstacle.warning = true;
      obstacle.timer = 0;
    }
  } else if (obstacle.warning) {
    obstacle.timer += dt * 16.6;
    if (obstacle.timer > 1400) {
      obstacle.warning = false;
      obstacle.active = true;
      obstacle.timer = 0;
      document.getElementById('jump-btn').style.display = 'block';
    }
  } else if (obstacle.active) {
    obstacle.timer += dt * 16.6;
    if (obstacle.timer > 1800) {
      player.health -= 22;
      obstacle.active = false;
      obstacle.timer = 0;
      obstacle.nextIn = 12000 + Math.random() * 6000;
      document.getElementById('jump-btn').style.display = 'none';
      spawnBlood(player.x, player.y + 20, 8);
    }
  }
}

// ---------- Particles (blood) ----------
function spawnBlood(x, y, count) {
  for (let i = 0; i < count; i++) {
    const a = Math.random() * Math.PI * 2;
    const s = 1 + Math.random() * 3;
    particles.push({
      x, y,
      vx: Math.cos(a) * s, vy: Math.sin(a) * s,
      life: 30 + Math.random() * 20,
      size: 2 + Math.random() * 2,
    });
  }
}

function updateParticles(dt) {
  for (let i = particles.length - 1; i >= 0; i--) {
    const p = particles[i];
    p.x += p.vx * dt; p.y += p.vy * dt;
    p.vx *= 0.94; p.vy *= 0.94;
    p.life -= dt;
    if (p.life <= 0) particles.splice(i, 1);
  }
}

// ---------- Bullets vs Zombies ----------
function updateBullets(dt) {
  for (let i = bullets.length - 1; i >= 0; i--) {
    const b = bullets[i];
    b.x += b.vx * dt; b.y += b.vy * dt; b.life -= dt;
    if (b.life <= 0 || b.x < -20 || b.x > canvas.width + 20 || b.y < -20 || b.y > canvas.height + 20) {
      bullets.splice(i, 1); continue;
    }
    for (let j = zombies.length - 1; j >= 0; j--) {
      const z = zombies[j];
      if (Math.hypot(z.x - b.x, z.y - b.y) < 16) {
        z.hp -= b.damage;
        z.hitFlash = 6;
        spawnBlood(b.x, b.y, 4);
        bullets.splice(i, 1);
        if (z.hp <= 0) {
          spawnBlood(z.x, z.y, 14);
          zombies.splice(j, 1);
          state.score += 10;
        }
        break;
      }
    }
  }
}

// ---------- Rendering ----------
function drawBackground() {
  ctx.fillStyle = '#0a0a0d';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  state.scrollOffset = (state.scrollOffset + 2.4) % 40;
  ctx.strokeStyle = 'rgba(255,255,255,0.03)';
  for (let y = -40 + state.scrollOffset; y < canvas.height; y += 40) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(canvas.width, y);
    ctx.stroke();
  }

  const g = ctx.createRadialGradient(
    canvas.width / 2, canvas.height / 2, canvas.height * 0.2,
    canvas.width / 2, canvas.height / 2, canvas.height * 0.75
  );
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,0.65)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
}

function drawPixelBlock(x, y, w, h, color) {
  ctx.fillStyle = color;
  ctx.fillRect(Math.round(x), Math.round(y), w, h);
}

function drawPlayer() {
  const px = player.x, py = player.y;
  drawPixelBlock(px - 8, py - 26, 16, 14, '#2f5d8a');
  drawPixelBlock(px - 6, py - 34, 12, 10, '#e0b089');
  drawPixelBlock(px - 10, py - 12, 6, 14, '#20364d');
  drawPixelBlock(px + 4, py - 12, 6, 14, '#20364d');

  if (player.health < 40) {
    ctx.fillStyle = 'rgba(180,0,0,0.15)';
    ctx.fillRect(px - 20, py - 40, 40, 50);
  }

  if (aiming) {
    ctx.strokeStyle = 'rgba(255,60,60,0.5)';
    ctx.beginPath();
    ctx.moveTo(px, py - 18);
    ctx.lineTo(aimX, aimY);
    ctx.stroke();
    drawPixelBlock(aimX - 3, aimY - 3, 6, 6, 'rgba(255,60,60,0.8)');
  }
}

function drawZombie(z) {
  const flash = z.hitFlash > 0;
  const body = flash ? '#ffffff' : '#3f6b3a';
  drawPixelBlock(z.x - 8, z.y - 22, 16, 12, body);
  drawPixelBlock(z.x - 6, z.y - 30, 12, 10, flash ? '#fff' : '#4d7a46');
  drawPixelBlock(z.x - 4, z.y - 27, 2, 2, '#ff2020');
  drawPixelBlock(z.x + 2, z.y - 27, 2, 2, '#ff2020');
  drawPixelBlock(z.x - 8, z.y - 10, 6, 12, flash ? '#fff' : '#2e4d2a');
  drawPixelBlock(z.x + 2, z.y - 10, 6, 12, flash ? '#fff' : '#2e4d2a');

  const w = 20;
  ctx.fillStyle = 'rgba(0,0,0,0.5)';
  ctx.fillRect(z.x - w / 2, z.y - 38, w, 3);
  ctx.fillStyle = '#c0392b';
  ctx.fillRect(z.x - w / 2, z.y - 38, w * Math.max(z.hp / z.maxHp, 0), 3);
}

function drawBullets() {
  bullets.forEach(b => drawPixelBlock(b.x - 2, b.y - 2, 4, 4, '#ffe89b'));
}

function drawParticles() {
  particles.forEach(p => {
    ctx.fillStyle = 'rgba(160,0,0,' + Math.min(p.life / 30, 1) + ')';
    ctx.fillRect(p.x, p.y, p.size, p.size);
  });
}

function drawObstacleWarning() {
  if (obstacle.warning) {
    const flashOn = Math.floor(performance.now() / 150) % 2 === 0;
    if (flashOn) {
      ctx.fillStyle = 'rgba(255,180,0,0.35)';
      ctx.fillRect(0, canvas.height - 30, canvas.width, 30);
    }
  }
  if (obstacle.active) {
    ctx.fillStyle = 'rgba(200,30,30,0.55)';
    ctx.fillRect(0, canvas.height - 24, canvas.width, 24);
  }
}

// ---------- HUD ----------
function updateHUD() {
  document.getElementById('health-fill').style.width = Math.max(player.health, 0) + '%';
  const elapsedMin = Math.floor((performance.now() - state.startTime) / 60000);
  document.getElementById('wave-label').textContent = 'Score: ' + state.score + '  |  ' + elapsedMin + 'm';
}

// ---------- Game Over ----------
function gameOver() {
  state.running = false;
  document.getElementById('gameover').style.display = 'flex';
  document.getElementById('final-score').textContent = 'Score: ' + state.score;
}

document.getElementById('restart-btn').addEventListener('click', () => window.location.reload());

// ---------- Main Loop ----------
let lastFrame = performance.now();

function loop(now) {
  if (!state.running) return;
  const dt = Math.min((now - lastFrame) / 16.67, 3);
  lastFrame = now;

  const elapsedMin = (now - state.startTime) / 60000;
  const interval = Math.max(1800 - elapsedMin * 220, 450);
  if (now - state.lastSpawn > interval) {
    spawnZombie();
    state.lastSpawn = now;
  }

  if (aiming) fireWeapon(now);

  updateZombies(dt);
  updateBullets(dt);
  updateParticles(dt);
  updateObstacle(dt);

  drawBackground();
  drawObstacleWarning();
  drawParticles();
  zombies.forEach(drawZombie);
  drawBullets();
  drawPlayer();
  updateHUD();

  if (player.health <= 0) { gameOver(); return; }

  requestAnimationFrame(loop);
}

requestAnimationFrame(loop);
"""

PACKAGE_JSON = """{
  "name": "zombie-survival",
  "version": "1.0.0",
  "description": "Zombie Survival - pixel art survival shooter",
  "main": "index.js",
  "scripts": {},
  "dependencies": {}
}
"""

CAPACITOR_CONFIG = """{
  "appId": "com.nostgames.zombiesurvival",
  "appName": "Zombie Survival",
  "webDir": "www",
  "bundledWebRuntime": false
}
"""

FILES = {
    "www/index.html": INDEX_HTML,
    "www/style.css": STYLE_CSS,
    "www/game.js": GAME_JS,
    "package.json": PACKAGE_JSON,
    "capacitor.config.json": CAPACITOR_CONFIG,
}


def main():
    for path, content in FILES.items():
        directory = os.path.dirname(path)
        if directory and not os.path.exists(directory):
            os.makedirs(directory, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Created:", path)


if __name__ == "__main__":
    main()
