import * as THREE from "three";
import { toCreasedNormals } from "three/addons/utils/BufferGeometryUtils.js";

export const PITCH = 24;
export const DEPTH_MID = -4;

export function tileGeometry(polygons, cx, cy, width, height) {
  const rings = polygons.map((ring) => ring.map((p) => new THREE.Vector2(p[0] - cx, cy - p[1])));
  const shape = new THREE.Shape(rings[0]);
  shape.holes = rings.slice(1).map((ring) => new THREE.Path(ring));
  const outline = rings[0];
  const area = Math.abs(THREE.ShapeUtils.area(outline));
  const perimeter = outline.reduce((sum, p, i) => sum + p.distanceTo(outline[(i + 1) % outline.length]), 0);
  let bevel = Math.min(1.7, (area / perimeter) * 0.65);
  const points = outline.slice(0, -1);
  const winding = Math.sign(THREE.ShapeUtils.area(points));
  for (let i = 0; i < points.length; i++) {
    const point = points[i];
    const incoming = point.clone().sub(points[(i + points.length - 1) % points.length]).normalize();
    const outgoing = points[(i + 1) % points.length].clone().sub(point).normalize();
    const direction = new THREE.Vector2(-incoming.y - outgoing.y, incoming.x + outgoing.x)
      .multiplyScalar(winding / (1 + incoming.dot(outgoing)));
    direction.clampLength(0, Math.SQRT2);
    for (let j = 0; j < points.length; j++) {
      const edge = points[(j + 1) % points.length].clone().sub(points[j]);
      const start = points[j].clone().sub(point);
      const cross = direction.cross(edge);
      if (Math.abs(cross) < 1e-8) continue;
      const distance = start.cross(edge) / cross;
      const along = start.cross(direction) / cross;
      if (distance > 1e-5 && along >= 0 && along <= 1) bevel = Math.min(bevel, distance * 0.8);
    }
  }
  const extruded = new THREE.ExtrudeGeometry(shape, {
    depth: 8,
    bevelEnabled: true,
    bevelThickness: 1.7,
    bevelSize: bevel,
    bevelOffset: -bevel,
    bevelSegments: 6,
    steps: 1,
    curveSegments: 1,
  });
  const geometry = toCreasedNormals(extruded, Math.PI / 3);
  extruded.dispose();
  geometry.translate(0, 0, -8);
  geometry.clearGroups();
  const position = geometry.getAttribute("position");
  const uv = geometry.getAttribute("uv");
  for (let i = 0; i < position.count; i++) uv.setXY(i, position.getX(i) / width + 0.5, position.getY(i) / height + 0.5);
  return geometry;
}

export function squareGeometry() {
  const h = 11.8;
  return tileGeometry([[[-h, -h], [h, -h], [h, h], [-h, h], [-h, -h]]], 0, 0, 24, 24);
}

function chalkTextures() {
  const n = 256;
  const normals = new Uint8Array(n * n * 4);
  const rough = new Uint8Array(n * n * 4);
  const hash = (x, y) => {
    const s = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
    return s - Math.floor(s);
  };
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      const u = ((x + 0.5) / n - 0.5) * 2;
      const v = ((y + 0.5) / n - 0.5) * 2;
      const grain = (hash(x, y) - 0.5) * 0.035;
      const dx = -0.2 * u * (1 - v * v) + grain;
      const dy = -0.2 * v * (1 - u * u) + (hash(y + 17, x + 3) - 0.5) * 0.035;
      const nv = new THREE.Vector3(-dx, -dy, 1).normalize();
      const i = (y * n + x) * 4;
      normals.set([(nv.x * 0.5 + 0.5) * 255, (nv.y * 0.5 + 0.5) * 255, (nv.z * 0.5 + 0.5) * 255, 255], i);
      const r = 235 + hash(x * 0.5, y * 0.5) * 20;
      rough.set([r, r, r, 255], i);
    }
  }
  const normalMap = new THREE.DataTexture(normals, n, n);
  const roughnessMap = new THREE.DataTexture(rough, n, n);
  for (const tex of [normalMap, roughnessMap]) {
    tex.magFilter = THREE.LinearFilter;
    tex.minFilter = THREE.LinearMipmapLinearFilter;
    tex.generateMipmaps = true;
    tex.anisotropy = 8;
    tex.needsUpdate = true;
  }
  return { normalMap, roughnessMap };
}

export const COLORS = {
  ink: new THREE.Color("#0f0d0c"),
  chalk: new THREE.Color("#c6bbab"),
  body: new THREE.Color("#968a7b"),
  orange: new THREE.Color("#ef672e"),
};

export function tileMaterial({ instanced }) {
  const { normalMap, roughnessMap } = chalkTextures();
  const material = new THREE.MeshPhysicalMaterial({
    color: 0xffffff,
    roughness: 0.7,
    normalMap,
    normalScale: new THREE.Vector2(1, 1),
    roughnessMap,
    clearcoat: 0.12,
    clearcoatRoughness: 0.55,
    metalness: 0,
  });
  const body = COLORS.body;
  material.onBeforeCompile = (shader) => {
    const attrs = instanced
      ? "attribute vec3 aFront; attribute vec3 aBack;"
      : "uniform vec3 uFront; uniform vec3 uBack;";
    if (!instanced) {
      shader.uniforms.uFront = material.userData.uFront;
      shader.uniforms.uBack = material.userData.uBack;
    }
    shader.vertexShader = `${attrs}\nvarying vec3 vFaceColor; varying vec3 vBackColor; varying float vSide;\n${shader.vertexShader}`;
    shader.vertexShader = shader.vertexShader.replace(
      "#include <begin_vertex>",
      `#include <begin_vertex>
      vFaceColor = ${instanced ? "aFront" : "uFront"};
      vBackColor = ${instanced ? "aBack" : "uBack"};
      vSide = position.z > -0.5 ? 1.0 : (position.z < -7.5 ? -1.0 : 0.0);`,
    );
    shader.fragmentShader = `varying vec3 vFaceColor; varying vec3 vBackColor; varying float vSide;\n${shader.fragmentShader}`;
    shader.fragmentShader = shader.fragmentShader.replace(
      "#include <color_fragment>",
      `#include <color_fragment>
      vec3 bodyColor = vec3(${body.r.toFixed(4)}, ${body.g.toFixed(4)}, ${body.b.toFixed(4)});
      diffuseColor.rgb *= vSide > 0.5 ? vFaceColor : (vSide < -0.5 ? vBackColor : bodyColor);`,
    );
  };
  material.customProgramCacheKey = () => (instanced ? "tile-instanced" : "tile-single");
  if (!instanced) {
    material.userData.uFront = { value: new THREE.Color() };
    material.userData.uBack = { value: new THREE.Color() };
  }
  return material;
}
