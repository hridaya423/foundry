import * as THREE from "three";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import { createTileGeometry } from "../tile-geometry";
import { createChalkMaterial } from "../tile-material";
import { createFlightPath, tilePose, type Tile } from "../tile-motion";
import { writeClipboardTilePose } from "./clipboard-motion";
import { downloadPoints, downloadStart, writeDownloadTilePose } from "./download-motion";
import { memoryStart, memoryTargets, memoryCarryCount, writeMemoryTilePose } from "./memory-motion";
import { toolTargets, toolTileCount, writeToolsTilePose } from "./tools-motion";
import { writeMediaTilePose } from "./media-motion";
import { createShelfTiles, phase, heroLift, introProgress, writePeelExitPose, writeShelfPose, type ShelfLayout, type ShelfPose } from "./shelf-motion";

export function createShelfScene(canvas: HTMLCanvasElement, tiles: Tile[]) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "low-power" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
  renderer.setClearColor(0x0f0d0c, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(0, 1280, 0, -720, 0.1, 4000);
  camera.position.z = 1800;
  const pmrem = new THREE.PMREMGenerator(renderer);
  const room = new RoomEnvironment();
  const environment = pmrem.fromScene(room, 0.04);
  scene.environment = environment.texture;
  scene.environmentIntensity = 0.35;
  room.dispose();
  pmrem.dispose();
  scene.add(new THREE.AmbientLight(0xffffff, 0.7));
  const key = new THREE.DirectionalLight(0xfffaf4, 2.2);
  key.position.set(-300, 500, 1600);
  key.target.position.set(640, -360, 0);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  key.shadow.camera.left = -1400;
  key.shadow.camera.right = 1400;
  key.shadow.camera.top = 1100;
  key.shadow.camera.bottom = -1100;
  key.shadow.camera.near = 10;
  key.shadow.camera.far = 4000;
  key.shadow.normalBias = 0.3;
  key.shadow.bias = -0.00015;
  key.shadow.radius = 3;
  scene.add(key, key.target);
  const { material, normalMap, roughnessMap } = createChalkMaterial();
  const tileMaterial = material.clone();
  tileMaterial.onBeforeCompile = (shader) => {
    shader.vertexShader = `attribute vec3 tileFace; varying vec3 vTileFace; varying float vFront;\n${shader.vertexShader}`;
    shader.vertexShader = shader.vertexShader.replace("#include <begin_vertex>", "#include <begin_vertex>\nvTileFace = tileFace; vFront = step(-0.5, position.z);");
    shader.fragmentShader = `varying vec3 vTileFace; varying float vFront;\n${shader.fragmentShader}`;
    shader.fragmentShader = shader.fragmentShader.replace("#include <color_fragment>", "diffuseColor.rgb *= mix(vColor.rgb, vTileFace, vFront);");
  };
  tileMaterial.customProgramCacheKey = () => "foundry-shelf-face";
  const chalk = new THREE.Color("#c6bbab");
  const side = new THREE.Color("#f36f39");
  const paint = (geometry: THREE.BufferGeometry, face: THREE.Color) => {
    const position = geometry.getAttribute("position");
    const colors = new Float32Array(position.count * 3);
    for (let i = 0; i < position.count; i++) {
      const color = position.getZ(i) > -0.5 ? face : side;
      colors.set([color.r, color.g, color.b], i * 3);
    }
    geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  };
  const square = createTileGeometry({
    id: "shelf-square", full: true, row: 0, column: 0,
    x: 0, y: 0, width: 24, height: 24,
    polygons: [[[-12, -12], [12, -12], [12, 12], [-12, 12], [-12, -12]]],
  });
  paint(square, chalk);
  const inventory = createShelfTiles(tiles);
  const backgroundIndices = inventory.flatMap(({ cell }, index) => cell.kind === "image" && !cell.subject ? [index] : []);
  const carried = Array.from({ length: 48 }, (_, index) => backgroundIndices[Math.floor(index * backgroundIndices.length / 48)]);
  const ribbonIndices = inventory.map((_, index) => carried.indexOf(index));
  const toolsCarry = carried;
  const toolsOrder = [...toolsCarry, ...inventory.map((_, index) => index).filter(index => !toolsCarry.includes(index))];
  const toolsIndices = inventory.map((_, index) => toolsOrder.indexOf(index));
  const capacity = Math.max(inventory.length, toolTileCount, memoryCarryCount);
  const faceColors = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 3), 3);
  faceColors.setUsage(THREE.DynamicDrawUsage);
  square.setAttribute("tileFace", faceColors);
  const instances = new THREE.InstancedMesh(square, tileMaterial, capacity);
  instances.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  instances.frustumCulled = false;
  instances.castShadow = true;
  instances.receiveShadow = true;
  scene.add(instances);
  const partials = new THREE.Group();
  const parts: THREE.BufferGeometry[] = [];
  const loose: { tile: Tile; mesh: THREE.Mesh }[] = [];
  const geometries: THREE.BufferGeometry[] = [square];
  for (const tile of tiles.filter((item) => !item.full)) {
    const geometry = createTileGeometry(tile);
    const face = chalk.clone().multiplyScalar((1.04 - tile.x / 1672 * 0.32) * (0.99 + Math.sin(tile.x * 0.8 + tile.y * 0.7) * 0.01));
    paint(geometry, face);
    if (tile.order !== undefined) {
      const mesh = new THREE.Mesh(geometry, material);
      mesh.castShadow = mesh.receiveShadow = true;
      scene.add(mesh);
      loose.push({ tile, mesh });
      geometries.push(geometry);
    } else {
      geometry.translate(tile.x, -tile.y, 0);
      parts.push(geometry);
    }
  }
  const merged = mergeGeometries(parts);
  parts.forEach((geometry) => geometry.dispose());
  if (merged) {
    geometries.push(merged);
    const contours = new THREE.Mesh(merged, material);
    contours.castShadow = contours.receiveShadow = true;
    partials.add(contours);
  }
  scene.add(partials);
  const planeGeometry = new THREE.PlaneGeometry(1, 1);
  const planeMaterial = new THREE.ShadowMaterial({ opacity: 0.12 });
  const plane = new THREE.Mesh(planeGeometry, planeMaterial);
  plane.receiveShadow = true;
  plane.position.z = -12;
  scene.add(plane);
  const object = new THREE.Object3D();
  const face = new THREE.Color();
  const toolFace = new THREE.Color();
  const colors = inventory.map((entry) => new THREE.Color(entry.cell.color));
  const sourceColors = inventory.map(({ tile }) => chalk.clone().multiplyScalar((1.04 - tile.x / 1672 * 0.32) * (0.99 + Math.sin(tile.x * 0.8 + tile.y * 0.7) * 0.01)));
  const pose: ShelfPose = { x: 0, y: 0, z: 0, rx: 0, ry: 0, rz: 0, sx: 1, sy: 1, color: 0 };
  let path = createFlightPath({ paletteX: 966, paletteY: 572 }, tiles);
  let layout: ShelfLayout;
  let draws = 0;
  let toolPoints: ReturnType<typeof toolTargets>[];
  let memoryPoints: ReturnType<typeof memoryTargets>;
  const orange = new THREE.Color("#ef672e");
  let closingPoints: ReturnType<typeof downloadPoints> = [];

  return {
    resize(next: ShelfLayout) {
      layout = next;
      closingPoints = downloadPoints(next.width, next.height);
      renderer.setSize(next.width, next.height, false);
      camera.right = next.width;
      camera.bottom = -next.height;
      camera.updateProjectionMatrix();
      toolPoints = Array.from({ length: 6 }, (_, index) => toolTargets(next.width, next.height, index));
      memoryPoints = memoryTargets(next.width, next.height);
      const scale = next.wordmark.width / 1672;
      path = createFlightPath({
        paletteX: (next.palette.x - next.wordmark.x) / scale,
        paletteY: (next.palette.y - next.wordmark.y) / scale,
      }, tiles);
      plane.scale.set(next.width * 1.5, next.height * 1.5, 1);
      plane.position.set(next.width / 2, -next.height / 2, -12);
    },
    render(progress: number, clipboardFocus: number, mediaPortrait: number, toolSelection: number, toolReveal: number, toolTransition: number) {
      const intro = introProgress(progress);
      const scale = layout.wordmark.width / 1672;
      const lift = heroLift(progress, layout.height);
      for (let index = 0; index < capacity; index++) {
        const original = index < inventory.length;
        const sourceIndex = index % inventory.length;
        const entry = inventory[sourceIndex];
        const source = tilePose(entry.tile, intro, path);
        writeShelfPose(pose, entry, source, Math.min(progress, ribbonIndices[sourceIndex] >= 0 ? 0.875 : 1), layout);
        writeClipboardTilePose(pose, ribbonIndices[sourceIndex], Math.min(progress, 1.9), layout, clipboardFocus);
        writeMediaTilePose(pose, ribbonIndices[sourceIndex], Math.min(progress, 1.9), layout, mediaPortrait);
        if (!original) pose.sx = pose.sy = 0;
        const toolIndex = original ? toolsIndices[index] : index;
        writeToolsTilePose(pose, toolIndex, Math.min(progress, memoryStart), layout, toolSelection, toolReveal, toolPoints[toolSelection], toolSelection > 0 ? toolPoints[toolSelection - 1] : toolPoints[toolSelection], toolTransition);
        writeMemoryTilePose(pose, index, Math.min(progress, downloadStart), layout, memoryPoints);
        writeDownloadTilePose(pose, index, progress, layout, closingPoints);
        object.position.set(pose.x, -pose.y, pose.z);
        object.rotation.set(pose.rx, pose.ry, -pose.rz);
        object.scale.set(pose.sx, pose.sy, Math.min(pose.sx, pose.sy));
        object.updateMatrix();
        instances.setMatrixAt(index, object.matrix);
        face.copy(sourceColors[sourceIndex]).lerp(colors[sourceIndex], pose.color);
        if (progress > 1.9) face.lerp(toolFace.copy(chalk).lerp(orange, pose.color), phase(progress, 1.9, 2.14));
        if (progress > memoryStart) face.lerp(memoryPoints[index]?.accent ? orange : chalk, phase(progress, memoryStart, memoryStart + .18));
        if (progress > downloadStart) face.lerp(chalk, phase(progress, downloadStart, downloadStart + .2));
        faceColors.setXYZ(index, face.r, face.g, face.b);
      }
      instances.instanceMatrix.needsUpdate = true;
      faceColors.needsUpdate = true;
      partials.position.set(layout.wordmark.x, -layout.wordmark.y + lift, 0);
      partials.scale.setScalar(scale);
      partials.visible = progress < 0.44;
      for (const { tile, mesh } of loose) {
        mesh.visible = progress < 0.59;
        if (!mesh.visible) continue;
        writePeelExitPose(pose, tile, tilePose(tile, intro, path), progress, layout);
        mesh.position.set(pose.x, -pose.y, pose.z);
        mesh.rotation.set(pose.rx, pose.ry, -pose.rz);
        mesh.scale.set(pose.sx * 24 / tile.width, pose.sy * 24 / tile.height, Math.min(pose.sx, pose.sy));
      }
      plane.visible = progress < 1.96;
      renderer.render(scene, camera);
      canvas.dataset.progress = progress.toFixed(4);
      canvas.dataset.drawCalls = String(renderer.info.render.calls);
      canvas.dataset.triangles = String(renderer.info.render.triangles);
      canvas.dataset.frames = String(++draws);
      canvas.dataset.tiles = String(capacity);
    },
    dispose() {
      geometries.forEach((geometry) => geometry.dispose());
      instances.dispose();
      material.dispose();
      tileMaterial.dispose();
      normalMap.dispose();
      roughnessMap.dispose();
      planeGeometry.dispose();
      planeMaterial.dispose();
      environment.dispose();
      key.shadow.dispose();
      renderer.dispose();
    },
  };
}
