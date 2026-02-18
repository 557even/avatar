// Synthetic cosmic web generator (superclusters as hubs + filament edges).
// No external deps.

function mulberry32(seed) {
  let t = seed >>> 0;
  return function () {
    t += 0x6D2B79F5;
    let x = Math.imul(t ^ (t >>> 15), 1 | t);
    x ^= x + Math.imul(x ^ (x >>> 7), 61 | x);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

function randn(rng) {
  // Box-Muller
  let u = 0, v = 0;
  while (u === 0) u = rng();
  while (v === 0) v = rng();
  return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}

export function generateUniverseGraph({
  seed = 1337,
  n = 600,
  hubs = 10,
  width = 1600,
  height = 900,
  edgePercentile = 45, // 0..100 higher => fewer edges
  alpha = 1.6, // distance penalty exponent
} = {}) {
  const rng = mulberry32(seed);

  // Hub centers (Gaussian mixture)
  const centers = Array.from({ length: hubs }, (_, i) => ({
    id: `H${i}`,
    cx: (rng() * 0.8 + 0.1) * width,
    cy: (rng() * 0.8 + 0.1) * height,
    scale: (0.08 + 0.18 * rng()) * Math.min(width, height),
    mass: 0.8 + 1.8 * rng(),
  }));

  // Nodes (superclusters)
  const nodes = Array.from({ length: n }, (_, i) => {
    const c = centers[Math.floor(rng() * hubs)];
    const x = c.cx + randn(rng) * c.scale;
    const y = c.cy + randn(rng) * c.scale;

    // heavy-tailed-ish mass
    const mass = Math.pow(1 - rng(), -0.7); // Pareto-like
    return {
      id: `SC${i}`,
      type: "supercluster",
      mass: Math.min(mass, 40),
      x,
      y,
    };
  });

  // Score all candidate edges via sparse kNN (approx): sample m candidates per node
  const m = 16;
  const candidates = [];
  for (let i = 0; i < n; i++) {
    for (let t = 0; t < m; t++) {
      const j = Math.floor(rng() * n);
      if (j === i) continue;
      const aN = nodes[i], bN = nodes[j];
      const dx = aN.x - bN.x, dy = aN.y - bN.y;
      const r = Math.sqrt(dx * dx + dy * dy) + 1e-6;
      const score = (aN.mass * bN.mass) / Math.pow(r, alpha);
      candidates.push({ i, j, r, score });
    }
  }

  // Determine threshold by percentile
  candidates.sort((a, b) => a.score - b.score);
  const idx = Math.floor((edgePercentile / 100) * (candidates.length - 1));
  const threshold = candidates[idx]?.score ?? 0;

  const seen = new Set();
  const links = [];
  for (const c of candidates) {
    if (c.score < threshold) continue;
    const a = Math.min(c.i, c.j);
    const b = Math.max(c.i, c.j);
    const key = `${a}-${b}`;
    if (seen.has(key)) continue;
    seen.add(key);
    links.push({
      source: nodes[c.i].id,
      target: nodes[c.j].id,
      weight: c.score,
      kind: "filament",
    });
  }

  // Degree
  const deg = new Map(nodes.map((d) => [d.id, 0]));
  for (const e of links) {
    deg.set(e.source, deg.get(e.source) + 1);
    deg.set(e.target, deg.get(e.target) + 1);
  }
  for (const nd of nodes) nd.degree = deg.get(nd.id);

  return { nodes, links, meta: { seed, n, hubs, threshold } };
}
