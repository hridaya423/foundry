import * as THREE from "three";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { squareGeometry, tileGeometry, tileMaterial } from "./tiles.js";
import { tilePose, wordmarkPose, wordmarkVisible, quatOf, PALETTE, WORDMARK, INFO, SWAP, LOOP_SWAP } from "./choreo.js";
import { camera as cameraAt, samplesAt, shutter, aperture, focusDepth } from "./camera.js";
import { clamp, hash, prog, inOutCubic, smooth } from "./ease.js";

const TM = window.TM;
const W = 1920, H = 1080;

export async function createScene(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false, preserveDrawingBuffer: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(1);
  renderer.setSize(W, H, false);
  renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
  renderer.toneMapping = THREE.NoToneMapping;
  renderer.autoClear = false;
  renderer.shadowMap.enabled = !new URLSearchParams(location.search).has("noshadow");
  renderer.shadowMap.type = THREE.PCFShadowMap;
  renderer.setClearColor(PALETTE.ink, 1);

  const scene = new THREE.Scene();
  scene.background = PALETTE.ink.clone();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  scene.environment = pmrem.fromScene(room, 0.04).texture;
  scene.environmentIntensity = 0.42;
  room.dispose();
  pmrem.dispose();

  const ambient = new THREE.AmbientLight(0xfff6ee, 0.72);
  scene.add(ambient);
  const key = new THREE.DirectionalLight(0xfff4e8, 3.3);
  key.castShadow = true;
  key.shadow.mapSize.set(4096, 4096);
  key.shadow.camera.near = 10;
  key.shadow.camera.far = 9000;
  key.shadow.normalBias = 0.35;
  key.shadow.bias = -0.0002;
  key.shadow.radius = 2.5;
  scene.add(key, key.target);
  const rim = new THREE.DirectionalLight(0xffd8c0, 0.35);
  rim.position.set(1600, -400, 900);
  scene.add(rim);

  const camera = new THREE.PerspectiveCamera(24, W / H, 4, 20000);

  const geometry = squareGeometry();
  const N = INFO.N;
  const front = new THREE.InstancedBufferAttribute(new Float32Array(N * 3), 3);
  const back = new THREE.InstancedBufferAttribute(new Float32Array(N * 3), 3);
  front.setUsage(THREE.DynamicDrawUsage);
  back.setUsage(THREE.DynamicDrawUsage);
  geometry.setAttribute("aFront", front);
  geometry.setAttribute("aBack", back);
  const material = tileMaterial({ instanced: true });
  const tiles = new THREE.InstancedMesh(geometry, material, N);
  tiles.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  tiles.frustumCulled = false;
  tiles.castShadow = true;
  tiles.receiveShadow = true;
  scene.add(tiles);

  const checkCols = INFO.COLS + 44, checkRows = INFO.ROWS + 34;
  const checkGeometry = squareGeometry();
  const cN = checkCols * checkRows;
  const cFront = new Float32Array(cN * 3);
  const checkMatrices = [];
  const m4 = new THREE.Matrix4();
  for (let r = 0; r < checkRows; r++) {
    for (let c = 0; c < checkCols; c++) {
      const k = r * checkCols + c;
      const col = (r + c) % 2 === 0 ? PALETTE.checkA : PALETTE.checkB;
      const v = 0.92 + 0.08 * hash(k, 90);
      cFront.set([col.r * v, col.g * v, col.b * v], k * 3);
      m4.makeTranslation((c - (checkCols - 1) / 2) * 24, ((checkRows - 1) / 2 - r) * 24, -240);
      checkMatrices.push(m4.clone());
    }
  }
  checkGeometry.setAttribute("aFront", new THREE.InstancedBufferAttribute(cFront, 3));
  checkGeometry.setAttribute("aBack", new THREE.InstancedBufferAttribute(cFront.slice(), 3));
  const checker = new THREE.InstancedMesh(checkGeometry, tileMaterial({ instanced: true }), cN);
  checkMatrices.forEach((m, k) => checker.setMatrixAt(k, m));
  checker.receiveShadow = true;
  checker.castShadow = false;
  checker.frustumCulled = false;
  scene.add(checker);

  const wordmark = WORDMARK.map((t) => {
    const g = tileGeometry(t.polygons, t.x, t.y, t.width, t.height);
    const m = tileMaterial({ instanced: false });
    const color = t.stop ? PALETTE.orange : PALETTE.chalk;
    m.userData.uFront.value.copy(color);
    m.userData.uBack.value.copy(color);
    const mesh = new THREE.Mesh(g, m);
    mesh.castShadow = mesh.receiveShadow = true;
    mesh.visible = false;
    mesh.matrixAutoUpdate = false;
    scene.add(mesh);
    return mesh;
  });

  const rtOpts = { type: THREE.HalfFloatType, colorSpace: THREE.LinearSRGBColorSpace, depthBuffer: true, samples: 4 };
  const sampleRT = new THREE.WebGLRenderTarget(W, H, rtOpts);
  const accumRT = new THREE.WebGLRenderTarget(W, H, { type: THREE.FloatType, depthBuffer: false });
  const quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const quadGeo = new THREE.PlaneGeometry(2, 2);
  const addMat = new THREE.ShaderMaterial({
    uniforms: { tSrc: { value: null }, uWeight: { value: 1 } },
    vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }",
    fragmentShader: "uniform sampler2D tSrc; uniform float uWeight; varying vec2 vUv; void main(){ gl_FragColor = vec4(texture2D(tSrc, vUv).rgb * uWeight, 1.0); }",
    blending: THREE.AdditiveBlending,
    depthTest: false,
    depthWrite: false,
    transparent: true,
  });
  const outMat = new THREE.ShaderMaterial({
    uniforms: { tSrc: { value: null }, uTime: { value: 0 }, uGrain: { value: 0.035 }, uVignette: { value: 0.16 }, uExposure: { value: Number(new URLSearchParams(location.search).get("exp") || 0.333) } },
    vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }",
    fragmentShader: `
      uniform sampler2D tSrc; uniform float uTime; uniform float uGrain; uniform float uVignette; uniform float uExposure; varying vec2 vUv;
      float h(vec2 p){ p = fract(p * vec2(443.897, 441.423)); p += dot(p, p.yx + 19.19); return fract((p.x + p.y) * p.x); }
      vec3 toSRGB(vec3 c){ c = max(c, 0.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0/2.4)) - 0.055, step(0.0031308, c)); }
      void main(){
        vec3 c = texture2D(tSrc, vUv).rgb * uExposure;
        vec2 pq = (vUv - vec2(0.42, 0.6)) * vec2(1.7777, 1.0);
        c *= mix(1.1, 0.72, smoothstep(0.15, 1.15, length(pq)));
        c = c / (1.0 + max(0.0, max(c.r, max(c.g, c.b)) - 0.9) * 0.7);
        vec2 q = vUv - 0.5; q.x *= 1.7777;
        float v = 1.0 - uVignette * smoothstep(0.35, 1.05, length(q));
        c *= v;
        vec3 s = toSRGB(c);
        s = mix(s, s * s * (3.0 - 2.0 * s), 0.22);
        float n = h(vUv * vec2(1920.0, 1080.0) + fract(uTime * 7.31) * 113.0) - 0.5;
        float luma = dot(s, vec3(0.2126, 0.7152, 0.0722));
        s += n * uGrain * (0.55 + 0.45 * (1.0 - luma));
        gl_FragColor = vec4(s, 1.0);
      }`,
    depthTest: false,
    depthWrite: false,
  });
  const quad = new THREE.Mesh(quadGeo, addMat);
  const quadScene = new THREE.Scene();
  quadScene.add(quad);

  const mat = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  const pos = new THREE.Vector3();
  const one = new THREE.Vector3(1, 1, 1);
  const zero = new THREE.Vector3(0, 0, 0);
  const wq = new THREE.Quaternion();
  const wp = new THREE.Vector3();
  const hookColor = INFO.wallColor(SWAP.hook);

  function pose(t) {
    for (let i = 0; i < N; i++) {
      const st = tilePose(i, t);
      if (st.hidden) {
        mat.compose(pos.set(0, -50000, 0), q.identity(), zero);
        tiles.setMatrixAt(i, mat);
        continue;
      }
      quatOf(st, q);
      pos.set(st.x, st.y, st.z);
      const pivot = -4;
      const off = new THREE.Vector3(0, 0, pivot).applyQuaternion(q);
      pos.x -= off.x;
      pos.y -= off.y;
      pos.z += pivot - off.z;
      mat.compose(pos, q, one);
      tiles.setMatrixAt(i, mat);
      const f = st.face || INFO.wallColor(i);
      const b = st.back || f;
      front.setXYZ(i, f.r, f.g, f.b);
      back.setXYZ(i, b.r, b.g, b.b);
    }
    tiles.instanceMatrix.needsUpdate = true;
    front.needsUpdate = true;
    back.needsUpdate = true;
    const show = wordmarkVisible(t);
    for (let k = 0; k < wordmark.length; k++) {
      const mesh = wordmark[k];
      if (!show || !wordmarkPose(k, t, wp, wq)) {
        mesh.visible = false;
        continue;
      }
      mesh.visible = true;
      mesh.matrix.compose(wp, wq, one);
      if (WORDMARK[k].stop) mesh.material.userData.uFront.value.copy(PALETTE.orange).lerp(hookColor, smooth(prog(t, LOOP_SWAP - 0.55, LOOP_SWAP - 0.04)));
    }
  }

  const right = new THREE.Vector3(), up = new THREE.Vector3(), fwd = new THREE.Vector3();
  function placeCamera(t, jx, jy, lens) {
    const c = cameraAt(t);
    camera.fov = c.fov;
    camera.position.set(c.px, c.py, c.pz);
    camera.up.set(Math.sin(c.roll), Math.cos(c.roll), 0);
    camera.lookAt(c.tx, c.ty, c.tz);
    camera.updateMatrixWorld();
    const A = aperture(t);
    let lx = 0, ly = 0;
    if (A > 0) {
      lx = lens[0] * A;
      ly = lens[1] * A;
      right.setFromMatrixColumn(camera.matrixWorld, 0);
      up.setFromMatrixColumn(camera.matrixWorld, 1);
      camera.position.addScaledVector(right, lx).addScaledVector(up, ly);
      camera.updateMatrixWorld();
    }
    camera.updateProjectionMatrix();
    const e = camera.projectionMatrix.elements;
    const F = c.dist - focusDepth(t);
    e[8] += (jx * 2) / W - (e[0] * lx) / F;
    e[9] += (jy * 2) / H - (e[5] * ly) / F;
    camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
    const kx = c.tx - 1300, ky = c.ty + 1050, kz = c.tz + 1900;
    key.position.set(kx, ky, kz);
    key.target.position.set(c.tx, c.ty, c.tz);
    key.target.updateMatrixWorld();
    const span = Math.max(900, c.dist * Math.tan((c.fov * Math.PI) / 360) * 2.4);
    const sc = key.shadow.camera;
    sc.left = -span * 1.2;
    sc.right = span * 1.2;
    sc.top = span;
    sc.bottom = -span;
    sc.updateProjectionMatrix();
    return c;
  }

  const halton = (i, b) => {
    let f = 1, r = 0;
    while (i > 0) {
      f /= b;
      r += f * (i % b);
      i = Math.floor(i / b);
    }
    return r;
  };

  function render(t) {
    const K = samplesAt(t);
    const sh = shutter(t);
    renderer.setRenderTarget(accumRT);
    renderer.setClearColor(0x000000, 1);
    renderer.clear();
    for (let s = 0; s < K; s++) {
      const ts = K === 1 ? t : t + ((s + 0.5) / K - 0.5) * sh;
      pose(ts);
      const jx = halton(s + 1, 2) - 0.5, jy = halton(s + 1, 3) - 0.5;
      const ga = s * 2.39996323, gr = Math.sqrt((s + 0.5) / K);
      placeCamera(ts, jx, jy, [Math.cos(ga) * gr, Math.sin(ga) * gr]);
      checker.position.z = 204 * inOutCubic(prog(ts, TM.drop + 0.9, TM.land[0] + 0.1)) * (ts < TM.loop[0] + 1.0 ? 1 : 0);
      renderer.setRenderTarget(sampleRT);
      renderer.setClearColor(PALETTE.ink, 1);
      renderer.clear();
      renderer.render(scene, camera);
      quad.material = addMat;
      addMat.uniforms.tSrc.value = sampleRT.texture;
      addMat.uniforms.uWeight.value = 1 / K;
      renderer.setRenderTarget(accumRT);
      renderer.render(quadScene, quadCam);
    }
    quad.material = outMat;
    outMat.uniforms.tSrc.value = accumRT.texture;
    outMat.uniforms.uTime.value = t;
    renderer.setRenderTarget(null);
    renderer.render(quadScene, quadCam);
  }

  return { render, renderer };
}
