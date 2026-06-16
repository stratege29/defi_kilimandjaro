/**
 * Rendu serveur des cartes « Vert Nuit » (canvas) — port fidèle des templates
 * Python (énigme / réponse / proverbe). Utilisé par igRenderCard (composer admin).
 */
import { createCanvas, GlobalFonts, loadImage, type SKRSContext2D } from "@napi-rs/canvas";
import * as path from "path";

const FD = path.join(__dirname, "..", "..", "assets", "fonts");
let fontsReady = false;
function ensureFonts(): void {
  if (fontsReady) return;
  GlobalFonts.registerFromPath(path.join(FD, "Lora-Variable.ttf"), "Lora");
  GlobalFonts.registerFromPath(path.join(FD, "Lora-Italic-Variable.ttf"), "LoraIt");
  GlobalFonts.registerFromPath(path.join(FD, "Poppins-Bold.ttf"), "Poppins");
  GlobalFonts.registerFromPath(path.join(FD, "Poppins-Medium.ttf"), "Poppins");
  GlobalFonts.registerFromPath(path.join(FD, "Poppins-Regular.ttf"), "Poppins");
  fontsReady = true;
}

// ---- palette ----
const C = {
  CANVAS: "#0C1712", S1: "#15241C", S2: "#1E3328", HAIR: "#2C4034",
  GOLD: "#E9B949", GOLD_DP: "#C18A2A", GOLD_LT: "#F1C766",
  KOLA: "#F0533B", SUCCESS: "#28C76F", T1: "#F4ECD8", T2: "#A6AE9C", T3: "#717A6C",
  INK: "#1A1206", BRONZE_DK: "#5E3D1A",
};
const ACCENTS: Record<string, string> = {
  culture: "#F07A1A", nouchi: "#E85D9E", villes: "#C77B3A", foot: "#3DA35D", gold: C.GOLD,
};
const RGB: Record<string, [number, number, number]> = { gold: [233, 185, 73], kola: [240, 83, 59], success: [40, 199, 111] };

function serif(size: number): string { return `700 ${size}px Lora`; }
function serifIt(size: number): string { return `500 ${size}px LoraIt`; }
function sans(size: number, w = "Bold"): string { return `${w === "Bold" ? 700 : w === "Medium" ? 500 : 400} ${size}px Poppins`; }

function roundRect(ctx: SKRSContext2D, x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function base(ctx: SKRSContext2D, w: number, h: number, glow: [number, number, number], strength: number, glowY = -0.08): void {
  ctx.fillStyle = C.CANVAS;
  ctx.fillRect(0, 0, w, h);
  const cx = w * 0.5, cy = h * glowY;
  const r = Math.max(w, h) * 0.9;
  const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
  g.addColorStop(0, `rgba(${glow[0]},${glow[1]},${glow[2]},${strength})`);
  g.addColorStop(1, `rgba(${glow[0]},${glow[1]},${glow[2]},0)`);
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
}

function kente(ctx: SKRSContext2D, x: number, y: number, w: number, h = 10): void {
  const seq = [C.GOLD, C.KOLA, "#C68A42", C.SUCCESS, C.GOLD_DP];
  const n = 16, seg = w / n;
  for (let i = 0; i < n; i += 1) {
    ctx.fillStyle = seq[i % seq.length];
    ctx.fillRect(x + i * seg, y, seg - 3, h);
  }
}

function wrapLines(ctx: SKRSContext2D, text: string, maxW: number): string[] {
  const words = text.split(/\s+/);
  const lines: string[] = [];
  let cur = "";
  for (const wd of words) {
    const t = (cur + " " + wd).trim();
    if (ctx.measureText(t).width <= maxW) cur = t;
    else { if (cur) lines.push(cur); cur = wd; }
  }
  if (cur) lines.push(cur);
  return lines;
}

function lineHeight(ctx: SKRSContext2D, lh: number): number {
  const m = ctx.measureText("Ag");
  return (m.fontBoundingBoxAscent + m.fontBoundingBoxDescent) * lh;
}

function drawBlock(ctx: SKRSContext2D, text: string, font: string, x: number, y: number, maxW: number, fill: string, lh: number, center: boolean, cx?: number): number {
  ctx.font = font;
  ctx.fillStyle = fill;
  ctx.textBaseline = "top";
  ctx.textAlign = center ? "center" : "left";
  const lines = wrapLines(ctx, text, maxW);
  const lhpx = lineHeight(ctx, lh);
  for (const ln of lines) {
    ctx.fillText(ln, center ? (cx ?? x + maxW / 2) : x, y);
    y += lhpx;
  }
  return y;
}

function cells(ctx: SKRSContext2D, x: number, y: number, n: number, s: number, gap: number, letters: string[] | null, color: string): void {
  const ch = Math.round(s * 1.18);
  for (let i = 0; i < n; i += 1) {
    const cx = x + i * (s + gap);
    roundRect(ctx, cx, y, s, ch, 12);
    ctx.fillStyle = C.S1;
    ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = C.HAIR;
    ctx.stroke();
    if (letters && i < letters.length && letters[i] !== " ") {
      ctx.font = serif(Math.round(s * 0.62));
      ctx.fillStyle = color;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(letters[i], cx + s / 2, y + ch / 2 + 2);
    }
  }
}

function txt(ctx: SKRSContext2D, s: string, x: number, y: number, font: string, fill: string, align: string, baseline: string): void {
  ctx.font = font; ctx.fillStyle = fill;
  (ctx as { textAlign: string }).textAlign = align;
  (ctx as { textBaseline: string }).textBaseline = baseline;
  ctx.fillText(s, x, y);
}

function letterList(answer: string): string[] {
  return [...answer.toUpperCase()].filter((c) => c !== " " && c !== "-" && c !== "'");
}

const W = 1080, H = 1080;

function footer(ctx: SKRSContext2D): void {
  txt(ctx, "@defi_kilimandjaro", W / 2, H - 56, sans(28), C.GOLD, "center", "middle");
}

export type CardSpec =
  | { template: "enigme"; categorie: string; question: string; answer?: string; nbCells?: number; accent?: string }
  | { template: "reponse"; categorie: string; answer: string; explanation: string; accent?: string }
  | { template: "proverbe"; texte: string; source: string }
  | { template: "medaillon"; photo: string; kicker: string; title: string; accent?: string };

function drawMedallion(ctx: SKRSContext2D, img: Awaited<ReturnType<typeof loadImage>>, cx: number, cy: number, size: number): void {
  const r = size / 2 + 8;
  ctx.beginPath(); ctx.ellipse(cx, cy, r + 3, r + 3, 0, 0, Math.PI * 2);
  ctx.lineWidth = 3; ctx.strokeStyle = C.HAIR; ctx.stroke();
  ctx.beginPath(); ctx.ellipse(cx, cy, r, r, 0, 0, Math.PI * 2);
  ctx.lineWidth = 6; ctx.strokeStyle = C.GOLD; ctx.stroke();
  ctx.save();
  ctx.beginPath(); ctx.ellipse(cx, cy, size / 2, size / 2, 0, 0, Math.PI * 2); ctx.clip();
  ctx.drawImage(img, cx - size / 2, cy - size / 2, size, size);
  ctx.restore();
}

export async function renderCard(spec: CardSpec, photoPath?: string): Promise<Buffer> {
  ensureFonts();
  const canvas = createCanvas(W, H);
  const ctx = canvas.getContext("2d") as unknown as SKRSContext2D;

  if (spec.template === "enigme") {
    const accent = ACCENTS[spec.accent || "culture"] || C.GOLD;
    base(ctx, W, H, RGB.kola, 0.12);
    roundRect(ctx, 70, 66, 300, 58, 29); ctx.fillStyle = C.S2; ctx.fill(); ctx.lineWidth = 2; ctx.strokeStyle = C.HAIR; ctx.stroke();
    ctx.beginPath(); ctx.ellipse(102, 96, 10, 10, 0, 0, Math.PI * 2); ctx.fillStyle = accent; ctx.fill();
    txt(ctx, "ÉNIGME", 124, 96, sans(24), C.T1, "left", "middle");
    txt(ctx, spec.categorie.toUpperCase(), W - 70, 96, sans(22), C.GOLD, "right", "middle");
    let y = drawBlock(ctx, spec.question, serif(46), 0, 240, W - 150, C.T1, 1.2, true, W / 2);
    const n = spec.nbCells || letterList(spec.answer || "").length || 6;
    y = Math.max(y + 46, 640);
    const gap = 16;
    const s = Math.min(92, Math.floor((W - 220 - (n - 1) * gap) / Math.max(n, 1)));
    const total = n * s + (n - 1) * gap;
    cells(ctx, (W - total) / 2, y, n, s, gap, null, C.GOLD);
    roundRect(ctx, 90, H - 150, W - 180, 60, 30); ctx.fillStyle = C.S2; ctx.fill(); ctx.lineWidth = 2; ctx.strokeStyle = C.GOLD; ctx.stroke();
    txt(ctx, "TA RÉPONSE EN COMMENTAIRE", W / 2, H - 120, sans(26), C.GOLD, "center", "middle");
    txt(ctx, "@defi_kilimandjaro", W / 2, H - 50, sans(20, "Medium"), C.T3, "center", "middle");
  } else if (spec.template === "reponse") {
    const accent = ACCENTS[spec.accent || "culture"] || C.GOLD;
    void accent;
    base(ctx, W, H, RGB.success, 0.12);
    txt(ctx, ("RÉPONSE · " + spec.categorie).toUpperCase(), W / 2, 150, sans(24), C.T2, "center", "middle");
    const letters = letterList(spec.answer);
    const n = letters.length, gap = 16;
    let rows = [letters];
    let s = Math.min(118, Math.floor((W - 200 - (n - 1) * gap) / Math.max(n, 1)));
    if (s < 90 && n > 6) {
      const h = Math.ceil(n / 2);
      rows = [letters.slice(0, h), letters.slice(h)];
      const m = Math.max(rows[0].length, rows[1].length);
      s = Math.min(118, Math.floor((W - 200 - (m - 1) * gap) / m));
    }
    const ch = Math.round(s * 1.18), rg = 22;
    const tot = rows.length * ch + (rows.length - 1) * rg;
    const y0 = 320;
    rows.forEach((row, ri) => {
      const rw = row.length * s + (row.length - 1) * gap;
      cells(ctx, (W - rw) / 2, y0 + ri * (ch + rg), row.length, s, gap, row, C.SUCCESS);
    });
    drawBlock(ctx, spec.explanation, serifIt(34), 0, y0 + tot + 64, W - 220, C.T1, 1.26, true, W / 2);
    footer(ctx);
  } else if (spec.template === "proverbe") {
    base(ctx, W, H, RGB.gold, 0.15);
    txt(ctx, "“", 90 + 60, 230, serif(220), C.GOLD_DP, "center", "middle");
    let y = drawBlock(ctx, spec.texte, serif(66), 0, 360, W - 220, C.T1, 1.22, true, W / 2);
    y += 36;
    kente(ctx, W / 2 - 150, y, 300); y += 50;
    txt(ctx, spec.source.toUpperCase(), W / 2, y, sans(24), C.GOLD, "center", "middle");
    footer(ctx);
  } else {
    const accent = ACCENTS[spec.accent || "culture"] || C.GOLD;
    base(ctx, W, H, RGB.gold, 0.14);
    if (photoPath) drawMedallion(ctx, await loadImage(photoPath), W / 2, 330, 360);
    txt(ctx, spec.kicker.toUpperCase(), W / 2, 575, sans(26), accent, "center", "middle");
    let y = drawBlock(ctx, spec.title, serif(82), 0, 620, W - 180, C.GOLD, 1.05, true, W / 2);
    y += 18;
    kente(ctx, W / 2 - 150, y, 300);
    footer(ctx);
  }
  return canvas.toBuffer("image/png");
}
