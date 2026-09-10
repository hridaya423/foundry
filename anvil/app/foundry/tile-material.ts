import * as THREE from "three";

export function createChalkMaterial() {
  const resolution = 128;
  const surfaceNormals = new Uint8Array(resolution * resolution * 4);
  const roughness = new Uint8Array(resolution * resolution * 4);
  for (let y = 0; y < resolution; y++) {
    for (let x = 0; x < resolution; x++) {
      const u = ((x + 0.5) / resolution - 0.5) * 2;
      const v = ((y + 0.5) / resolution - 0.5) * 2;
      const dx = -0.2 * u * (1 - v * v);
      const dy = -0.2 * v * (1 - u * u);
      const normal = new THREE.Vector3(-dx, -dy, 1).normalize();
      const index = (y * resolution + x) * 4;
      surfaceNormals.set(
        [
          (normal.x * 0.5 + 0.5) * 255,
          (normal.y * 0.5 + 0.5) * 255,
          (normal.z * 0.5 + 0.5) * 255,
          255,
        ],
        index,
      );
      const grain = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
      const value = 235 + (grain - Math.floor(grain)) * 20;
      roughness.set([value, value, value, 255], index);
    }
  }
  const normalMap = new THREE.DataTexture(
    surfaceNormals,
    resolution,
    resolution,
  );
  const roughnessMap = new THREE.DataTexture(roughness, resolution, resolution);
  for (const texture of [normalMap, roughnessMap]) {
    texture.magFilter = THREE.LinearFilter;
    texture.minFilter = THREE.LinearMipmapLinearFilter;
    texture.generateMipmaps = true;
    texture.needsUpdate = true;
  }
  const material = new THREE.MeshPhysicalMaterial({
    vertexColors: true,
    roughness: 0.7,
    normalMap,
    normalScale: new THREE.Vector2(1, 1),
    roughnessMap,
    clearcoat: 0.12,
    clearcoatRoughness: 0.55,
    metalness: 0,
  });
  return { material, normalMap, roughnessMap };
}
