"""
generate_project.py
--------------------
Generates the full web-game project (Zombie Survival, pixel-art, SIDE-VIEW)
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

GAME_JS = """// Zombie Survival - Core Game Engine (MVP v2 - SIDE VIEW)
// Pixel-art style rendering via Canvas 2D - no external image assets.
// Player always faces right (where zombies approach from) and visually
// retreats to the left as the world scrolls past. Aim is forward-fixed
// with a vertical tilt controlled by touch position.

const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');

let groundY = 0;

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  groundY = canvas.height * 0.72;
  placePlayer();
}
window.addEventListener('resize', resize);

// ---------- Game State ----------
const state = {
  running: true,
  startTime: performance.now(),
  lastSpawn: 0,
  score: 0,
  farOffset: 0,
  midOffset: 0,
  groundOffset: 0,
};

const player = {
  x: 0, y: 0,
  health: 100,
  maxHealth: 100,
  weapon: 'pistol',
  lastFire: 0,
  aimTilt: 0,     // -1 (up) .. 1 (down)
  recoil: 0,
  walkPhase: 0,
  jumping: false,
  jumpVel: 0,
};

function placePlayer() {
  player.x = canvas.width * 0.24;
  player.y = groundY;
}
resize();

const bullets = [];
const zombies = [];
const particles = [];

// ---------- Weapons (forward-fixed direction, vertical spread only) ----------
const WEAPONS = {
  pistol:  { fireRate: 260, bulletSpeed: 12, damage: 34, spreadCount: 1, spreadAngle: 0 },
  shotgun: { fireRate: 650, bulletSpeed: 10, damage: 20, spreadCount: 4, spreadAngle: 0.16 },
};

let aiming = false;

function updateAimFromTouch(y) {
  const centerY = player.y - 30;
  const range = canvas.height * 0.32;
  let tilt = (y - centerY) / range;
  if (tilt < -1) tilt = -1;
  if (tilt > 1) tilt = 1;
  player.aimTilt = tilt;
}

function fireWeapon(now) {
  const w = WEAPONS[player.weapon];
  if (now - player.lastFire < w.fireRate) return;
  player.lastFire = now;
  player.recoil = 8;

  const baseAngle = player.aimTilt * 0.6;
  const muzzleX = player.x + 24;
  const muzzleY = player.y - 20;

  const half = (w.spreadCount - 1) / 2;
  for (let i = 0; i < w.spreadCount; i++) {
    const angle = baseAngle + (i - half) * w.spreadAngle;
    bullets.push({
      x: muzzleX, y: muzzleY,
      vx: Math.cos(angle) * w.bulletSpeed,
      vy: Math.sin(angle) * w.bulletSpeed,
      damage: w.damage,
      life: 90,
    });
  }
}

// ---------- Input ----------
function pointerDown(y) { aiming = true; updateAimFromTouch(y); }
function pointerMove(y) { if (aiming) updateAimFromTouch(y); }
function pointerUp() { aiming = false; }

canvas.addEventListener('touchstart', e => {
  pointerDown(e.touches[0].clientY);
  e.preventDefault();
}, { passive: false });

canvas.addEventListener('touchmove', e => {
  pointerMove(e.touches[0].clientY);
  e.preventDefault();
}, { passive: false });

canvas.addEventListener('touchend', () => pointerUp(), { passive: false });

canvas.addEventListener('mousedown', e => pointerDown(e.clientY));
canvas.addEventListener('mousemove', e => pointerMove(e.clientY));
window.addEventListener('mouseup', pointerUp);

document.getElementById('weapon-switch').addEventListener('click', () => {
  player.weapon = player.weapon === 'pistol' ? 'shotgun' : 'pistol';
});

// ---------- Jump ----------
function startJump() {
  if (!player.jumping) {
    player.jumping = true;
    player.jumpVel = -9;
  }
}

function updateJump(dt) {
  if (player.jumping) {
    player.y += player.jumpVel * dt;
    player.jumpVel += 0.55 * dt;
    if (player.y >= groundY) {
      player.y = groundY;
      player.jumping = false;
      player.jumpVel = 0;
    }
  }
}

// ---------- Zombies (approach from the right only, for now) ----------
function spawnZombie() {
  const elapsedMin = (performance.now() - state.startTime) / 60000;
  const speedBonus = Math.min(elapsedMin * 0.12, 1.0);
  const hpBonus = Math.min(elapsedMin * 8, 60);

  zombies.push({
    x: canvas.width + 30,
    y: groundY,
    speed: 1.1 + Math.random() * 0.4 + speedBonus,
    hp: 40 + hpBonus,
    maxHp: 40 + hpBonus,
    hitFlash: 0,
    walkPhase: Math.random() * Math.PI * 2,
  });
}

function updateZombies(dt) {
  zombies.forEach(z => {
    z.walkPhase += dt * 0.18 * z.speed;
    const dx = player.x - z.x;
    const dist = Math.abs(dx);
    if (dist > 34) {
      z.x += (dx / dist) * z.speed * dt;
    } else {
      player.health -= 0.35 * dt;
    }
    if (z.hitFlash > 0) z.hitFlash -= dt;
  });
}

// ---------- Obstacles (emerge from behind, where the player is retreating into) ----------
const obstacle = {
  active: false,
  warning: false,
  timer: 0,
  nextIn: 12000 + Math.random() * 6000,
};

document.getElementById('jump-btn').addEventListener('click', () => {
  startJump();
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
      spawnBlood(player.x - 20, player.y - 5, 8);
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
    if (b.life <= 0 || b.x > canvas.width + 40 || b.y < -40 || b.y > canvas.height + 40) {
      bullets.splice(i, 1); continue;
    }
    for (let j = zombies.length - 1; j >= 0; j--) {
      const z = zombies[j];
      if (Math.hypot(z.x - b.x, (z.y - 16) - b.y) < 18) {
        z.hp -= b.damage;
        z.hitFlash = 6;
        spawnBlood(b.x, b.y, 4);
        bullets.splice(i, 1);
        if (z.hp <= 0) {
          spawnBlood(z.x, z.y - 14, 14);
          zombies.splice(j, 1);
          state.score += 10;
        }
        break;
      }
    }
  }
}

// ---------- Rendering helpers ----------
function drawPixelBlock(x, y, w, h, color) {
  ctx.fillStyle = color;
  ctx.fillRect(Math.round(x), Math.round(y), w, h);
}

function drawWalkingLegs(hipX, hipY, phase, color) {
  const legLen = 15;
  const swingA = Math.sin(phase) * 0.55;
  const swingB = Math.sin(phase + Math.PI) * 0.55;
  [swingA, swingB].forEach(ang => {
    ctx.save();
    ctx.translate(hipX, hipY);
    ctx.rotate(ang);
    ctx.fillStyle = color;
    ctx.fillRect(-3, 0, 6, legLen);
    ctx.restore();
  });
}

// ---------- Background (parallax side-view) ----------
function drawBackground(dt) {
  ctx.fillStyle = '#0a0a0d';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  // distant skyline silhouette (slow layer)
  state.farOffset = (state.farOffset - dt * 0.5) % 140;
  ctx.fillStyle = '#141419';
  for (let x = state.farOffset - 140; x < canvas.width + 140; x += 140) {
    drawPixelBlock(x, groundY - 70, 55, 70, '#141419');
    drawPixelBlock(x + 65, groundY - 105, 38, 105, '#141419');
  }

  // mid debris layer (medium speed)
  state.midOffset = (state.midOffset - dt * 1.3) % 220;
  for (let x = state.midOffset - 220; x < canvas.width + 220; x += 220) {
    drawPixelBlock(x, groundY - 18, 34, 18, '#1c1c22');
  }

  // ground fill
  drawPixelBlock(0, groundY, canvas.width, canvas.height - groundY, '#101012');
  ctx.strokeStyle = 'rgba(255,255,255,0.08)';
  ctx.beginPath();
  ctx.moveTo(0, groundY);
  ctx.lineTo(canvas.width, groundY);
  ctx.stroke();

  // fast ground ticks (sells the retreat motion)
  state.groundOffset = (state.groundOffset - dt * 3.6) % 40;
  ctx.strokeStyle = 'rgba(255,255,255,0.06)';
  for (let x = state.groundOffset - 40; x < canvas.width + 40; x += 40) {
    ctx.beginPath();
    ctx.moveTo(x, groundY + 6);
    ctx.lineTo(x - 12, canvas.height);
    ctx.stroke();
  }

  // vignette
  const g = ctx.createRadialGradient(
    canvas.width / 2, canvas.height / 2, canvas.height * 0.2,
    canvas.width / 2, canvas.height / 2, canvas.height * 0.8
  );
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,0.6)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
}

function drawObstacle() {
  const ox = player.x - 55;
  if (obstacle.warning) {
    const flashOn = Math.floor(performance.now() / 150) % 2 === 0;
    if (flashOn) drawPixelBlock(ox, groundY - 8, 22, 8, 'rgba(255,180,0,0.6)');
  }
  if (obstacle.active) {
    drawPixelBlock(ox, groundY - 20, 22, 20, '#4a3a2a');
  }
}

function drawPlayer() {
  const hipX = player.x, hipY = player.y - 15;
  const bodyColor = player.health < 40 ? '#7a3030' : '#2f5d8a';

  if (!player.jumping) drawWalkingLegs(hipX - 2, hipY, player.walkPhase, '#20364d');
  else drawPixelBlock(hipX - 8, hipY, 6, 12, '#20364d');

  drawPixelBlock(hipX - 8, hipY - 20, 16, 20, bodyColor);
  drawPixelBlock(hipX - 6, hipY - 30, 12, 10, '#e0b089');

  const angle = player.aimTilt * 0.6;
  ctx.save();
  ctx.translate(hipX + 6, hipY - 14);
  ctx.rotate(angle);
  drawPixelBlock(-player.recoil, -2, 22, 4, '#333');
  if (player.recoil > 4) {
    drawPixelBlock(20 - player.recoil, -4, 6, 8, 'rgba(255,220,120,0.9)');
  }
  ctx.restore();
}

function drawZombie(z) {
  const hipX = z.x, hipY = z.y - 15;
  const flash = z.hitFlash > 0;
  const bodyColor = flash ? '#ffffff' : '#3f6b3a';

  drawWalkingLegs(hipX + 2, hipY, z.walkPhase, flash ? '#fff' : '#2e4d2a');
  drawPixelBlock(hipX - 8, hipY - 20, 16, 20, bodyColor);
  drawPixelBlock(hipX - 6, hipY - 30, 12, 10, flash ? '#fff' : '#4d7a46');
  drawPixelBlock(hipX - 6, hipY - 27, 2, 2, '#ff2020');
  drawPixelBlock(hipX - 2, hipY - 27, 2, 2, '#ff2020');

  const w = 20;
  ctx.fillStyle = 'rgba(0,0,0,0.5)';
  ctx.fillRect(hipX - w / 2, hipY - 38, w, 3);
  ctx.fillStyle = '#c0392b';
  ctx.fillRect(hipX - w / 2, hipY - 38, w * Math.max(z.hp / z.maxHp, 0), 3);
}

function drawBullets() {
  bullets.forEach(b => drawPixelBlock(b.x - 2, b.y - 2, 5, 3, '#ffe89b'));
}

function drawParticles() {
  particles.forEach(p => {
    ctx.fillStyle = 'rgba(160,0,0,' + Math.min(p.life / 30, 1) + ')';
    ctx.fillRect(p.x, p.y, p.size, p.size);
  });
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
  if (player.recoil > 0) { player.recoil -= dt * 1.1; if (player.recoil < 0) player.recoil = 0; }
  if (!player.jumping) player.walkPhase += dt * 0.22;

  updateJump(dt);
  updateZombies(dt);
  updateBullets(dt);
  updateParticles(dt);
  updateObstacle(dt);

  drawBackground(dt);
  drawObstacle();
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
