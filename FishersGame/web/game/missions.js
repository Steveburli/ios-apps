// Story missions, mission givers and the golden-fish collectibles.
import * as THREE from 'three';
import { textSprite } from './models.js';
import { isDrivable, isTrafficRoad, isTrail, F } from './world.js';
import { mulberry32 } from './util.js';
import { lonLatToXZ } from './data.js';

class Fail extends Error {}

// Landmarks looked up by name in the map's points of interest, with a fallback position.
const LANDMARKS = {
  cityHall: { names: ['Fishers City Hall', 'Fishers Municipal Center'], fb: [39.9568, -86.0137], label: 'Fishers City Hall' },
  nickelPlate: { names: ['Nickel Plate District Amphitheater', 'Nickel Plate District Amphitheatre', 'Nickel Plate Amphitheater', 'Fishers Amphitheater'], fb: [39.9563, -86.0126], label: 'Nickel Plate District' },
  library: { names: ['Fishers Public Library', 'Fishers Branch', 'Hamilton East Public Library'], fb: [39.9578, -86.0110], label: 'Fishers Library' },
  connerPrairie: { names: ['Conner Prairie'], fb: [39.9830, -86.0277], label: 'Conner Prairie' },
  topgolf: { names: ['Topgolf'], fb: [39.9606, -85.9658], label: 'Topgolf' },
  geist: { names: ['Geist Reservoir', 'Geist Lake'], fb: [39.9330, -85.9600], label: 'Geist Reservoir' },
  noblesville: { names: ['Hamilton County Courthouse', 'Hamilton County Judicial Center', 'Noblesville Courthouse Square'], fb: [40.0457, -86.0087], label: 'Noblesville Square' },
  htc: { names: ['Hamilton Town Center'], fb: [40.0170, -85.9660], label: 'Hamilton Town Center' },
  ruoff: { names: ['Ruoff Music Center', 'Ruoff Home Mortgage Music Center', 'Deer Creek Music Center', 'Klipsch Music Center'], fb: [39.9993, -85.9471], label: 'Ruoff Music Center' },
  carmelArts: { names: ['Carmel Arts & Design District', 'Arts & Design District', 'Carmel Arts and Design District'], fb: [39.9785, -86.1282], label: 'Carmel Arts District' },
  palladium: { names: ['The Palladium', 'Palladium', 'Center for the Performing Arts'], fb: [39.9689, -86.1486], label: 'The Palladium' },
  fishersHS: { names: ['Fishers High School'], fb: [39.9937, -85.9631], label: 'Fishers High School' },
  ritchey: { names: ['Ritchey Woods', 'Ritchey Woods Nature Preserve'], fb: [39.9465, -86.0428], label: 'Ritchey Woods' },
  saxony: { names: ['Saxony Beach', 'Saxony'], fb: [40.0022, -85.9589], label: 'Saxony' },
  ikea: { names: ['IKEA'], fb: [39.9599, -85.9628], label: 'IKEA' },
  heritage: { names: ['Heritage Park at White River', 'Heritage Park'], fb: [39.9709, -86.0367], label: 'Heritage Park' },
  cumberland: { names: ['Cumberland Park'], fb: [39.9694, -85.9982], label: 'Cumberland Park' },
};

const look = (o) => o;

export class Missions {
  constructor(game) {
    this.g = game;
    this.waiters = [];
    this.active = null;
    this.spawned = [];
    this.markers = [];
    this.L = this.resolveLandmarks();
    this.defs = this.buildDefs();
    this.givers = [];
    this.fish = this.makeFish();
    this.flash = 0;
    this.placeGivers();
  }

  // ---------------------------------------------------------------- places
  resolveLandmarks() {
    const g = this.g, pois = g.world.meta.pois;
    const out = {};
    for (const [key, lm] of Object.entries(LANDMARKS)) {
      const fb = lonLatToXZ(g.world.meta, lm.fb[0], lm.fb[1]);
      let best = null, bs = -1;
      for (const p of pois) {
        const nm = p[0].toLowerCase();
        for (let i = 0; i < lm.names.length; i++) {
          const want = lm.names[i].toLowerCase();
          let score = 0;
          if (nm === want) score = 100 - i;
          else if (nm.startsWith(want)) score = 60 - i;
          if (!score) continue;
          // prefer the match closest to where we expect it
          const d = Math.hypot(p[2] - fb.x, p[3] - fb.z);
          score -= d / 400;
          if (score > bs) { bs = score; best = p; }
        }
      }
      const x = best ? best[2] : fb.x, z = best ? best[3] : fb.z;
      out[key] = { x, z, name: best ? best[0] : lm.label, label: lm.label };
    }
    return out;
  }

  findPOI(test, near, maxD = 6000) {
    let best = null, bd = maxD;
    for (const p of this.g.world.meta.pois) {
      if (!test(p[0], p[1])) continue;
      const d = Math.hypot(p[2] - near.x, p[3] - near.z);
      if (d < bd) { bd = d; best = { name: p[0], x: p[2], z: p[3] }; }
    }
    return best;
  }

  // Road-side point near (x,z) that a car can reach.
  spot(p, filter = isTrafficRoad, max = 300) {
    const hit = this.g.world.nearestRoad(p.x, p.z, filter, max) || this.g.world.nearestRoad(p.x, p.z, isDrivable, 800);
    if (!hit) return { x: p.x, z: p.z, road: '' };
    const c = this.g.nav.curbside(hit, 2.2);
    return { x: c.x, z: c.z, rx: hit.x, rz: hit.z, dx: hit.dx, dz: hit.dz, road: this.g.world.roadName(hit.edge) };
  }

  randomHouseSpot(near, minD, maxD, rnd = Math.random) {
    const filter = (t, f) => (t === 11 || t === 13) && !(f & F.DRIVEWAY);
    for (let i = 0; i < 30; i++) {
      const hit = this.g.nav.randomRoadSpot(near.x, near.z, minD, maxD, rnd, filter);
      if (!hit) continue;
      const c = this.g.nav.curbside(hit, 2.2);
      return { x: c.x, z: c.z, road: this.g.world.roadName(hit.edge) || 'a quiet street' };
    }
    return this.spot({ x: near.x + minD, z: near.z });
  }

  roundabouts(near, maxD) {
    const R = this.g.world.R, w = this.g.world;
    const pts = [];
    for (let e = 0; e < R.nEdges; e++) {
      if (!(R.flags[e] & F.ROUNDABOUT)) continue;
      const [x, z] = w.edgePoint(e, Math.floor(R.count[e] / 2));
      if (Math.hypot(x - near.x, z - near.z) > maxD) continue;
      pts.push([x, z]);
    }
    const centers = [];
    for (const [x, z] of pts) {
      const c = centers.find((c) => Math.hypot(c.sx / c.n - x, c.sz / c.n - z) < 70);
      if (c) { c.sx += x; c.sz += z; c.n++; } else centers.push({ sx: x, sz: z, n: 1 });
    }
    return centers.map((c) => ({ x: c.sx / c.n, z: c.sz / c.n }));
  }

  // ---------------------------------------------------------------- mission defs
  buildDefs() {
    const L = this.L, home = this.g.home;
    const grocery = this.findPOI((n, k) => k === 'shop=supermarket', home) || { name: 'the grocery store', ...L.cityHall };
    const pizza = this.findPOI((n, k) => /pizza/i.test(n) && /amenity=(restaurant|fast_food)/.test(k), L.cityHall) || { name: 'the pizza place', ...L.nickelPlate };
    const school = this.findPOI((n, k) => k === 'amenity=school' && /elementary/i.test(n), L.cityHall) || { name: 'the elementary school', ...L.fishersHS };
    const park = this.findPOI((n, k) => k === 'leisure=park', L.cityHall, 3000) || L.cumberland;
    const self = this;
    // A timed ride along one of the trails, giver standing at a trailside spot near `near`.
    const trailRide = (id, title, trailLabel, near, giverName, giverLook, pay, lines) => {
      const trail = (self.g.trails || []).find((t) => t.label === trailLabel);
      if (!trail) return null;
      const start = closest(trail.pts, near);
      return {
        id, title, pay, giver: { name: giverName, at: { x: start.x, z: start.z }, look: giverLook, onTrail: true },
        async run(m) {
          await m.say(lines.map((t) => [giverName, t]));
          if (!self.g.car?.spec.bike) {
            const rack = closest(trail.racks.length ? trail.racks : [start], self.g.pos);
            m.objective('Hop on a bike. There is a rack along the trail.');
            m.mark([rack], false);
            await m.until(() => self.g.car?.spec.bike);
          }
          // follow the trail ~3 km in whichever direction has more of it, using bike routing
          const pts = trail.pts;
          const here = self.g.pos;
          const i0 = pts.indexOf(closest(pts, here));
          const dir = i0 < pts.length / 2 ? 1 : -1;
          let end = pts[i0];
          for (let i = i0; i >= 0 && i < pts.length; i += dir) {
            end = pts[i];
            if (Math.hypot(end.x - here.x, end.z - here.z) > 3000) break;
          }
          const route = self.g.nav.route(here.x, here.z, end.x, end.z, true);
          const cps = [];
          let total = 0;
          if (route) {
            let run = 0;
            const rp = route.pts;
            for (let i = 2; i < rp.length && cps.length < 7; i += 2) {
              const d = Math.hypot(rp[i] - rp[i - 2], rp[i + 1] - rp[i - 1]);
              run += d; total += d;
              if (run > 550) { cps.push({ x: rp[i], z: rp[i + 1] }); run = 0; }
            }
          }
          if (cps.length < 2) throw new Fail('This stretch of trail is too short. Try again from the middle.');
          m.timer(Math.round(total / 6 + 40));
          for (let i = 0; i < cps.length; i++) {
            await m.goto(cps[i], { text: `${trailLabel} checkpoint ${i + 1} of ${cps.length}. Stay on the trail!`, bike: true, radius: 10, next: cps[i + 1] });
            self.g.sound.checkpoint();
          }
          m.bonus(Math.round(m.timeLeft()) * 2, 'Speedy pedaling');
          await m.say([[giverName, 'Look at you go! Same time next week?']]);
        },
      };
    };
    const rides = [
      trailRide('nickelride', 'Nickel Plate Pedal', 'Nickel Plate Trail', L.nickelPlate, 'Coach Rosa',
        look({ shirt: 0xf2c037, cap: 0xf2f2f2, hair: 0x2a1c12 }), 350,
        ['The Nickel Plate Trail used to be a railroad. Now it is the best ride in Fishers.',
          'Grab a bike and hit every checkpoint before the clock runs out. Ring your bell at the walkers!']),
      trailRide('mononride', 'Monon Mileage', 'Monon Trail', L.carmelArts, 'Dev',
        look({ shirt: 0x2bb3b1, cap: 0x2b2f36 }), 400,
        ['The Monon runs all the way from Indy up through Carmel. I ride it every morning.',
          'Think you can keep up? Bike to every checkpoint before time runs out.']),
    ].filter(Boolean);
    return [...rides,
      {
        id: 'welcome', title: 'Welcome to Fishers', pay: 150, giver: { name: 'Mom', at: home, look: look({ shirt: 0x2bb3b1, longHair: true, hair: 0x5a3a22 }) }, first: true,
        async run(m) {
          await m.say([
            ['Mom', 'Moving day is done! Welcome to your new house in Fishers.'],
            ['Mom', 'Grandma is coming over tonight and the fridge is empty.'],
            ['Mom', `Take the minivan in the driveway and grab a cake from ${grocery.name}. Then pick up my books on hold at the library.`],
          ]);
          const van = self.g.familyCar;
          m.objective('Get in the family minivan.');
          m.mark([{ x: van.x, z: van.z }], false);
          self.g.hud.toast('Walk up to the minivan and press E to get in');
          await m.until(() => self.g.car === van);
          self.g.hud.toast('W/S drive, A/D steer, Space handbrake. Follow the pink GPS line.');
          const g1 = self.spot(grocery);
          await m.goto(g1, { text: `Drive to ${grocery.name} and stop out front.`, car: true, stop: true });
          await m.say([['Bakery clerk', 'One chocolate cake with sprinkles, extra frosting. Drive gently!']]);
          const lib = self.spot(L.library);
          await m.goto(lib, { text: 'Pick up the books at the Fishers library.', car: true, stop: true });
          await m.say([['Librarian', 'Three mystery novels and a book about the history of Fishers. Enjoy!']]);
          await m.goto(self.spot(home), { text: 'Head home.', stop: true });
          await m.say([
            ['Mom', 'Perfect, Grandma is going to love this. Thank you!'],
            ['Mom', 'Go explore. Lots of people around town could use a hand. Look for the yellow ! on your map (press M).'],
          ]);
        },
      },
      {
        id: 'pizza', title: 'Pizza Rush', pay: 300, giver: { name: 'Tony', at: pizza, look: look({ shirt: 0xf2f2f2, cap: 0xd94848 }) },
        async run(m) {
          await m.say([
            ['Tony', `Our delivery driver called in sick and three pizzas are going cold here at ${pizza.name}.`],
            ['Tony', 'Take the delivery car out front. Each delivery buys you another minute. Go, go, go!'],
          ]);
          const s = self.spot(pizza);
          const car = m.car('hatch', s, 0xd94848);
          if (!self.g.car) {
            m.objective('Get in the red delivery car.');
            m.mark([{ x: car.x, z: car.z }], false);
            await m.until(() => self.g.car);
          }
          m.timer(150);
          for (let i = 1; i <= 3; i++) {
            const d = self.randomHouseSpot(self.g.pos, 450, 1300);
            await m.goto(d, { text: `Deliver pizza ${i} of 3 to a house on ${d.road}.`, car: true, stop: true, radius: 10 });
            self.g.sound.coin();
            self.g.hud.toast(['"Pizza night! You are a hero."', '"Still hot! Here is a tip."', '"Extra pepperoni, perfect!"'][i - 1]);
            m.addTime(60);
          }
          m.bonus(Math.round(m.timeLeft()) * 2, 'Speed tip');
        },
      },
      {
        id: 'fieldtrip', title: 'Field Trip', pay: 400, giver: { name: 'Ms. Alvarez', at: school, look: look({ shirt: 0x8d5bc2, longHair: true, hair: 0x2a1c12 }) },
        async run(m) {
          await m.say([
            ['Ms. Alvarez', `Our bus driver is stuck in traffic and the class is waiting here at ${school.name}.`],
            ['Ms. Alvarez', 'Could you drive us to Conner Prairie? Gently, please. If the bus bumps into things more than five times the kids get carsick.'],
          ]);
          const s = self.spot(school);
          const bus = m.car('bus', s, 0xf2b705);
          m.objective('Get in the school bus.');
          m.mark([{ x: bus.x, z: bus.z }], false);
          await m.until(() => self.g.car === bus);
          const route = self.g.nav.route(bus.x, bus.z, L.connerPrairie.x, L.connerPrairie.z);
          m.timer(Math.round((route ? route.length : 4000) / 11 + 60));
          let bumps = 0;
          m.onBump = (s2) => {
            if (self.g.car !== bus || s2 < 4) return;
            bumps++;
            self.g.hud.toast(bumps > 5 ? 'The kids are carsick!' : `"Whoa!" Bumps: ${bumps} of 5`, 'warn');
          };
          m.failIf(() => bumps > 5, 'The kids got carsick.');
          m.failIf(() => self.g.car !== bus && Math.hypot(self.g.pos.x - bus.x, self.g.pos.z - bus.z) > 150, 'You left the bus behind.');
          await m.goto(self.spot(L.connerPrairie), { text: 'Drive the class to Conner Prairie.', car: true, stop: true, radius: 14 });
          await m.say([['Ms. Alvarez', 'Everyone off the bus! Say thank you, class!'], ['Kids', 'THANK YOUUU!']]);
          m.bonus((5 - bumps) * 30, 'Smooth driving');
        },
      },
      {
        id: 'ducks', title: 'Lost Ducklings', pay: 250, giver: { name: 'Ranger Pat', at: L.geist, look: look({ shirt: 0x4b5d3a, cap: 0x6b5b45 }) },
        async run(m) {
          await m.say([
            ['Ranger Pat', 'A mama duck lost her eight ducklings around here. They waddled off in every direction.'],
            ['Ranger Pat', 'Find them before dark! Get close to each one to scoop it up.'],
          ]);
          const c = self.g.pos;
          const rnd = mulberry32(Date.now() & 0xffff);
          const spots = [];
          for (let i = 0; spots.length < 8 && i < 400; i++) {
            const a = rnd() * Math.PI * 2, d = 40 + rnd() * 260;
            const x = c.x + Math.cos(a) * d, z = c.z + Math.sin(a) * d;
            if (self.g.world.inWater(x, z) || self.g.world.buildingAt(x, z, 1) >= 0) continue;
            if (spots.some((s) => Math.hypot(s.x - x, s.z - z) < 30)) continue;
            spots.push({ x, z });
          }
          m.timer(240);
          await m.collect(spots, 'duck', (n, t) => `Find the ducklings: ${n} of ${t}.`);
          await m.goto(self.spot(L.geist), { text: 'Bring the ducklings back to Ranger Pat.', radius: 12 });
          await m.say([['Ranger Pat', 'All eight! Mama duck says quack. That means thank you.']]);
        },
      },
      {
        id: 'grandtour', title: 'Grand Tour', pay: 500, giver: { name: 'Coach Kim', at: L.fishersHS, look: look({ shirt: 0xd94848, cap: 0x1f2b3d }) },
        async run(m) {
          await m.say([
            ['Coach Kim', 'Think you know Hamilton County? Prove it.'],
            ['Coach Kim', 'Hit Noblesville Square, Hamilton Town Center and Ruoff Music Center, then come back here. Beat the clock and there is a sports car in it for you.'],
          ]);
          if (!self.g.car) {
            m.objective('Get in any car.');
            await m.until(() => self.g.car);
          }
          const legs = [L.noblesville, L.htc, L.ruoff, L.fishersHS].map((p) => self.spot(p));
          let dist = 0, prev = self.g.pos;
          for (const p of legs) { dist += Math.hypot(p.x - prev.x, p.z - prev.z) * 1.3; prev = p; }
          m.timer(Math.round(dist / 15 + 60));
          const names = ['Noblesville Square', 'Hamilton Town Center', 'Ruoff Music Center', 'Fishers High School'];
          for (let i = 0; i < legs.length; i++) {
            await m.goto(legs[i], { text: `Checkpoint ${i + 1} of 4: ${names[i]}.`, car: true, radius: 18, next: legs[i + 1] });
            self.g.sound.checkpoint();
          }
          self.g.save.sports = true;
          await m.say([['Coach Kim', 'Now THAT is local knowledge. The sports car is parked at your house. Enjoy!']]);
          self.g.spawnHomeCars();
        },
      },
      {
        id: 'teetime', title: 'Tee Time', pay: 300, giver: { name: 'Grandpa Joe', at: L.carmelArts, look: look({ shirt: 0x3b9c5a, hair: 0x8a8a8a, cap: 0xf2f2f2 }) },
        async run(m) {
          await m.say([
            ['Grandpa Joe', 'I lost track of time looking at the sculptures. My tee time at Topgolf is soon!'],
            ['Grandpa Joe', 'Pull a car up next to me and I will hop in.'],
          ]);
          const gp = m.npcFromGiver();
          if (!self.g.car) { m.objective('Get a car.'); await m.until(() => self.g.car); }
          await m.goto({ x: gp.x, z: gp.z }, { text: 'Pull up next to Grandpa Joe.', car: true, stop: true, radius: 9 });
          m.boardPassenger(gp);
          const route = self.g.nav.route(self.g.pos.x, self.g.pos.z, L.topgolf.x, L.topgolf.z);
          m.timer(Math.round((route ? route.length : 6000) / 14 + 50));
          m.chatter(['Grandpa Joe', [
            'Back in my day 116th Street was all cornfields.', 'Is it me, or is everyone driving a minivan?',
            'Watch for the roundabout! They love those around here.', 'I am going to hit the target in the back. You watch.',
          ]]);
          await m.goto(self.spot(L.topgolf), { text: 'Get Grandpa Joe to Topgolf.', car: true, stop: true, radius: 14 });
          m.dropPassenger();
          await m.say([['Grandpa Joe', 'Made it with time to spare. You are my favorite grandkid. Do not tell the others.']]);
        },
      },
      {
        id: 'roundabouts', title: 'Roundabout Rally', pay: 450, giver: { name: 'Rally Rita', at: L.palladium, look: look({ shirt: 0x2b2f36, longHair: true, hair: 0xd9b26b }) },
        async run(m) {
          const all = self.roundabouts(L.palladium, 3500);
          const chain = [];
          let cur = self.g.pos;
          const pool = all.slice();
          while (chain.length < 6 && pool.length) {
            pool.sort((a, b) => Math.hypot(a.x - cur.x, a.z - cur.z) - Math.hypot(b.x - cur.x, b.z - cur.z));
            const next = pool.find((p) => Math.hypot(p.x - cur.x, p.z - cur.z) > 250) || pool[0];
            pool.splice(pool.indexOf(next), 1);
            chain.push(next); cur = next;
          }
          if (chain.length < 3) {
            await m.say([['Rally Rita', 'Hmm, my roundabout map is missing today. Come back later!']]);
            throw new Fail('No roundabouts found nearby.');
          }
          await m.say([
            ['Rally Rita', 'Carmel has more roundabouts than any city in America. Let us find out how fast you can go around them.'],
            ['Rally Rita', `Drive through ${chain.length} roundabouts before time runs out. Grab a car!`],
          ]);
          if (!self.g.car) { m.objective('Get in any car.'); await m.until(() => self.g.car); }
          let dist = 0, prev = self.g.pos;
          for (const p of chain) { dist += Math.hypot(p.x - prev.x, p.z - prev.z) * 1.35; prev = p; }
          m.timer(Math.round(dist / 13 + 40));
          for (let i = 0; i < chain.length; i++) {
            await m.goto(chain[i], { text: `Roundabout ${i + 1} of ${chain.length}.`, car: true, radius: 22, next: chain[i + 1] });
            self.g.sound.checkpoint();
          }
          m.bonus(Math.round(m.timeLeft()) * 3, 'Time bonus');
        },
      },
      {
        id: 'icecream', title: 'Ice Cream Emergency', pay: 250, giver: { name: 'Lily', at: park, look: look({ shirt: 0xe46aa7, longHair: true, scale: 0.68 }) },
        async run(m) {
          await m.say([
            ['Lily', 'The ice cream truck drove off before I got my cone!'],
            ['Lily', 'Can you catch it? Please please please?'],
          ]);
          const truck = self.g.traffic.spawnSpecial('icecream', self.g.pos, 0xf7f3ea);
          if (!truck) throw new Fail('The truck is nowhere to be found.');
          m.track(truck);
          truck.ai.boost = 1;
          m.timer(180);
          await m.until(() => {
            const p = self.g.pos;
            const d = Math.hypot(truck.x - p.x, truck.z - p.z);
            truck.ai.boost = d < 70 ? 1.35 : 1;
            m.objective(`Catch the ice cream truck! ${Math.round(d)} m away.`);
            m.mark([{ x: truck.x, z: truck.z }]);
            return d < 7;
          });
          truck.driver = null; truck.ai.stun = 999;
          self.g.sound.smallHorn();
          await m.say([['Ice cream driver', 'A customer! One strawberry cone coming right up. Better hurry before it melts!']]);
          m.timer(120);
          await m.goto(self.spot(park), { text: 'Bring the cone to Lily before it melts.', radius: 12 });
          await m.say([['Lily', 'YAY! It is only a little melty. Thank you!']]);
        },
      },
      {
        id: 'market', title: 'Farmers Market Run', pay: 400, giver: { name: 'Farmer Dee', at: L.nickelPlate, look: look({ shirt: 0xff8a3d, cap: 0x3b9c5a }) },
        async run(m) {
          const fields = self.g.world.map.areas.filter((a) => a.kind === 6);
          const pick = [];
          const rnd = mulberry32(99);
          const c = L.nickelPlate;
          const cands = fields.map((a) => ({ x: (a.bbox[0] + a.bbox[2]) / 2, z: (a.bbox[1] + a.bbox[3]) / 2 }))
            .filter((p) => { const d = Math.hypot(p.x - c.x, p.z - c.z); return d > 2500 && d < 7500; });
          while (pick.length < 3 && cands.length) {
            const p = cands.splice(Math.floor(rnd() * cands.length), 1)[0];
            if (pick.every((q) => Math.hypot(q.x - p.x, q.z - p.z) > 1500)) pick.push(p);
          }
          if (pick.length < 3) pick.push(L.saxony, L.ritchey, L.ruoff);
          await m.say([
            ['Farmer Dee', 'The Saturday market opens soon and my produce is still out at the farms!'],
            ['Farmer Dee', 'Take my pickup. Grab pumpkins, apples and sweet corn, then bring it all back here. Easy on the bumps!'],
          ]);
          const s = self.spot(L.nickelPlate);
          const truck = m.car('pickup', s, 0x26472f);
          m.objective('Get in the farm pickup.');
          m.mark([{ x: truck.x, z: truck.z }], false);
          await m.until(() => self.g.car === truck);
          let bumps = 0;
          m.onBump = (st) => { if (self.g.car === truck && st > 4) { bumps++; self.g.hud.toast(`Produce bounced! ${bumps} bumps`, 'warn'); } };
          const crops = ['pumpkins', 'apples', 'sweet corn'];
          for (let i = 0; i < 3; i++) {
            await m.goto(self.spot(pick[i]), { text: `Pick up the ${crops[i]} at farm ${i + 1} of 3.`, car: true, stop: true, radius: 14 });
            self.g.sound.coin();
            self.g.hud.toast(`Loaded the ${crops[i]}.`);
          }
          await m.goto(s, { text: 'Bring the produce back to the market.', car: true, stop: true, radius: 14 });
          await m.say([['Farmer Dee', 'Look at these beauties! The market is going to be great this week.']]);
          m.bonus(Math.max(0, 200 - bumps * 25), 'Careful driving');
        },
      },
      {
        id: 'photos', title: 'Picture Perfect', pay: 600, giver: { name: 'Sam the photographer', at: L.cityHall, look: look({ shirt: 0x2f6fb5, hair: 0xb5532b }) },
        async run(m) {
          await m.say([
            ['Sam', 'I am making a calendar of the best spots in Hamilton County, but my car is in the shop.'],
            ['Sam', 'Get photos at six landmarks, in any order. Just get close and I will tell you when the shot is good.'],
          ]);
          const set = [L.connerPrairie, L.geist, L.noblesville, L.carmelArts, L.topgolf, L.ruoff];
          const left = set.map((p) => ({ ...self.spot(p, isDrivable, 300), label: p.label }));
          while (left.length) {
            m.objective(`Photograph the landmarks: ${6 - left.length} of 6. Next closest: ${closest(left, self.g.pos).label}.`);
            m.mark(left);
            const hit = await m.until(() => left.find((p) => Math.hypot(p.x - self.g.pos.x, p.z - self.g.pos.z) < 30));
            left.splice(left.indexOf(hit), 1);
            self.flash = 1;
            self.g.sound.checkpoint();
            self.g.hud.toast(`Snap! ${hit.label} looks great.`);
          }
          await m.goto(self.spot(L.cityHall), { text: 'Bring the photos back to Sam at City Hall.', radius: 14 });
          await m.say([['Sam', 'These are gorgeous. You really are a Hamilton County local now.']]);
        },
      },
    ];
  }

  // ---------------------------------------------------------------- givers
  placeGivers() {
    for (const gv of this.givers) { this.g.scene.remove(gv.npc.mesh); this.g.scene.remove(gv.sprite); }
    this.givers = [];
    const done = new Set(this.g.save.done);
    const welcomeDone = done.has('welcome');
    for (const def of this.defs) {
      if (!def.first && !welcomeDone) continue;
      if (def.first && welcomeDone) continue;
      const at = def.giver.at;
      const s = def.first ? { x: at.x, z: at.z }
        : def.giver.onTrail ? this.spot(at, isTrail, 60)
        : this.spot(at, (t, f) => isDrivable(t, f) || t === 16, 250);
      const npc = this.g.spawnNPC(def.giver.look, s.x, s.z, Math.random() * 6);
      const sprite = textSprite(done.has(def.id) ? def.giver.name : `! ${def.title}`, {
        bg: done.has(def.id) ? 'rgba(20,30,40,0.75)' : '#ffd23f', color: done.has(def.id) ? '#fff' : '#13202b', scale: 0.24,
        font: '700 40px "Barlow Condensed", "Arial Narrow", sans-serif',
      });
      sprite.position.set(s.x, 2.6, s.z);
      this.g.scene.add(sprite);
      this.givers.push({ def, npc, sprite, x: s.x, z: s.z, done: done.has(def.id) });
    }
  }

  blips() {
    const out = [];
    if (!this.active) for (const gv of this.givers) if (!gv.done) out.push({ x: gv.x, z: gv.z, icon: 'giver', color: '#ffd23f' });
    for (const mk of this.markers) out.push({ x: mk.x, z: mk.z, color: '#ffd23f' });
    return out;
  }

  // nearest giver within reach, for the E prompt
  nearGiver(p) {
    if (this.active) return null;
    let best = null, bd = 3.5;
    for (const gv of this.givers) {
      const d = Math.hypot(gv.x - p.x, gv.z - p.z);
      if (d < bd) { bd = d; best = gv; }
    }
    return best;
  }

  start(gv) {
    if (this.active) return;
    const def = gv.def;
    const m = new MissionCtx(this, def, gv);
    this.active = m;
    this.g.hud.banner(def.title, gv.done ? 'Replay' : 'New job', 'start');
    def.run(m).then(() => { if (!m.dead) this.finish(m, true); }).catch((e) => {
      if (!(e instanceof Fail)) console.error(e);
      if (!m.dead) { m.dead = true; this.finish(m, false, e instanceof Fail ? e.message : 'Something went wrong.'); }
    });
  }

  finish(m, ok, reason) {
    if (this.active !== m) return;
    m.cleanup();
    this.active = null;
    this.markers = [];
    this.g.hud.setObjective(null);
    if (ok) {
      const replay = this.g.save.done.includes(m.def.id);
      const pay = Math.round(m.def.pay * (replay ? 0.5 : 1)) + m.bonusTotal;
      this.g.addMoney(pay);
      if (!replay) this.g.save.done.push(m.def.id);
      this.g.sound.success();
      this.g.hud.banner('Job complete', `${m.def.title}  +$${pay}`, 'pass');
      this.g.persist();
      if (this.g.save.done.length === this.defs.length && !replay) {
        setTimeout(() => this.g.hud.banner('Hamilton County Hero', 'You finished every job. Keep cruising!', 'pass'), 4500);
      }
    } else {
      this.g.sound.fail();
      this.g.hud.banner('Job failed', reason || 'Try again.', 'fail');
    }
    this.placeGivers();
  }

  cancel() {
    if (this.active) this.active.reject(new Fail('You called it off.'));
  }

  update(dt) {
    const m = this.active;
    if (this.flash > 0) this.flash = Math.max(0, this.flash - dt * 2.5);
    for (const gv of this.givers) {
      gv.sprite.position.y = 2.6 + Math.sin(performance.now() / 400 + gv.x) * 0.12;
    }
    this.updateFish(dt);
    if (!m) return;
    m.tick(dt);
  }

  // ---------------------------------------------------------------- golden fish
  makeFish() {
    const rnd = mulberry32(4242);
    const [minx, minz, maxx, maxz] = this.g.world.bounds;
    const items = [];
    const mat = new THREE.SpriteMaterial({ map: this.g.tex.fish, transparent: true });
    for (let i = 0; items.length < 30 && i < 600; i++) {
      const x = minx + 1500 + rnd() * (maxx - minx - 3000), z = minz + 1500 + rnd() * (maxz - minz - 3000);
      const hit = this.g.world.nearestRoad(x, z, (t) => t >= 11 && t <= 16, 300);
      if (!hit) continue;
      const c = this.g.nav.curbside(hit, 3);
      if (items.some((f) => Math.hypot(f.x - c.x, f.z - c.z) < 1500)) continue;
      const s = new THREE.Sprite(mat);
      s.scale.set(1.6, 1.6, 1);
      s.position.set(c.x, 1.2, c.z);
      s.visible = false;
      this.g.scene.add(s);
      items.push({ id: items.length, x: c.x, z: c.z, sprite: s, got: this.g.save.fish.includes(items.length) });
    }
    return items;
  }

  updateFish(dt) {
    const p = this.g.pos;
    const t = performance.now() / 1000;
    for (const f of this.fish) {
      if (f.got) { f.sprite.visible = false; continue; }
      const d = Math.hypot(f.x - p.x, f.z - p.z);
      f.sprite.visible = d < 120;
      if (!f.sprite.visible) continue;
      f.sprite.position.y = 1.3 + Math.sin(t * 2 + f.id) * 0.25;
      f.sprite.material.rotation = Math.sin(t * 1.5) * 0.2;
      if (d < 3) {
        f.got = true;
        this.g.save.fish.push(f.id);
        this.g.addMoney(50);
        this.g.sound.coin();
        this.g.hud.toast(`Golden fish found! ${this.g.save.fish.length} of ${this.fish.length}  +$50`, 'gold');
        this.g.persist();
      }
    }
  }
}

function closest(list, p) {
  return list.reduce((a, b) => (Math.hypot(a.x - p.x, a.z - p.z) <= Math.hypot(b.x - p.x, b.z - p.z) ? a : b));
}

// What a running mission script uses to wait for things and to show its goals.
class MissionCtx {
  constructor(mgr, def, giver) {
    this.mgr = mgr; this.g = mgr.g; this.def = def; this.giver = giver;
    this.waiters = [];
    this.deadline = null;
    this.fails = [];
    this.title = def.title;
    this.text = '';
    this.items = [];
    this.cars = [];
    this.npcs = [];
    this.bonusTotal = 0;
    this.passenger = null;
    this.chat = null;
    this.onBump = null;
    this.dead = false;
  }

  objective(text) { this.text = text; }
  timer(sec) { this.deadline = sec; }
  addTime(sec) { if (this.deadline != null) this.deadline += sec; }
  timeLeft() { return this.deadline ?? 0; }
  bonus(n, why) { if (n > 0) { this.bonusTotal += n; this.g.hud.toast(`${why}: +$${n}`, 'gold'); } }
  mark(list, route = true) { this.mgr.markers = list.map((p) => ({ x: p.x, z: p.z, label: p.label })); this.route = route; }
  failIf(fn, reason) { this.fails.push([fn, reason]); }

  say(lines) {
    return this.g.hud.say(lines.map(([who, text]) => ({ who, text })));
  }

  until(fn) {
    if (this.dead) return new Promise(() => {}); // a finished mission's script just stops here
    return new Promise((resolve, reject) => {
      this.waiters.push({ fn, resolve, reject });
    });
  }

  reject(err) {
    if (this.dead) return;
    this.dead = true;
    const ws = this.waiters;
    this.waiters = [];
    for (const w of ws) w.reject(err);
    this.mgr.finish(this, false, err.message);
  }

  goto(p, opts = {}) {
    const r = opts.radius ?? 8;
    this.objective(opts.text || 'Go to the marker.');
    const list = [p];
    if (opts.next) list.push(opts.next);
    this.mark(list);
    this.mgr.markers[0].radius = r;
    return this.until(() => {
      const pos = this.g.pos;
      const d = Math.hypot(p.x - pos.x, p.z - pos.z);
      if (d > r) return false;
      if (opts.bike && !this.g.car?.spec.bike) { this.g.hud.setPrompt('You need to be on a bike for this.'); return false; }
      if (opts.car && !this.g.car) { this.g.hud.setPrompt('You need to be in a car for this.'); return false; }
      if (opts.stop && this.g.car && Math.abs(this.g.car.speed) > 2.5) { this.g.hud.setPrompt('<b>Slow down</b> and stop here.'); return false; }
      return true;
    });
  }

  car(type, s, color) {
    if (this.dead) throw new Fail('Mission over.');
    const heading = s.dx != null ? Math.atan2(s.dx, s.dz) : 0;
    const c = this.g.spawnCar(type, s.x, s.z, heading, color);
    this.cars.push(c);
    return c;
  }

  track(car) { this.cars.push(car); }

  npcFromGiver() { return { x: this.giver.x, z: this.giver.z, npc: this.giver.npc }; }

  boardPassenger(p) {
    p.npc.mesh.visible = false;
    this.passenger = p;
    this.g.sound.door();
  }
  dropPassenger() {
    if (!this.passenger) return;
    const c = this.g.car || { x: this.g.pos.x, z: this.g.pos.z };
    this.passenger.npc.mesh.visible = true;
    this.passenger.npc.mesh.position.set(c.x + 2, 0, c.z);
    this.passenger = null;
    this.chat = null;
    this.g.sound.door();
  }
  chatter([who, lines]) { this.chat = { who, lines, i: 0, t: 12 }; }

  collect(spots, kind, label) {
    const total = spots.length;
    const geo = new THREE.SphereGeometry(0.35, 10, 8);
    const mat = new THREE.MeshLambertMaterial({ color: 0xffd23f, emissive: 0x332200 });
    const beak = new THREE.MeshLambertMaterial({ color: 0xff8a3d });
    for (const s of spots) {
      const g = new THREE.Group();
      const body = new THREE.Mesh(geo, mat); body.scale.set(1, 0.8, 1.3); body.position.y = 0.3; g.add(body);
      const head = new THREE.Mesh(geo, mat); head.scale.setScalar(0.6); head.position.set(0, 0.62, 0.3); g.add(head);
      const bk = new THREE.Mesh(geo, beak); bk.scale.set(0.25, 0.12, 0.35); bk.position.set(0, 0.6, 0.55); g.add(bk);
      g.position.set(s.x, 0, s.z);
      g.rotation.y = Math.random() * 6;
      this.g.scene.add(g);
      this.items.push({ ...s, obj: g, got: false });
    }
    const left = () => this.items.filter((i) => !i.got);
    return this.until(() => {
      const p = this.g.pos;
      for (const it of left()) {
        it.obj.position.y = Math.abs(Math.sin(performance.now() / 200 + it.x)) * 0.15;
        if (Math.hypot(it.x - p.x, it.z - p.z) < 2.8) {
          it.got = true; this.g.scene.remove(it.obj); this.g.sound.coin();
        }
      }
      const l = left().sort((a, b) => Math.hypot(a.x - p.x, a.z - p.z) - Math.hypot(b.x - p.x, b.z - p.z));
      this.objective(label(total - l.length, total));
      this.mgr.markers = l.map((i) => ({ x: i.x, z: i.z }));
      this.route = true;
      return l.length === 0;
    });
  }

  tick(dt) {
    if (this.dead) return;
    if (this.deadline != null && !this.g.hud.dialog) {
      this.deadline -= dt;
      if (this.deadline <= 0) { this.reject(new Fail('You ran out of time.')); return; }
    }
    for (const [fn, reason] of this.fails) if (fn()) { this.reject(new Fail(reason)); return; }
    if (this.chat && this.g.car) {
      this.chat.t -= dt;
      if (this.chat.t <= 0 && this.chat.i < this.chat.lines.length) {
        this.g.hud.toast(`${this.chat.who}: "${this.chat.lines[this.chat.i++]}"`);
        this.chat.t = 14;
      }
    }
    if (this.g.hud.dialog) return; // wait for the player to read
    const ws = this.waiters;
    this.waiters = [];
    for (const w of ws) {
      let r;
      try { r = w.fn(); } catch (e) { w.reject(e); continue; }
      if (r) w.resolve(r); else this.waiters.push(w);
    }
    this.g.hud.setObjective(this.title, this.text, this.deadline);
  }

  cleanup() {
    for (const it of this.items) this.g.scene.remove(it.obj);
    for (const c of this.cars) {
      if (this.g.car === c) continue; // keep the car you're sitting in
      this.g.removeCar(c);
    }
    if (this.passenger) this.dropPassenger();
    this.mgr.markers = [];
  }
}
