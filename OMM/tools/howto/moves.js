// How-to animations for OMM, authored here and turned into Swift by
// generate.js (node OMM/tools/howto/generate.js). preview.html shows them.
//
// The scene is 200 x 140 points, y grows down, the floor is at y = 124.
// A pose places the hip, shoulder, both hands and both feet; elbows and knees
// are worked out from the bone lengths, so limbs never stretch. "n" is the
// near side (dark), "f" the far side (light). sw/hw are half the shoulder and
// hip width (front views). ht turns the head (degrees). Each frame says how
// long to hold it and how long to move to the next one; the last frame moves
// back to the first, so every move loops.
//
// All drawings here are original. Don't trace another app's art.
(function (root) {
  const FLOOR = 124;
  const TORSO = 38, LEG = 51;

  // A straight body pivoting on the toes: shoulder height comes from the angle.
  function plank(footX, degrees) {
    const a = degrees * Math.PI / 180;
    const ux = Math.cos(a), uy = -Math.sin(a);
    const foot = [footX, FLOOR];
    const hip = [footX + ux * LEG, FLOOR + uy * LEG];
    const sh = [footX + ux * (LEG + TORSO), FLOOR + uy * (LEG + TORSO)];
    return { hip: r(hip), sh: r(sh), nf: foot, ff: [footX - 3, FLOOR] };
  }
  function r(p) { return [Math.round(p[0] * 10) / 10, Math.round(p[1] * 10) / 10]; }
  function pose(base, extra) { return Object.assign({}, base, extra); }

  const moves = [];
  function move(m) { moves.push(m); }

  // ---------- Mid chest: no equipment ----------

  const pTop = plank(46, 27.5), pLow = plank(46, 7);
  move({
    name: "Standard Push-ups", view: "side",
    bends: [-1, -1, -1, -1],
    frames: [
      { p: pose(pTop, { nh: [125, FLOOR], fh: [128, FLOOR] }), hold: 0.3, go: 1.2 },
      { p: pose(pLow, { nh: [125, FLOOR], fh: [128, FLOOR] }), hold: 0.2, go: 0.9 },
    ],
    tips: ["Hands under your shoulders, body in one straight line.",
           "Lower until your chest is just above the floor.",
           "Push back up without letting your hips sag."],
  });

  // Front view: the arms frame the head, the body runs away from you.
  function frontPlank(cx, y, extra) {
    return pose({ hip: [cx, y - 12], sh: [cx, y], sw: [14, 0], hw: [6, 0],
                  nf: [cx - 5, y - 30], ff: [cx + 5, y - 30], ht: 0, hideBody: 1 }, extra);
  }
  move({
    name: "Wide Grip Push-ups", view: "front",
    bends: [1, -1, 1, -1],
    frames: [
      { p: frontPlank(100, 88, { nh: [140, FLOOR], fh: [60, FLOOR] }), hold: 0.3, go: 1.2 },
      { p: frontPlank(100, 110, { nh: [140, FLOOR], fh: [60, FLOOR] }), hold: 0.2, go: 0.9 },
    ],
    tips: ["Hands a little wider than your shoulders.",
           "Elbows bend out to the sides as you lower.",
           "Keep your body straight and press back up."],
  });

  const pAir = plank(46, 31);
  move({
    name: "Plyometric (Clapping) Push-ups", view: "side",
    bends: [-1, -1, -1, -1],
    frames: [
      { p: pose(pTop, { nh: [125, FLOOR], fh: [128, FLOOR] }), hold: 0.4, go: 1.0 },
      { p: pose(pLow, { nh: [125, FLOOR], fh: [128, FLOOR] }), hold: 0.1, go: 0.3 },
      { p: pose(pAir, { nh: [pAir.sh[0] + 6, pAir.sh[1] + 18], fh: [pAir.sh[0] + 6, pAir.sh[1] + 18] }), hold: 0.15, go: 0.3 },
    ],
    tips: ["Lower under control, then push up hard enough that your hands leave the floor.",
           "Clap quickly and get your hands back down.",
           "Land with soft elbows. Do these from your knees to start."],
  });

  move({
    name: "Archer Push-ups", view: "front",
    bends: [1, -1, 1, -1],
    frames: [
      { p: frontPlank(100, 86, { nh: [134, FLOOR], fh: [66, FLOOR] }), hold: 0.2, go: 1.0 },
      { p: frontPlank(80, 110, { nh: [134, FLOOR], fh: [66, FLOOR] }), hold: 0.3, go: 1.0 },
      { p: frontPlank(100, 86, { nh: [134, FLOOR], fh: [66, FLOOR] }), hold: 0.2, go: 1.0 },
      { p: frontPlank(120, 110, { nh: [134, FLOOR], fh: [66, FLOOR] }), hold: 0.3, go: 1.0 },
    ],
    tips: ["Hands very wide. Shift your weight over one hand as you lower.",
           "The other arm stays almost straight, like drawing a bow.",
           "Push back to the middle, then switch sides."],
  });

  // Standing, seen from the front.
  function stand(extra) {
    return pose({ hip: [100, 73], sh: [100, 35], sw: [13, 0], hw: [7, 0],
                  nf: [107, FLOOR], ff: [93, FLOOR] }, extra);
  }
  move({
    name: "Isometric Chest Squeeze (Prayer pose)", view: "front",
    bends: [-1, 1, 1, -1],
    props: [{ k: "squeeze" }],
    frames: [
      { p: stand({ nh: [101, 52], fh: [99, 52] }), hold: 0.6, go: 0.5 },
      { p: stand({ nh: [100.5, 50], fh: [99.5, 50], sw: [14, -1] }), hold: 1.6, go: 0.5 },
    ],
    tips: ["Press your palms together in front of your chest, elbows out.",
           "Squeeze as hard as you can and hold for 10 to 20 seconds.",
           "Keep breathing. Relax, then repeat."],
  });

  // ---------- Mid chest: gym ----------

  const benchBody = { hip: [80, 87], sh: [118, 87], nf: [62, FLOOR], ff: [58, FLOOR] };
  move({
    name: "Flat Bench Press (Barbell)", view: "side",
    bends: [-1, -1, -1, -1],
    props: [{ k: "bench", x: 62, y: 93, w: 78 }, { k: "barbell" }],
    frames: [
      { p: pose(benchBody, { nh: [117, 44], fh: [119, 44] }), hold: 0.3, go: 1.4 },
      { p: pose(benchBody, { nh: [113, 76], fh: [115, 76] }), hold: 0.2, go: 1.0 },
    ],
    tips: ["Feet flat on the floor, shoulder blades pinched together.",
           "Lower the bar slowly to the middle of your chest.",
           "Press it straight back up. Use a spotter for heavy sets."],
  });

  move({
    name: "Flat Dumbbell Press", view: "side",
    bends: [-1, -1, -1, -1],
    props: [{ k: "bench", x: 62, y: 93, w: 78 }, { k: "dumbbells" }],
    frames: [
      { p: pose(benchBody, { nh: [118, 44], fh: [120, 44] }), hold: 0.3, go: 1.4 },
      { p: pose(benchBody, { nh: [115, 79], fh: [117, 79] }), hold: 0.2, go: 1.0 },
    ],
    tips: ["Start with the dumbbells over your chest, palms facing your feet.",
           "Lower them to the sides of your chest, elbows a little below the bench.",
           "Press up and let them come close together at the top."],
  });

  const seated = { hip: [80, 90], sh: [75, 52], nf: [112, FLOOR], ff: [108, FLOOR], ht: -8 };
  move({
    name: "Machine Chest Press", view: "side",
    bends: [1, 1, -1, -1],
    props: [{ k: "seat", x: 66, y: 93, w: 32, back: 40 },
            { k: "lever", pivot: [80, 24], post: 56 }],
    frames: [
      { p: pose(seated, { nh: [95, 60], fh: [97, 60] }), hold: 0.3, go: 1.0 },
      { p: pose(seated, { nh: [113, 60], fh: [115, 60] }), hold: 0.2, go: 1.4 },
    ],
    tips: ["Set the seat so the handles line up with the middle of your chest.",
           "Push forward until your arms are nearly straight.",
           "Come back slowly without letting the weight stack touch."],
  });

  function cableStand(extra) { return stand(extra); }
  move({
    name: "Cable Flyes (Middle setting)", view: "front",
    bends: [-1, 1, 1, -1],
    props: [{ k: "tower", x: 14, top: 38 }, { k: "tower", x: 186, top: 38 },
            { k: "cable", from: [186, 38], hand: "n" }, { k: "cable", from: [14, 38], hand: "f" }],
    frames: [
      { p: cableStand({ nh: [156, 48], fh: [44, 48] }), hold: 0.3, go: 1.3 },
      { p: cableStand({ nh: [102, 68], fh: [98, 68] }), hold: 0.4, go: 1.3 },
    ],
    tips: ["Set both pulleys at shoulder height and step forward a little.",
           "Keep a slight bend in your elbows and sweep your hands together.",
           "Squeeze your chest, then open slowly until you feel a stretch."],
  });

  const floorBody = { hip: [76, 116], sh: [114, 116], nf: [56, FLOOR], ff: [52, FLOOR] };
  move({
    name: "Dumbbell Floor Press", view: "side",
    bends: [1, 1, 1, 1],
    props: [{ k: "dumbbells" }],
    frames: [
      { p: pose(floorBody, { nh: [113, 72], fh: [115, 72] }), hold: 0.3, go: 1.3 },
      { p: pose(floorBody, { nh: [110, 104], fh: [112, 104] }), hold: 0.3, go: 1.0 },
    ],
    tips: ["Lie on the floor, knees bent, dumbbells over your chest.",
           "Lower until your upper arms rest on the floor and pause.",
           "Press back up. The floor keeps your shoulders safe."],
  });

  root.HOWTO = { group: "Mid", moves: moves };
})(typeof window !== "undefined" ? window : globalThis);
