import * as THREE from "three";
import { toCreasedNormals } from "three/addons/utils/BufferGeometryUtils.js";
import type { Tile } from "./tile-motion";

export function createTileGeometry(tile: Tile): THREE.BufferGeometry {
  const rings = tile.polygons.map((ring) =>
    ring.map((point) => new THREE.Vector2(point[0] - tile.x, tile.y - point[1])),
  );
  const shape = new THREE.Shape(rings[0]);
  shape.holes = rings.slice(1).map((ring) => new THREE.Path(ring));
  const outline = rings[0];
  const area = Math.abs(THREE.ShapeUtils.area(outline));
  const perimeter = outline.reduce(
    (length, point, index) => length + point.distanceTo(outline[(index + 1) % outline.length]),
    0,
  );
  let bevel = Math.min(1.7, area / perimeter * 0.65);
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
      if (distance > 1e-5 && along >= 0 && along <= 1)
        bevel = Math.min(bevel, distance * 0.8);
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
  for (let i = 0; i < position.count; i++)
    uv.setXY(i, position.getX(i) / tile.width + 0.5, position.getY(i) / tile.height + 0.5);
  return geometry;
}
