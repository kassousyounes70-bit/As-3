"""
generate_project.py
--------------------
Generates the full web-game project (Zombie Survival, pixel-art, SIDE-VIEW).
This script's ONLY job is to build the project's file structure on disk -
the game logic itself now lives in separate, focused JS files under www/js/.

Run this file (python generate_project.py) inside the repo root.
It writes:
  - package.json
  - capacitor.config.json
  - www/index.html
  - www/style.css
  - www/js/utils.js       (shared pixel-art drawing helpers)
  - www/js/world.js       (maps / background / parallax scrolling)
  - www/js/weapons.js     (weapon configs + firing)
  - www/js/player.js      (the player character)
  - www/js/zombie.js      (zombies)
  - www/js/obstacles.js   (wall-jump obstacle + security-code gate obstacle)
  - www/js/game.js        (main loop, input, HUD, glue code)
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

<div id="code-pad" style="display:none;">
  <div id="code-target"></div>
  <div id="code-buttons">
    <button class="code-btn"></button>
    <button class="code-btn"></button>
    <button class="code-btn"></button>
    <button class="code-btn"></button>
  </div>
</div>

<div id="gameover" style="display:none;">
  <h1>GAME OVER</h1>
  <p id="final-score"></p>
  <button id="restart-btn">Restart</button>
</div>

<script src="js/utils.js"></script>
<script src="js/world.js"></script>
<script src="js/weapons.js"></script>
<script src="js/player.js"></script>
<script src="js/zombie.js"></script>
<script src="js/obstacles.js"></script>
<script src="js/game.js"></script>
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
#code-pad {
  position: fixed; bottom: 24px; left: 20px; right: 20px;
  z-index: 6; color: #fff; text-align: center;
}
#code-target {
  font-size: 20px; font-weight: bold; margin-bottom: 8px;
  text-shadow: 0 0 6px #000;
}
#code-buttons { display: flex; justify-content: center; gap: 10px; }
.code-btn {
  width: 52px; height: 52px; border-radius: 8px; border: none;
  background: rgba(255,255,255,0.18); color: #fff; font-size: 20px; font-weight: bold;
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

UTILS_JS = """// Shared pixel-art drawing helpers used by world.js, player.js,
// zombie.js and obstacles.js. Relies on the global `ctx` created in game.js.

function drawPixelBlock(x, y, w, h, color) {
  ctx.fillStyle = color;
  ctx.fillRect(Math.round(x), Math.round(y), w, h);
}

// Draws a body part with a black pixel-art outline, a base fill color,
// an optional darker shadow band, and an optional lighter highlight band.
function part(x, y, w, h, fill, shadow, highlight) {
  ctx.fillStyle = '#050505';
  ctx.fillRect(Math.round(x - 1), Math.round(y - 1), w + 2, h + 2);

  ctx.fillStyle = fill;
  ctx.fillRect(Math.round(x), Math.round(y), w, h);

  if (shadow) {
    const sh = Math.max(1, Math.ceil(h / 3));
    ctx.fillStyle = shadow;
    ctx.fillRect(Math.round(x), Math.round(y + h - sh), w, sh);
  }
  if (highlight) {
    const hh = Math.max(1, Math.round(h * 0.18));
    ctx.fillStyle = highlight;
    ctx.fillRect(Math.round(x), Math.round(y), w, hh);
  }
}

function drawWalkingLegs(hipX, hipY, phase, colors) {
  const legLen = 14;
  const swingA = Math.sin(phase) * 0.55;
  const swingB = Math.sin(phase + Math.PI) * 0.55;
  [swingA, swingB].forEach(ang => {
    ctx.save();
    ctx.translate(hipX, hipY);
    ctx.rotate(ang);
    part(-3, 0, 6, legLen - 4, colors.main, colors.shadow, null);
    part(-3, legLen - 6, 6, 6, colors.boot, colors.bootShadow, null);
    ctx.restore();
  });
}

function shuffleArray(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
  }
}
"""

WORLD_JS = """// World / maps - side-view parallax background.
// The world scrolls to the RIGHT, because the player is retreating to the
// LEFT: relative to the player, everything else drifts the opposite way.

let groundY = 0;

const world = {
  farOffset: 0,
  midOffset: 0,
  groundOffset: 0,
};

function computeGroundY() {
  groundY = canvas.height * 0.72;
}

function drawBackground(dt) {
  const sky = ctx.createLinearGradient(0, 0, 0, groundY);
  sky.addColorStop(0, '#1a1424');
  sky.addColorStop(0.6, '#140e1a');
  sky.addColorStop(1, '#0d0a10');
  ctx.fillStyle = sky;
  ctx.fillRect(0, 0, canvas.width, groundY);

  ctx.fillStyle = 'rgba(230,220,200,0.16)';
  ctx.beginPath();
  ctx.arc(canvas.width * 0.82, groundY * 0.18, 28, 0, Math.PI * 2);
  ctx.fill();

  world.farOffset = (world.farOffset + dt * 0.5) % 140;
  for (let x = world.farOffset - 140; x < canvas.width + 140; x += 140) {
    drawPixelBlock(x, groundY - 70, 55, 70, '#242434');
    drawPixelBlock(x + 65, groundY - 105, 38, 105, '#1e1e2c');
    ctx.fillStyle = 'rgba(255,196,90,0.55)';
    ctx.fillRect(Math.round(x + 10), Math.round(groundY - 55), 5, 6);
    ctx.fillRect(Math.round(x + 25), Math.round(groundY - 40), 5, 6);
    ctx.fillRect(Math.round(x + 78), Math.round(groundY - 85), 5, 6);
  }

  world.midOffset = (world.midOffset + dt * 1.3) % 220;
  for (let x = world.midOffset - 220; x < canvas.width + 220; x += 220) {
    drawPixelBlock(x, groundY - 18, 34, 18, '#2c2c3a');
  }

  const groundGrad = ctx.createLinearGradient(0, groundY, 0, canvas.height);
  groundGrad.addColorStop(0, '#1e1b20');
  groundGrad.addColorStop(1, '#0a0909');
  ctx.fillStyle = groundGrad;
  ctx.fillRect(0, groundY, canvas.width, canvas.height - groundY);

  ctx.strokeStyle = 'rgba(255,255,255,0.18)';
  ctx.beginPath();
  ctx.moveTo(0, groundY);
  ctx.lineTo(canvas.width, groundY);
  ctx.stroke();

  world.groundOffset = (world.groundOffset + dt * 3.6) % 40;
  ctx.strokeStyle = 'rgba(255,255,255,0.09)';
  for (let x = world.groundOffset - 40; x < canvas.width + 40; x += 40) {
    ctx.beginPath();
    ctx.moveTo(x, groundY + 6);
    ctx.lineTo(x + 12, canvas.height);
    ctx.stroke();
  }

  const fog = ctx.createLinearGradient(0, groundY - 40, 0, groundY + 10);
  fog.addColorStop(0, 'rgba(130,130,150,0)');
  fog.addColorStop(1, 'rgba(130,130,150,0.14)');
  ctx.fillStyle = fog;
  ctx.fillRect(0, groundY - 40, canvas.width, 50);

  const g = ctx.createRadialGradient(
    canvas.width / 2, canvas.height / 2, canvas.height * 0.2,
    canvas.width / 2, canvas.height / 2, canvas.height * 0.85
  );
  g.addColorStop(0, 'rgba(0,0,0,0)');
  g.addColorStop(1, 'rgba(0,0,0,0.5)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, canvas.width, canvas.height);
}
"""

WEAPONS_JS = """// Weapons - the aim direction is forward-fixed; only the vertical tilt
// (set by touch position) changes where bullets go.

const WEAPONS = {
  pistol:  { fireRate: 260, bulletSpeed: 12, damage: 34, spreadCount: 1, spreadAngle: 0 },
  shotgun: { fireRate: 650, bulletSpeed: 10, damage: 20, spreadCount: 4, spreadAngle: 0.16 },
};

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
"""

PLAYER_JS = """// The player character: movement (retreat + jump), aiming and drawing.

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

function updateAimFromTouch(y) {
  const centerY = player.y - 30;
  const range = canvas.height * 0.32;
  let tilt = (y - centerY) / range;
  if (tilt < -1) tilt = -1;
  if (tilt > 1) tilt = 1;
  player.aimTilt = tilt;
}

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

function drawPlayer() {
  const hipX = player.x, hipY = player.y - 15;
  const jacket = player.health < 40 ? '#8a3b3b' : '#2f5d8a';
  const jacketShadow = player.health < 40 ? '#5c2626' : '#1f3f5c';
  const jacketHi = player.health < 40 ? '#b96565' : '#4a7aab';

  if (!player.jumping) {
    drawWalkingLegs(hipX - 2, hipY, player.walkPhase, {
      main: '#20364d', shadow: '#15242f', boot: '#14181b', bootShadow: '#0a0d0f'
    });
  } else {
    part(hipX - 9, hipY, 7, 13, '#20364d', '#15242f');
    part(hipX + 2, hipY, 7, 13, '#20364d', '#15242f');
  }

  const bob = player.jumping ? 0 : Math.abs(Math.sin(player.walkPhase)) * 1.5;

  part(hipX - 8, hipY - 20 - bob, 16, 20, jacket, jacketShadow, jacketHi);

  ctx.fillStyle = '#aa3333';
  ctx.fillRect(Math.round(hipX - 2), Math.round(hipY - 19 - bob), 4, 3);

  part(hipX - 6, hipY - 30 - bob, 12, 10, '#e0a878', '#b98a5e');
  part(hipX - 6, hipY - 33 - bob, 12, 4, '#2a1f16', '#181110');

  ctx.fillStyle = '#111';
  ctx.fillRect(Math.round(hipX + 2), Math.round(hipY - 26 - bob), 2, 2);

  const angle = player.aimTilt * 0.6;
  ctx.save();
  ctx.translate(hipX + 6, hipY - 14 - bob);
  ctx.rotate(angle);
  part(-player.recoil, -3, 10, 6, '#c99a70', '#8a6644');
  part(6 - player.recoil, -2, 18, 4, '#3a3a3a', '#181818');
  if (player.recoil > 4) {
    ctx.fillStyle = 'rgba(255,220,120,0.9)';
    ctx.fillRect(Math.round(22 - player.recoil), -4, 6, 8);
  }
  ctx.restore();
}
"""

ZOMBIE_JS = """// Zombies: spawning, approach behaviour, and drawing.

const zombies = [];

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

function drawZombie(z) {
  const hipX = z.x, hipY = z.y - 15;
  const flash = z.hitFlash > 0;
  const skin = flash ? '#ffffff' : '#4d7a46';
  const skinShadow = flash ? '#dddddd' : '#2e4d2a';
  const skinHi = flash ? null : '#6a9861';
  const bob = Math.abs(Math.sin(z.walkPhase)) * 1.2;

  drawWalkingLegs(hipX + 2, hipY, z.walkPhase, {
    main: flash ? '#eeeeee' : '#3a3830',
    shadow: flash ? '#cccccc' : '#221f1a',
    boot: '#161616', bootShadow: '#0a0a0a'
  });

  // a loosely swinging arm reads much more like an undead gait than a static one
  ctx.save();
  ctx.translate(hipX - 6, hipY - 16 - bob);
  ctx.rotate(0.4 + Math.sin(z.walkPhase) * 0.15);
  part(-2, 0, 5, 12, flash ? '#eee' : '#3a5a35', flash ? '#ccc' : '#233b20');
  ctx.restore();

  part(hipX - 8, hipY - 20 - bob, 16, 20, skin, skinShadow, skinHi);

  if (!flash) {
    ctx.fillStyle = '#3a3830';
    ctx.fillRect(Math.round(hipX - 6), Math.round(hipY - 14 - bob), 6, 8);
    ctx.fillStyle = '#4a0f0f';
    ctx.fillRect(Math.round(hipX + 2), Math.round(hipY - 10 - bob), 4, 4);
  }

  part(hipX - 6, hipY - 30 - bob, 12, 10, skin, skinShadow);

  ctx.fillStyle = 'rgba(255,40,40,0.28)';
  ctx.fillRect(Math.round(hipX - 7), Math.round(hipY - 28 - bob), 7, 4);
  ctx.fillStyle = '#ff2b2b';
  ctx.fillRect(Math.round(hipX - 6), Math.round(hipY - 27 - bob), 2, 2);
  ctx.fillRect(Math.round(hipX - 2), Math.round(hipY - 27 - bob), 2, 2);

  const w = 20;
  ctx.fillStyle = 'rgba(0,0,0,0.5)';
  ctx.fillRect(hipX - w / 2, hipY - 40 - bob, w, 3);
  ctx.fillStyle = '#c0392b';
  ctx.fillRect(hipX - w / 2, hipY - 40 - bob, w * Math.max(z.hp / z.maxHp, 0), 3);
}
"""

OBSTACLES_JS = """// Obstacles that appear behind the retreating player (off to the left,
// where the player cannot see). Two kinds for now:
//   - 'wall'  : tap JUMP in time
//   - 'gate'  : a locked gate - enter the 3-digit security code in time

const obstacle = {
  type: null,
  active: false,
  warning: false,
  timer: 0,
  nextIn: 12000 + Math.random() * 6000,
  codeSequence: [],
  codeProgress: 0,
};

function beginObstacle() {
  obstacle.type = Math.random() < 0.5 ? 'wall' : 'gate';
  if (obstacle.type === 'wall') {
    document.getElementById('jump-btn').style.display = 'block';
  } else {
    setupGateUI();
  }
}

function setupGateUI() {
  const pool = [1, 2, 3, 4, 5, 6, 7, 8, 9];
  shuffleArray(pool);
  const correct = pool.slice(0, 3);
  const decoy = pool[3];
  const buttons = correct.concat([decoy]);
  shuffleArray(buttons);

  obstacle.codeSequence = correct;
  obstacle.codeProgress = 0;

  document.getElementById('code-target').textContent = correct.join(' - ');
  const btns = document.querySelectorAll('.code-btn');
  btns.forEach((b, i) => {
    b.textContent = buttons[i];
    b.onclick = () => handleCodeTap(buttons[i]);
  });
  document.getElementById('code-pad').style.display = 'block';
}

function handleCodeTap(digit) {
  if (digit === obstacle.codeSequence[obstacle.codeProgress]) {
    obstacle.codeProgress++;
    if (obstacle.codeProgress >= obstacle.codeSequence.length) {
      resolveObstacle();
    }
  } else {
    obstacle.codeProgress = 0;
  }
}

function resolveObstacle() {
  if (obstacle.type === 'wall') startJump();
  obstacle.active = false;
  obstacle.timer = 0;
  obstacle.nextIn = 12000 + Math.random() * 6000;
  document.getElementById('jump-btn').style.display = 'none';
  document.getElementById('code-pad').style.display = 'none';
}

document.getElementById('jump-btn').addEventListener('click', () => {
  if (obstacle.active && obstacle.type === 'wall') resolveObstacle();
  else startJump();
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
      beginObstacle();
    }
  } else if (obstacle.active) {
    obstacle.timer += dt * 16.6;
    const windowMs = obstacle.type === 'gate' ? 3200 : 1800;
    if (obstacle.timer > windowMs) {
      player.health -= obstacle.type === 'gate' ? 28 : 22;
      obstacle.active = false;
      obstacle.timer = 0;
      obstacle.nextIn = 12000 + Math.random() * 6000;
      document.getElementById('jump-btn').style.display = 'none';
      document.getElementById('code-pad').style.display = 'none';
      spawnBlood(player.x - 20, player.y - 5, 8);
    }
  }
}

function drawObstacle() {
  const ox = player.x - 55;
  if (obstacle.warning) {
    const flashOn = Math.floor(performance.now() / 150) % 2 === 0;
    if (flashOn) drawPixelBlock(ox, groundY - 8, 22, 8, 'rgba(255,180,0,0.6)');
  }
  if (obstacle.active) {
    if (obstacle.type === 'wall') {
      part(ox, groundY - 20, 22, 20, '#4a3a2a', '#2c2214');
    } else {
      part(ox, groundY - 28, 22, 28, '#3a3f45', '#22262a');
      ctx.fillStyle = '#e0c060';
      ctx.fillRect(Math.round(ox + 8), Math.round(groundY - 18), 6, 6);
    }
  }
}
"""

GAME_JS = """// Main entry point: canvas setup, shared state, particles, bullets,
// input wiring, HUD, game-over handling, and the main loop.
// All other files (world/weapons/player/zombie/obstacles) are loaded
// before this one and expose their pieces as plain global functions/objects.

const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');

const state = {
  running: true,
  startTime: performance.now(),
  lastSpawn: 0,
  score: 0,
};

const bullets = [];
const particles = [];

function resize() {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  computeGroundY();
  placePlayer();
}
window.addEventListener('resize', resize);
resize();

// ---------- Input ----------
let aiming = false;

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

function drawParticles() {
  particles.forEach(p => {
    ctx.fillStyle = 'rgba(160,0,0,' + Math.min(p.life / 30, 1) + ')';
    ctx.fillRect(p.x, p.y, p.size, p.size);
  });
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

function drawBullets() {
  bullets.forEach(b => drawPixelBlock(b.x - 2, b.y - 2, 5, 3, '#ffe89b'));
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
    "www/js/utils.js": UTILS_JS,
    "www/js/world.js": WORLD_JS,
    "www/js/weapons.js": WEAPONS_JS,
    "www/js/player.js": PLAYER_JS,
    "www/js/zombie.js": ZOMBIE_JS,
    "www/js/obstacles.js": OBSTACLES_JS,
    "www/js/game.js": GAME_JS,
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
