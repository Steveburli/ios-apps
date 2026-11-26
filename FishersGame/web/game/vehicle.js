// Arcade car physics shared by the player's car, traffic and parked cars.
import { buildCar, CAR_TYPES, lightMats, pedal } from './models.js';
import { clamp, smooth, wrapAngle } from './util.js';

const tmp = { x: 0, z: 0, nx: 0, nz: 0, hit: false };

export class Car {
  // Set by the game when real 3D tiles are on: ground(x, z, fromY) = first surface
  // below fromY; floor(x, z) = lowest surface (street level). Both return null if unknown.
  static ground = null;
  static floor = null;

  constructor(scene, type, color, x, z, heading) {
    this.type = type;
    this.spec = CAR_TYPES[type];
    this.mesh = buildCar(type, color);
    this.color = color;
    scene.add(this.mesh);
    this.scene = scene;
    this.x = x; this.z = z; this.heading = heading;
    this.y = 0; this.slope = 0; this.settled = !Car.floor; this.followSlope = false;
    this.vx = 0; this.vz = 0; this.yawRate = 0;
    this.steer = 0; this.wheelSpin = 0;
    this.roll = 0; this.pitch = 0;
    this.driver = null; // 'player' | 'ai' | null
    this.input = { throttle: 0, brake: 0, steer: 0, handbrake: 0 };
    this.lastHit = 0; this.hitStrength = 0;
    this.radius = this.spec.bike ? 0.35 : this.spec.w * 0.52;
    this.mass = this.spec.bike ? 0.12 : this.type === 'bus' ? 3 : 1;
    this.crank = 0;
    this.halfLen = this.spec.l / 2;
    this.sync();
  }

  get fx() { return Math.sin(this.heading); }
  get fz() { return Math.cos(this.heading); }
  get speed() { return this.vx * this.fx + this.vz * this.fz; }
  get absSpeed() { return Math.hypot(this.vx, this.vz); }

  // Circle centres along the car's length, used for collisions.
  circles() {
    const n = this.spec.l > 6 ? 4 : 3;
    const out = [];
    const span = this.halfLen - this.radius * 0.9;
    for (let i = 0; i < n; i++) {
      const t = n === 1 ? 0 : -1 + (2 * i) / (n - 1);
      out.push([this.x + this.fx * span * t, this.z + this.fz * span * t]);
    }
    return out;
  }

  update(dt, world) {
    const s = this.spec, inp = this.input;
    const fx = this.fx, fz = this.fz, rx = fz, rz = -fx;
    let vF = this.vx * fx + this.vz * fz;
    let vR = this.vx * rx + this.vz * rz;
    // engine and brakes
    if (inp.throttle > 0) {
      if (vF < -0.5) vF += s.accel * 1.6 * inp.throttle * dt; // braking from reverse
      else vF += s.accel * inp.throttle * (1 - Math.max(0, vF) / s.maxSpeed) * dt * (vF < 8 ? 1.25 : 1);
    }
    if (inp.brake > 0) {
      if (vF > 0.5) vF -= s.accel * 2.0 * inp.brake * dt;
      else vF -= s.accel * 0.6 * inp.brake * (1 + vF / 12) * dt; // reverse, capped near -12 m/s
    }
    // rolling resistance and drag
    vF -= vF * (0.12 + Math.abs(vF) * 0.0045) * dt;
    if (!inp.throttle && !inp.brake) vF -= Math.sign(vF) * Math.min(Math.abs(vF), 1.8 * dt);
    if (inp.handbrake) vF -= Math.sign(vF) * Math.min(Math.abs(vF), 9 * dt);
    // lateral grip (lower with handbrake = drift)
    const grip = inp.handbrake ? 1.6 : s.grip;
    vR *= Math.exp(-grip * dt);
    // steering
    this.steer = smooth(this.steer, inp.steer, 9, dt);
    const speedFactor = 1 / (1 + Math.abs(vF) * 0.045);
    const wheelbase = s.l * 0.62;
    // +steer is a right turn; +heading turns left (toward +x when facing +z)
    let yaw = -(vF / wheelbase) * Math.tan(this.steer * s.steer * speedFactor);
    if (inp.handbrake) yaw *= 1.35;
    this.yawRate = smooth(this.yawRate, yaw, 12, dt);
    this.heading = wrapAngle(this.heading + this.yawRate * dt);
    const nfx = Math.sin(this.heading), nfz = Math.cos(this.heading);
    this.vx = nfx * vF + nfz * vR;
    this.vz = nfz * vF - nfx * vR;
    this.x += this.vx * dt;
    this.z += this.vz * dt;
    // world collisions
    if (world) this.collideWorld(world, dt);
    this.followGround();
    // body motion for looks
    const accelF = (vF - (this._lastVF ?? vF)) / Math.max(dt, 1e-3);
    this._lastVF = vF;
    this.pitch = smooth(this.pitch, clamp(-accelF * 0.004, -0.06, 0.06), 6, dt);
    this.roll = smooth(this.roll, clamp(-this.yawRate * vF * 0.004, -0.08, 0.08), 6, dt);
    this.wheelSpin += (vF / this.mesh.userData.wheelR) * dt;
    this.sync();
  }

  // Keeps the car on the real ground surface (no-op when there are no 3D tiles).
  followGround() {
    if (!Car.floor) return;
    if (!this.settled) {
      const y = Car.floor(this.x, this.z);
      if (y == null) return;
      this.y = y; this.settled = true;
      return;
    }
    const y = Car.ground(this.x, this.z, this.y + 1.8);
    if (y != null) this.y = y;
    if (this.followSlope) {
      const h = this.halfLen * 0.8;
      const yf = Car.ground(this.x + this.fx * h, this.z + this.fz * h, this.y + 1.8);
      const yb = Car.ground(this.x - this.fx * h, this.z - this.fz * h, this.y + 1.8);
      if (yf != null && yb != null) this.slope = clamp(Math.atan2(yf - yb, 2 * h), -0.35, 0.35);
    }
  }

  collideWorld(world, dt) {
    let hit = false, nx = 0, nz = 0;
    const cs = this.circles();
    for (const [cx, cz] of cs) {
      world.collide(cx, cz, this.radius, tmp);
      if (tmp.hit) {
        const dx = tmp.x - cx, dz = tmp.z - cz;
        this.x += dx; this.z += dz;
        nx += tmp.nx; nz += tmp.nz; hit = true;
      }
    }
    if (hit) {
      const L = Math.hypot(nx, nz) || 1;
      nx /= L; nz /= L;
      const vn = this.vx * nx + this.vz * nz;
      if (vn < 0) {
        this.vx -= vn * nx * 1.35; this.vz -= vn * nz * 1.35;
        this.vx *= 0.82; this.vz *= 0.82;
        this.hitStrength = Math.max(this.hitStrength, -vn);
        // spin a little on glancing hits
        const side = nx * Math.cos(this.heading) - nz * Math.sin(this.heading);
        this.yawRate += side * vn * 0.05;
      }
    }
  }

  sync() {
    const m = this.mesh;
    m.position.set(this.x, this.y, this.z);
    m.rotation.order = 'YXZ';
    m.rotation.set(-this.slope, this.heading, 0);
    const body = m.userData.body;
    if (this.spec.bike) {
      const vF = this.speed;
      const lean = m.userData.rider ? -clamp(this.yawRate * vF * 0.07, -0.5, 0.5) : 0.13; // parked on its kickstand
      body.rotation.set(0, 0, lean);
      this.crank += (vF / 0.34) * 0.016 * 0.45 * (this.input.throttle > 0 ? 1 : 0.15);
      pedal(m, this.crank);
    } else body.rotation.set(this.pitch, 0, this.roll);
    for (const w of m.userData.wheels) {
      w.pivot.rotation.y = w.front ? -this.steer * this.spec.steer * 0.8 : 0;
      w.tire.rotation.x = this.wheelSpin;
    }
  }

  setHeadlights(on) {
    this.mesh.userData.lights.material = on ? lightMats.on : lightMats.off;
  }

  remove() {
    this.scene.remove(this.mesh);
  }
}

// Resolves overlaps between two cars by pushing them apart and trading momentum.
export function carVsCar(a, b) {
  const ca = a.circles(), cb = b.circles();
  const rr = a.radius + b.radius;
  let hit = false, nx = 0, nz = 0, depth = 0;
  for (const p of ca) {
    for (const q of cb) {
      const dx = p[0] - q[0], dz = p[1] - q[1];
      const d2 = dx * dx + dz * dz;
      if (d2 < rr * rr && d2 > 1e-6) {
        const d = Math.sqrt(d2);
        nx += dx / d; nz += dz / d;
        depth = Math.max(depth, rr - d);
        hit = true;
      }
    }
  }
  if (!hit) return 0;
  const L = Math.hypot(nx, nz) || 1;
  nx /= L; nz /= L;
  const ma = a.mass ?? 1, mb = b.mass ?? 1;
  const ta = mb / (ma + mb), tb = ma / (ma + mb);
  a.x += nx * depth * ta; a.z += nz * depth * ta;
  b.x -= nx * depth * tb; b.z -= nz * depth * tb;
  const rvx = a.vx - b.vx, rvz = a.vz - b.vz;
  const vn = rvx * nx + rvz * nz;
  if (vn < 0) {
    const j = -1.25 * vn;
    a.vx += nx * j * ta; a.vz += nz * j * ta;
    b.vx -= nx * j * tb; b.vz -= nz * j * tb;
  }
  return -vn;
}
