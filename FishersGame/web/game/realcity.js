// Real 3D city: streams Google Photorealistic 3D Tiles for the map area and
// answers ground-height and wall questions by casting rays against them.
//
// The tiles arrive in Earth-centred (ECEF) coordinates. The game uses a local
// east/up/south frame at the map origin, so the tile group is given the matrix
// that maps ECEF into that frame. The map builder projects OpenStreetMap data
// into the same frame (see tools/build_map.py), so roads line up with the tiles.
import * as THREE from 'three';
import { TilesRenderer } from '3d-tiles-renderer';
import { GoogleCloudAuthPlugin, TileCompressionPlugin, TilesFadePlugin } from '3d-tiles-renderer/plugins';
import { computeBoundsTree, disposeBoundsTree, acceleratedRaycast } from 'three-mesh-bvh';

THREE.BufferGeometry.prototype.computeBoundsTree = computeBoundsTree;
THREE.BufferGeometry.prototype.disposeBoundsTree = disposeBoundsTree;
THREE.Mesh.prototype.raycast = acceleratedRaycast;

// WGS84
const A = 6378137, F_ = 1 / 298.257223563, E2 = F_ * (2 - F_);

export function ecef(latDeg, lonDeg, h) {
  const lat = THREE.MathUtils.degToRad(latDeg), lon = THREE.MathUtils.degToRad(lonDeg);
  const s = Math.sin(lat), c = Math.cos(lat);
  const N = A / Math.sqrt(1 - E2 * s * s);
  return new THREE.Vector3((N + h) * c * Math.cos(lon), (N + h) * c * Math.sin(lon), (N * (1 - E2) + h) * s);
}

// Matrix taking ECEF to the game frame: x = east, y = up, z = south, origin at (lat, lon, h).
export function ecefToLocal(latDeg, lonDeg, h) {
  const lat = THREE.MathUtils.degToRad(latDeg), lon = THREE.MathUtils.degToRad(lonDeg);
  const east = new THREE.Vector3(-Math.sin(lon), Math.cos(lon), 0);
  const north = new THREE.Vector3(-Math.sin(lat) * Math.cos(lon), -Math.sin(lat) * Math.sin(lon), Math.cos(lat));
  const up = new THREE.Vector3(Math.cos(lat) * Math.cos(lon), Math.cos(lat) * Math.sin(lon), Math.sin(lat));
  const o = ecef(latDeg, lonDeg, h);
  const m = new THREE.Matrix4().set(
    east.x, east.y, east.z, -east.dot(o),
    up.x, up.y, up.z, -up.dot(o),
    -north.x, -north.y, -north.z, north.dot(o),
    0, 0, 0, 1,
  );
  return m;
}

export class RealCity {
  // opts: { apiKey, origin: {lat, lon, h}, rootURL (testing only) }
  constructor(scene, camera, renderer, opts) {
    this.scene = scene; this.camera = camera; this.renderer = renderer;
    const tiles = new TilesRenderer(opts.rootURL || undefined);
    if (!opts.rootURL) {
      this.auth = new GoogleCloudAuthPlugin({ apiToken: opts.apiKey, autoRefreshToken: true });
      tiles.registerPlugin(this.auth);
    }
    tiles.registerPlugin(new TileCompressionPlugin());
    tiles.registerPlugin(new TilesFadePlugin());
    // sharper near the player than Google's recommended default of 40
    tiles.errorTarget = 16;
    tiles.setCamera(camera);
    tiles.setResolutionFromRenderer(camera, renderer);
    const g = tiles.group;
    g.matrixAutoUpdate = false;
    g.matrix.copy(ecefToLocal(opts.origin.lat, opts.origin.lon, opts.origin.h));
    g.matrixWorldNeedsUpdate = true;
    scene.add(g);
    this.tiles = tiles;
    this.materials = new Set();
    this.bvhQueue = [];
    this.loaded = 0;
    this.errors = [];
    this.dim = 1;
    tiles.addEventListener('load-model', ({ scene: model }) => {
      this.loaded++;
      model.traverse((o) => {
        if (!o.isMesh) return;
        o.castShadow = false; o.receiveShadow = false;
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) {
          if (!m) continue;
          m.userData.baseColor = m.color ? m.color.clone() : null;
          if (m.color) m.color.copy(m.userData.baseColor).multiplyScalar(this.dim);
          this.materials.add(m);
        }
        this.bvhQueue.push(o.geometry);
      });
    });
    tiles.addEventListener('dispose-model', ({ scene: model }) => {
      model.traverse((o) => {
        if (!o.isMesh) return;
        if (o.geometry.boundsTree) o.geometry.disposeBoundsTree();
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) this.materials.delete(m);
      });
    });
    tiles.addEventListener('load-error', (e) => {
      const msg = String(e.error?.message || e.error || 'load error');
      this.errors.push(msg);
      if (this.errors.length > 20) this.errors.shift();
    });
    this.ray = new THREE.Raycaster();
    this.ray.firstHitOnly = true;
    this.hits = [];
    this.v = new THREE.Vector3();
    this.d = new THREE.Vector3();
  }

  // Night dimming: the photo textures already contain daylight.
  setDim(f) {
    if (Math.abs(f - this.dim) < 0.01) return;
    this.dim = f;
    for (const m of this.materials) if (m.color && m.userData.baseColor) m.color.copy(m.userData.baseColor).multiplyScalar(f);
  }

  update() {
    // the tile group's world matrix must be current before tiles are picked,
    // including while loading when nothing has been rendered yet
    this.tiles.group.updateMatrixWorld(true);
    this.camera.updateMatrixWorld();
    this.tiles.setResolutionFromRenderer(this.camera, this.renderer);
    this.tiles.update();
    // build ray-acceleration trees a few at a time so loading never stalls a frame
    const t0 = performance.now();
    while (this.bvhQueue.length && performance.now() - t0 < 3) {
      const geo = this.bvhQueue.shift();
      if (!geo.boundsTree && geo.attributes.position) geo.computeBoundsTree();
    }
  }

  cast(ox, oy, oz, dx, dy, dz, far) {
    this.ray.set(this.v.set(ox, oy, oz), this.d.set(dx, dy, dz));
    this.ray.near = 0; this.ray.far = far;
    this.hits.length = 0;
    this.ray.intersectObject(this.tiles.group, true, this.hits);
    let best = null;
    for (const h of this.hits) if (!best || h.distance < best.distance) best = h;
    return best;
  }

  // Height of the first surface below (x, fromY, z), or null if no tile is loaded there.
  groundAt(x, z, fromY = 400) {
    const h = this.cast(x, fromY, z, 0, -1, 0, fromY + 600);
    return h ? h.point.y : null;
  }

  // Lowest surface under a point when dropping from high above: the street, not a roof or tree.
  lowestGroundAt(x, z) {
    this.ray.set(this.v.set(x, 600, z), this.d.set(0, -1, 0));
    this.ray.near = 0; this.ray.far = 1400;
    this.ray.firstHitOnly = false;
    this.hits.length = 0;
    this.ray.intersectObject(this.tiles.group, true, this.hits);
    this.ray.firstHitOnly = true;
    let low = null;
    for (const h of this.hits) if (low === null || h.point.y < low) low = h.point.y;
    return low;
  }

  // First steep surface (a wall, tree trunk, fence) along a horizontal ray. Returns {dist, nx, nz} or null.
  wall(x, y, z, dx, dz, far) {
    const h = this.cast(x, y, z, dx, 0, dz, far);
    if (!h || !h.face) return null;
    const n = h.face.normal.clone().transformDirection(h.object.matrixWorld);
    if (Math.abs(n.y) > 0.6) return null; // sloped ground, not a wall
    const L = Math.hypot(n.x, n.z) || 1;
    let nx = n.x / L, nz = n.z / L;
    if (nx * dx + nz * dz > 0) { nx = -nx; nz = -nz; }
    return { dist: h.distance, nx, nz };
  }

  // Text credits Google requires on screen while the tiles are shown.
  attributions() {
    if (!this.auth) return 'Test tiles';
    const list = [];
    this.auth.getAttributions(list);
    return list.filter((a) => a.type === 'string').map((a) => a.value).join(' ');
  }

  dispose() {
    this.scene.remove(this.tiles.group);
    this.tiles.dispose();
  }
}
