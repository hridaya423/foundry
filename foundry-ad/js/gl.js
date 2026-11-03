// WebGL layer: II (keycap strike, sparks, time freeze, the camera finds one ember).
// Rendered from composition time only (L.on clock), never from requestAnimationFrame.
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

const { clamp, lerp, prog, smooth, ease, rng, hash, warp, PLAN } = window.L;
const W = 1920, H = 1080;

const canvas = document.getElementById("gl");
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true, powerPreference: "high-performance" });
renderer.setPixelRatio(1);
renderer.setSize(W, H, false);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.0;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.setClearColor(0x000000, 1);

const pmrem = new THREE.PMREMGenerator(renderer);
const envTex = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;

// ---------------------------------------------------------------- spark streak material (shared)
// depthRef: view depth at which aWidth is in true pixels (scene-scale dependent)
export function sparkMaterial(depthRef = 1.6) {
  return new THREE.ShaderMaterial({
    uniforms: { uRes: { value: new THREE.Vector2(W, H) }, uDepthRef: { value: depthRef } },
    vertexShader: /* glsl */ `
      attribute vec2 corner;
      attribute vec3 aHead;
      attribute vec3 aTail;
      attribute vec4 aCol;
      attribute float aWidth;
      uniform vec2 uRes;
      uniform float uDepthRef;
      varying vec2 vUv;
      varying vec4 vCol;
      void main() {
        vec4 h = projectionMatrix * viewMatrix * vec4(aHead, 1.0);
        vec4 t = projectionMatrix * viewMatrix * vec4(aTail, 1.0);
        if (aCol.a <= 0.0 || h.w < 0.06 || t.w < 0.06) { gl_Position = vec4(2.0, 2.0, 2.0, 1.0); vUv = vec2(0.0); vCol = vec4(0.0); return; }
        vec2 hs = h.xy / h.w, ts = t.xy / t.w;
        vec2 d = (hs - ts) * uRes * 0.5;
        float len = length(d);
        vec2 along = len > 1e-4 ? d / len : vec2(1.0, 0.0);
        vec2 nrm = vec2(-along.y, along.x);
        vec2 base = mix(ts, hs, corner.x);
        float wpx = aWidth * clamp(uDepthRef / h.w, 0.35, 2.2);
        vec2 off = nrm * corner.y * wpx * 0.5 + along * (corner.x * 2.0 - 1.0) * wpx * 0.5;
        float w = mix(t.w, h.w, corner.x);
        float z = mix(t.z / t.w, h.z / h.w, corner.x);
        gl_Position = vec4((base + off / (uRes * 0.5)) * w, z * w, w);
        vUv = corner;
        vCol = aCol;
      }`,
    fragmentShader: /* glsl */ `
      varying vec2 vUv;
      varying vec4 vCol;
      void main() {
        float across = 1.0 - smoothstep(0.15, 1.0, abs(vUv.y));
        float along = mix(0.08, 1.0, pow(clamp(vUv.x, 0.0, 1.0), 1.6));
        float a = clamp(across * along * vCol.a, 0.0, 1.0);
        gl_FragColor = vec4(min(vCol.rgb * a, vec3(40.0)), a);
      }`,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
}

export function sparkMesh(n, depthRef) {
  const g = new THREE.InstancedBufferGeometry();
  g.setAttribute("corner", new THREE.BufferAttribute(new Float32Array([0, -1, 1, -1, 1, 1, 0, 1]), 2));
  g.setIndex([0, 1, 2, 0, 2, 3]);
  g.setAttribute("position", new THREE.BufferAttribute(new Float32Array(12), 3));
  const head = new THREE.InstancedBufferAttribute(new Float32Array(n * 3), 3);
  const tail = new THREE.InstancedBufferAttribute(new Float32Array(n * 3), 3);
  const col = new THREE.InstancedBufferAttribute(new Float32Array(n * 4), 4);
  const wid = new THREE.InstancedBufferAttribute(new Float32Array(n), 1);
  for (const a of [head, tail, col, wid]) a.setUsage(THREE.DynamicDrawUsage);
  g.setAttribute("aHead", head);
  g.setAttribute("aTail", tail);
  g.setAttribute("aCol", col);
  g.setAttribute("aWidth", wid);
  g.instanceCount = n;
  const m = new THREE.Mesh(g, sparkMaterial(depthRef));
  m.frustumCulled = false;
  return { mesh: m, head, tail, col, wid, n };
}

// heat 1 (just born) .. 0 (dead): white-hot -> peach -> molten -> deep red. HDR intensity for bloom.
const HEAT = [[1.0, 0.98, 0.92], [1.0, 0.85, 0.68], [1.0, 0.353, 0.122], [0.48, 0.07, 0.02]];
export function heatColor(h, out) {
  const x = clamp(1 - h) * 3;
  const i = Math.min(2, Math.floor(x));
  const f = x - i;
  for (let k = 0; k < 3; k++) out[k] = lerp(HEAT[i][k], HEAT[i + 1][k], f);
  return out;
}

// Closed-form point under gravity g (y) with linear drag k: x(t) = x0 + (g/k) t + (v0 - g/k)(1 - e^{-kt})/k
function ballistic(p0, v0, k, g, t, out) {
  const e = (1 - Math.exp(-k * t)) / k;
  out[0] = p0[0] + v0[0] * e;
  out[1] = p0[1] + (g / k) * t + (v0[1] - g / k) * e;
  out[2] = p0[2] + v0[2] * e;
  return out;
}

// ---------------------------------------------------------------- Act II scene
function glyphTexture(draw, size = 512) {
  const c = document.createElement("canvas");
  c.width = c.height = size;
  const x = c.getContext("2d");
  x.clearRect(0, 0, size, size);
  x.strokeStyle = x.fillStyle = "#f4f4f2";
  x.lineCap = "butt";
  x.lineJoin = "miter";
  draw(x, size);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

function drawOption(x, s, scale = 1) {
  const u = (s / 512) * scale;
  x.save();
  x.translate(s / 2, s / 2);
  x.lineWidth = 30 * u;
  x.beginPath();
  x.moveTo(-150 * u, -86 * u);
  x.lineTo(-58 * u, -86 * u);
  x.lineTo(62 * u, 86 * u);
  x.lineTo(150 * u, 86 * u);
  x.moveTo(30 * u, -86 * u);
  x.lineTo(150 * u, -86 * u);
  x.stroke();
  x.restore();
}

// ⌘: the four sides of a square run on into a loop at every corner.
function drawCommand(x, s, scale = 1) {
  const u = (s / 512) * scale;
  const a = 52 * u, r = 46 * u;
  x.save();
  x.translate(s / 2, s / 2);
  x.lineWidth = 24 * u;
  x.beginPath();
  x.moveTo(-a, -a - r); x.lineTo(-a, a + r);
  x.moveTo(a, -a - r); x.lineTo(a, a + r);
  x.moveTo(-a - r, -a); x.lineTo(a + r, -a);
  x.moveTo(-a - r, a); x.lineTo(a + r, a);
  x.stroke();
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
    const phi = Math.atan2(-sy, -sx);
    x.beginPath();
    x.arc(sx * (a + r), sy * (a + r), r, phi + Math.PI / 4, phi + Math.PI * 7 / 4);
    x.stroke();
  }
  x.restore();
}

function drawLabel(x, s, text, align = "left") {
  x.font = `500 ${Math.round(s * 0.11)}px Archivo`;
  x.textAlign = align;
  x.textBaseline = "alphabetic";
  x.fillText(text, align === "left" ? s * 0.12 : s * 0.88, s * 0.86);
}

function buildKeys() {
  const scene = new THREE.Scene();
  scene.environment = envTex;
  scene.environmentIntensity = 0.05;
  scene.background = new THREE.Color(0x000000);

  const keyMat = () => new THREE.MeshStandardMaterial({ color: 0x09090a, roughness: 0.46, metalness: 0.0 });
  const capH = 0.2;
  const keys = [];
  const row = [
    { x: -1.22, w: 1.0, glyph: (c, s) => { drawLabel(c, s, "control"); }, dim: 0.45 },
    { x: 0, w: 1.0, glyph: (c, s) => { drawOption(c, s, 1.0); }, hero: true },
    { x: 1.345, w: 1.25, glyph: (c, s) => { drawCommand(c, s, 0.62); drawLabel(c, s, "command"); }, dim: 0.6 },
    { x: 1.345 + 0.625 + 0.12 + 2.9, w: 5.8, glyph: null, dim: 1 },
  ];
  for (const k of row) {
    const geo = new RoundedBoxGeometry(k.w, capH, 1.0, 6, 0.11);
    const mesh = new THREE.Mesh(geo, keyMat());
    mesh.position.set(k.x, 0, 0);
    scene.add(mesh);
    if (k.glyph) {
      const tex = glyphTexture(k.glyph);
      const g = new THREE.Mesh(new THREE.PlaneGeometry(Math.min(k.w, 1.0) * 0.9, 0.9),
        new THREE.MeshBasicMaterial({ map: tex, transparent: true, opacity: k.hero ? 1 : k.dim, toneMapped: true, depthWrite: false }));
      g.rotation.x = -Math.PI / 2;
      g.position.set(0, capH / 2 + 0.002, 0);
      g.renderOrder = 2;
      mesh.add(g);
    }
    keys.push({ ...k, mesh });
  }
  const deck = new THREE.Mesh(new THREE.PlaneGeometry(60, 60), new THREE.MeshStandardMaterial({ color: 0x030303, roughness: 0.92, metalness: 0, envMapIntensity: 0 }));
  deck.rotation.x = -Math.PI / 2;
  deck.position.y = -capH / 2 - 0.06;
  scene.add(deck);

  const rim = new THREE.DirectionalLight(0xdfe8ff, 1.8);
  rim.position.set(-1.2, 0.9, -4.5);
  scene.add(rim);
  const side = new THREE.DirectionalLight(0xffffff, 0.12);
  side.position.set(-4, 3, 0.5);
  scene.add(side);
  const fire = new THREE.PointLight(0xff5a1f, 0, 2.6, 2);
  fire.position.set(0, capH * 0.1, 0.62);
  scene.add(fire);

  // shockwave rings (flat, on the deck)
  const ringMat = (c) => new THREE.MeshBasicMaterial({ color: c, transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
  const ring1 = new THREE.Mesh(new THREE.RingGeometry(0.97, 1.0, 160), ringMat(new THREE.Color(3.2, 1.6, 0.8)));
  const ring2 = new THREE.Mesh(new THREE.RingGeometry(0.985, 1.0, 160), ringMat(new THREE.Color(2.2, 2.0, 1.9)));
  for (const r of [ring1, ring2]) { r.rotation.x = -Math.PI / 2; r.position.y = deck.position.y + 0.004; scene.add(r); }

  // sparks: perimeter of the hero key, outward + up
  const N = 1200;
  const S = sparkMesh(N);
  scene.add(S.mesh);
  const R = rng(1360);
  const P = [];
  for (let i = 0; i < N; i++) {
    const side = Math.floor(R() * 4), u = R() * 2 - 1;
    const half = 0.5;
    const px = side === 0 ? u * half : side === 1 ? half : side === 2 ? -u * half : -half;
    const pz = side === 0 ? half : side === 1 ? u * half : side === 2 ? -half : -u * half;
    const out = Math.atan2(pz, px) * 0.35 + (side === 0 ? Math.PI / 2 : side === 1 ? 0 : side === 2 ? -Math.PI / 2 : Math.PI) * 0.65;
    const az = out + (R() - 0.5) * 1.6;
    const el = 0.05 + Math.pow(R(), 1.4) * 1.05;
    const ember = R() < 0.22;
    const sp = ember ? 1.2 + R() * 2.4 : 3.2 + Math.pow(R(), 0.7) * 8.5;
    P.push({
      p0: [px * 1.02, -capH / 2 - 0.02 + R() * 0.05, pz * 1.02],
      v0: [Math.cos(az) * Math.cos(el) * sp, Math.sin(el) * sp * (ember ? 1.4 : 1), Math.sin(az) * Math.cos(el) * sp],
      k: ember ? 3.2 : 1.6 + R() * 1.4,
      g: ember ? -1.4 : -7.5,
      life: ember ? 0.9 + R() * 1.4 : 0.35 + R() * 0.75,
      delay: R() * 0.035,
      width: ember ? 2.2 + R() * 2.2 : 2.6 + R() * 3.2,
      gain: ember ? 2.0 + R() * 2.5 : 3.5 + R() * 5,
    });
  }
  // the hero ember: off the front edge, up and toward the lens; the camera ends the scene on it
  const HERO = N - 1;
  P[HERO] = { p0: [0.06, -capH / 2 + 0.02, 0.52], v0: [0.35, 2.3, 1.05], k: 3.2, g: -1.4, life: 0.8, delay: 0, width: 9, gain: 5.5 };

  const camera = new THREE.PerspectiveCamera(30, W / H, 0.05, 200);

  // time warp: real speed at the hit, decelerate to a near standstill and hold
  const t0 = PLAN.strike, t1 = PLAN.first;
  const D0 = t1 - 0.42 - 0.36, D1 = t1 - 0.42;   // the dolly onto the hero ember lands as the zoom begins
  const speed = (t) => {
    if (t < t0 + 0.14) return 1;
    if (t < t0 + 0.42) return lerp(1, 0.012, smooth(prog(t, t0 + 0.14, t0 + 0.42)));
    return 0.012;
  };
  const tau = warp(t0, t1 + 0.1, speed);
  const look = new THREE.Vector3(), pos = new THREE.Vector3(), hero3 = new THREE.Vector3(), away = new THREE.Vector3();
  const tmp = [0, 0, 0], tmp2 = [0, 0, 0], col = [0, 0, 0];

  function render(t) {
    const tt = tau(t);
    const sp = speed(t);
    // key: bottomed out at the strike, squash and recover
    const hero = keys[1].mesh;
    const pk = prog(t, t0, t0 + 0.16);
    hero.position.y = -0.045 + 0.02 * ease.outCubic(pk);
    hero.scale.set(1 + 0.015 * Math.sin(pk * Math.PI), 1 - 0.05 * Math.exp(-pk * 6), 1 + 0.015 * Math.sin(pk * Math.PI));
    for (const k of keys) if (!k.hero) k.mesh.position.y = -0.006 * Math.exp(-tt * 18);

    fire.intensity = 5 * Math.exp(-tt * 6) + 0.9 * clamp(1 - tt * 1.2);

    ring1.scale.setScalar(0.72 + tt * 9);
    ring2.scale.setScalar(0.72 + tt * 15);
    ring1.material.opacity = Math.pow(clamp(1 - tt / 0.2), 2);
    ring2.material.opacity = Math.pow(clamp(1 - tt / 0.13), 2) * 0.7;

    // camera: impact shake, then bullet-time drift through the frozen sparks
    const drift = ease.inOutCubic(prog(t, t0 + 0.25, D1));
    const th = lerp(0.42, -0.12, drift);
    const rad = lerp(2.75, 2.2, drift);
    const hgt = lerp(1.18, 0.7, drift);
    const shake = Math.exp(-prog(t, t0, t0 + 0.5) * 6) * (t >= t0 ? 1 : 0);
    const f = Math.floor(t * 60);
    pos.set(Math.sin(th) * rad + (hash(f) - 0.5) * 0.06 * shake, hgt + (hash(f + 99) - 0.5) * 0.06 * shake, Math.cos(th) * rad);
    look.set(0.18 + Math.sin(th) * 0.2, -0.05, 0);
    // dolly: the hero ember slides to frame centre and the camera closes to 0.55 from it
    const q = P[HERO];
    ballistic(q.p0, q.v0, q.k, q.g, Math.max(0, tt - q.delay), tmp);
    hero3.set(tmp[0], tmp[1], tmp[2]);
    const dl = ease.inOutCubic(prog(t, D0, D1));
    away.copy(pos).sub(hero3).normalize().multiplyScalar(0.55).add(hero3);
    camera.position.lerpVectors(pos, away, dl);
    camera.lookAt(look.lerp(hero3, Math.min(1, dl * 1.6)));
    camera.fov = lerp(30, 33, drift);
    camera.updateProjectionMatrix();

    const shutter = 1 / 60 * 0.75;
    for (let i = 0; i < N; i++) {
      const q = P[i];
      const a = tt - q.delay;
      const o = i * 3, c4 = i * 4;
      if (a <= 0 || a > q.life) {
        S.col.array[c4 + 3] = 0;
        continue;
      }
      ballistic(q.p0, q.v0, q.k, q.g, a, tmp);
      const trail = i === HERO ? Math.max(0.0015, shutter * sp) : Math.max(0.022, shutter * sp) + (a < 0.03 ? 0.02 : 0);
      ballistic(q.p0, q.v0, q.k, q.g, Math.max(0, a - trail), tmp2);
      if (tmp[1] < -capH / 2 - 0.06) { tmp[1] = -capH / 2 - 0.06; tmp2[1] = Math.max(tmp2[1], tmp[1]); }
      S.head.array[o] = tmp[0]; S.head.array[o + 1] = tmp[1]; S.head.array[o + 2] = tmp[2];
      S.tail.array[o] = tmp2[0]; S.tail.array[o + 1] = tmp2[1]; S.tail.array[o + 2] = tmp2[2];
      const heat = 1 - a / q.life;
      heatColor(heat, col);
      const g = q.gain * (0.35 + 0.65 * heat);
      S.col.array[c4] = col[0] * g; S.col.array[c4 + 1] = col[1] * g; S.col.array[c4 + 2] = col[2] * g;
      S.col.array[c4 + 3] = clamp(heat * 3);
      S.wid.array[i] = q.width * (0.6 + 0.4 * heat);
    }
    S.head.needsUpdate = S.tail.needsUpdate = S.col.needsUpdate = S.wid.needsUpdate = true;
    return camera;
  }
  return { scene, camera, render, tau };
}

// ---------------------------------------------------------------- composer
const composer = new EffectComposer(renderer, new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType, samples: 4 }));
const renderPass = new RenderPass(new THREE.Scene(), new THREE.PerspectiveCamera());
const bloom = new UnrealBloomPass(new THREE.Vector2(W, H), 1.0, 0.55, 0.8);
composer.addPass(renderPass);
composer.addPass(bloom);
composer.addPass(new OutputPass());

const keys = buildKeys();

let blank = false;
function draw(t) {
  let scene = null, camera = null;
  if (t >= PLAN.strike && t < PLAN.first) {
    camera = keys.render(t);
    scene = keys.scene;
    bloom.strength = 0.9;
    bloom.radius = 0.4;
    bloom.threshold = 1.6;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
  }
  if (!scene) {
    if (!blank) { renderer.setRenderTarget(null); renderer.clear(); blank = true; }
    return;
  }
  blank = false;
  renderPass.scene = scene;
  renderPass.camera = camera;
  composer.render();
}

window.L.on(draw, { continuous: true });
window.L.glReady.resolve({ renderer, draw, composer, keys });
