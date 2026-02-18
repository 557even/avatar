import { generateUniverseGraph } from "./universe.js";

const canvas = document.getElementById("links");
const ctx = canvas.getContext("2d");
const svg = d3.select("#nodesSvg");
const inspect = document.getElementById("inspect");

const ui = {
  nodes: document.getElementById("nodes"),
  edge: document.getElementById("edge"),
  repel: document.getElementById("repel"),
  regen: document.getElementById("regen"),
  pause: document.getElementById("pause"),
  resetView: document.getElementById("resetView"),
  labels: document.getElementById("labels"),
  bg: document.getElementById("bg"),
  nodesVal: document.getElementById("nodesVal"),
  edgeVal: document.getElementById("edgeVal"),
  repelVal: document.getElementById("repelVal"),
  fps: document.getElementById("fps"),
};

let width = window.innerWidth;
let height = window.innerHeight;

function resize() {
  width = window.innerWidth;
  height = window.innerHeight;
  canvas.width = Math.floor(width * devicePixelRatio);
  canvas.height = Math.floor(height * devicePixelRatio);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
  svg.attr("width", width).attr("height", height);
}
window.addEventListener("resize", resize);
resize();

// Particles background
function startParticles() {
  if (!window.particlesJS) return;
  particlesJS("particles", {
    particles: {
      number: { value: 90, density: { enable: true, value_area: 1000 } },
      color: { value: "#9ca3af" },
      opacity: { value: 0.35 },
      size: { value: 1.6, random: true },
      move: { enable: true, speed: 0.25 },
      line_linked: { enable: false },
    },
    interactivity: { events: { onhover: { enable: false }, onclick: { enable: false } } },
    retina_detect: true,
  });
}
startParticles();

ui.bg.addEventListener("change", () => {
  document.getElementById("particles").style.display = ui.bg.checked ? "block" : "none";
});

let transform = d3.zoomIdentity;
const zoom = d3.zoom().scaleExtent([0.05, 20]).on("zoom", (ev) => {
  transform = ev.transform;
  nodesG.attr("transform", transform);
});
svg.call(zoom);

// SVG nodes layer
const nodesG = svg.append("g");
let nodeSel = nodesG.selectAll("circle");
let labelSel = nodesG.selectAll("text");

let sim = null;
let graph = null;
let paused = false;

function massToRadius(m) {
  return Math.max(1.8, Math.min(10, 1.8 + Math.log2(m + 1)));
}

function drawLinks() {
  ctx.clearRect(0, 0, width, height);
  if (!graph) return;

  ctx.save();
  ctx.translate(transform.x, transform.y);
  ctx.scale(transform.k, transform.k);

  ctx.globalAlpha = 0.35;
  ctx.lineWidth = 1 / transform.k;

  for (const e of graph.links) {
    const s = e.source, t = e.target;
    // During simulation, d3 mutates source/target to objects
    const sx = s.x ?? s?.x, sy = s.y ?? s?.y;
    const tx = t.x ?? t?.x, ty = t.y ?? t?.y;
    const w = Math.min(1, 0.15 + 0.15 * Math.log10(e.weight + 1));
    ctx.strokeStyle = `rgba(56,189,248,${w})`; // cyan
    ctx.beginPath();
    ctx.moveTo(sx, sy);
    ctx.lineTo(tx, ty);
    ctx.stroke();
  }
  ctx.restore();
}

function updateHUD() {
  ui.nodesVal.textContent = ui.nodes.value;
  ui.edgeVal.textContent = `${ui.edge.value}%`;
  ui.repelVal.textContent = ui.repel.value;
}

function setInspect(d) {
  if (!d) {
    inspect.innerHTML = `<div class="text-slate-300">Hover a node…</div>`;
    return;
  }
  inspect.innerHTML = `
    <div class="font-semibold text-slate-100">${d.id}</div>
    <div class="text-slate-300">type=${d.type}</div>
    <div class="text-slate-300">mass=${d.mass.toFixed(2)}</div>
    <div class="text-slate-300">degree=${d.degree}</div>
  `;
}

function build() {
  updateHUD();
  const seed = Math.floor(performance.now()) ^ (Math.random() * 1e9);

  graph = generateUniverseGraph({
    seed,
    n: +ui.nodes.value,
    hubs: Math.max(6, Math.floor(Math.sqrt(+ui.nodes.value) / 2)),
    width: Math.max(1400, width),
    height: Math.max(800, height),
    edgePercentile: +ui.edge.value,
  });

  // Reset selections
  nodesG.selectAll("*").remove();

  nodeSel = nodesG
    .selectAll("circle")
    .data(graph.nodes, (d) => d.id)
    .join("circle")
    .attr("r", (d) => massToRadius(d.mass))
    .attr("fill", (d) => {
      // color by degree (rough)
      const k = Math.min(1, d.degree / 12);
      return d3.interpolateTurbo(0.15 + 0.7 * k);
    })
    .attr("stroke", "rgba(15,23,42,0.9)")
    .attr("stroke-width", 1.0)
    .on("mouseenter", (_, d) => setInspect(d))
    .on("mouseleave", () => setInspect(null))
    .call(
      d3
        .drag()
        .on("start", (ev, d) => {
          if (!ev.active) sim.alphaTarget(0.25).restart();
          d.fx = d.x;
          d.fy = d.y;
        })
        .on("drag", (ev, d) => {
          d.fx = transform.invertX(ev.x);
          d.fy = transform.invertY(ev.y);
        })
        .on("end", (ev, d) => {
          if (!ev.active) sim.alphaTarget(0);
          d.fx = null;
          d.fy = null;
        })
    );

  labelSel = nodesG
    .selectAll("text")
    .data(graph.nodes, (d) => d.id)
    .join("text")
    .text((d) => d.id)
    .attr("font-size", 10)
    .attr("fill", "rgba(226,232,240,0.75)")
    .attr("dx", 8)
    .attr("dy", 3)
    .style("display", ui.labels.checked ? "block" : "none");

  // D3 force simulation
  if (sim) sim.stop();
  sim = d3
    .forceSimulation(graph.nodes)
    .force(
      "link",
      d3
        .forceLink(graph.links)
        .id((d) => d.id)
        .distance((e) => 30 + 180 / Math.sqrt((e.weight ?? 1) + 1))
        .strength(0.07)
    )
    .force("charge", d3.forceManyBody().strength(() => -(+ui.repel.value)))
    .force("center", d3.forceCenter(Math.max(1400, width) / 2, Math.max(800, height) / 2))
    .force("collide", d3.forceCollide().radius((d) => massToRadius(d.mass) + 1.5))
    .on("tick", () => {
      drawLinks();
      nodeSel.attr("cx", (d) => d.x).attr("cy", (d) => d.y);
      labelSel.attr("x", (d) => d.x).attr("y", (d) => d.y);
    });

  paused = false;
  ui.pause.textContent = "Pause";
}
build();

ui.labels.addEventListener("change", () => {
  labelSel.style("display", ui.labels.checked ? "block" : "none");
});
ui.nodes.addEventListener("input", updateHUD);
ui.edge.addEventListener("input", updateHUD);
ui.repel.addEventListener("input", () => {
  updateHUD();
  if (sim) sim.force("charge").strength(() => -(+ui.repel.value));
  if (sim) sim.alpha(0.15).restart();
});

ui.regen.addEventListener("click", build);
ui.pause.addEventListener("click", () => {
  if (!sim) return;
  paused = !paused;
  if (paused) {
    sim.stop();
    ui.pause.textContent = "Resume";
  } else {
    sim.alpha(0.12).restart();
    ui.pause.textContent = "Pause";
  }
});
ui.resetView.addEventListener("click", () => {
  svg.transition().duration(250).call(zoom.transform, d3.zoomIdentity);
});

// FPS meter
let last = performance.now();
let frames = 0;
setInterval(() => {
  const now = performance.now();
  const dt = now - last;
  const fps = (frames / dt) * 1000;
  ui.fps.textContent = `FPS: ${fps.toFixed(0)}`;
  frames = 0;
  last = now;
}, 500);

(function animateCount() {
  frames++;
  requestAnimationFrame(animateCount);
})();
