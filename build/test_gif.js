/* Round-trip test for the GIF engine embedded in index.html.
   Extracts ALGO_SRC + the container helpers, encodes a synthetic animation,
   then decodes the LZW back and compares against the quantized indices. */
const fs = require('fs');
const path = require('path');
// default to the committed single file; the Nix build points this at the
// freshly built site so the check exercises what actually ships
const target = process.argv[2] || path.join(__dirname, '..', 'index.html');
const html = fs.readFileSync(target, 'utf8');

/* ---- pull ALGO_SRC ---- */
const a0 = html.indexOf('const ALGO_SRC = String.raw`');
const a1 = html.indexOf('\n`;', a0);
if (a0 < 0 || a1 < 0) throw new Error('ALGO_SRC not found');
const ALGO_SRC = html.slice(a0 + 'const ALGO_SRC = String.raw`'.length, a1);
const ALGO = new Function(ALGO_SRC + '\nreturn {buildPalette:buildPalette, encodeFrame:encodeFrame, lzw:lzw};')();

/* ---- pull the container helpers ---- */
const c0 = html.indexOf('/* ---- GIF container assembly ---- */');
const c1 = html.indexOf('/* =====================================================================\n   EXPORT', c0);
if (c0 < 0 || c1 < 0) throw new Error('container helpers not found');
const CONT_SRC = html.slice(c0, c1);
const CONT = new Function('clamp',
  CONT_SRC + '\nreturn {gifHeader:gifHeader, gifFrameHeader:gifFrameHeader, delayTable:delayTable};'
)((v, a, b) => v < a ? a : v > b ? b : v);

let fails = 0;
function ok(cond, msg) { if (!cond) { console.log('  FAIL  ' + msg); fails++; } else console.log('  ok    ' + msg); }

/* =================================================================== */
console.log('\n1. delayTable: integer centiseconds that sum to the exact duration');
for (const [N, dur] of [[96, 4], [90, 3], [72, 3], [45, 1.5], [150, 5], [360, 12], [25, 1], [1, 1], [450, 15]]) {
  const d = CONT.delayTable(N, dur);
  let s = 0, mn = 1e9, mx = 0;
  for (const v of d) { s += v; mn = Math.min(mn, v); mx = Math.max(mx, v); }
  ok(s === Math.round(dur * 100), N + ' frames / ' + dur + 's -> sum ' + s + ' cs (want ' + Math.round(dur * 100) + '), delays ' + mn + '-' + mx);
  ok(mn >= 1, '  no zero-length frames (min ' + mn + ')');
}

/* =================================================================== */
console.log('\n2. LZW round trip against an independent decoder');
function lzwDecode(bytes) {
  let p = 0;
  const minCode = bytes[p++];
  const data = [];
  for (;;) { const len = bytes[p++]; if (!len) break; for (let i = 0; i < len; i++) data.push(bytes[p++]); }
  const clear = 1 << minCode, eoi = clear + 1;
  let codeSize, next, dict;
  const reset = () => {
    dict = new Array(4096);
    for (let i = 0; i < clear; i++) dict[i] = [i];
    dict[clear] = null; dict[eoi] = null;
    next = eoi + 1; codeSize = minCode + 1;
  };
  reset();
  let bitPos = 0;
  const out = [];
  const read = () => {
    let v = 0;
    for (let i = 0; i < codeSize; i++) {
      const byte = data[bitPos >> 3];
      if (byte === undefined) return -1;
      v |= ((byte >> (bitPos & 7)) & 1) << i;
      bitPos++;
    }
    return v;
  };
  let prev = null;
  for (;;) {
    const code = read();
    if (code < 0) break;
    if (code === clear) { reset(); prev = null; continue; }
    if (code === eoi) break;
    let entry;
    if (dict[code]) entry = dict[code];
    else if (code === next && prev) entry = prev.concat([prev[0]]);
    else { out.push(-999); break; }
    for (let i = 0; i < entry.length; i++) out.push(entry[i]);
    if (prev) {
      dict[next++] = prev.concat([entry[0]]);
      if (next === (1 << codeSize) && codeSize < 12) codeSize++;
    }
    prev = entry;
  }
  return out;
}

function testLzw(name, pixels, minCodeSize) {
  const enc = ALGO.lzw(pixels, minCodeSize);
  const dec = lzwDecode(enc);
  let same = dec.length === pixels.length;
  if (same) for (let i = 0; i < pixels.length; i++) if (dec[i] !== pixels[i]) { same = false; console.log('   first mismatch at ' + i + ': got ' + dec[i] + ' want ' + pixels[i]); break; }
  ok(same, name + '  (' + pixels.length + ' px -> ' + enc.length + ' B, ratio ' +
    (pixels.length / enc.length).toFixed(2) + 'x)');
  return enc;
}
{
  const n = 640 * 360;
  const flat = new Uint8Array(n);                       // all one colour: extreme run lengths
  testLzw('flat field, 8-bit', flat, 8);
  const grad = new Uint8Array(n);
  for (let i = 0; i < n; i++) grad[i] = (i % 640) * 255 / 640 | 0;
  testLzw('horizontal ramp, 8-bit', grad, 8);
  const noise = new Uint8Array(n);
  let s = 12345;
  for (let i = 0; i < n; i++) { s = (s * 1103515245 + 12345) & 0x7fffffff; noise[i] = s & 255; }
  testLzw('white noise, 8-bit (forces table resets)', noise, 8);
  const small = new Uint8Array(n);
  for (let i = 0; i < n; i++) small[i] = i & 3;
  testLzw('4 colours, 2-bit min code', small, 2);
  const sixteen = new Uint8Array(n);
  for (let i = 0; i < n; i++) sixteen[i] = (i * 7) & 15;
  testLzw('16 colours, 4-bit min code', sixteen, 4);
  testLzw('single pixel', new Uint8Array([5]), 8);
  testLzw('two pixels', new Uint8Array([5, 5]), 8);
  // long enough to blow past 4096 codes several times
  const big = new Uint8Array(1920 * 1080);
  s = 999;
  for (let i = 0; i < big.length; i++) { s = (s * 1103515245 + 12345) & 0x7fffffff; big[i] = (s >> 7) & 255; }
  testLzw('1920x1080 noise (multiple clear codes)', big, 8);
}

/* =================================================================== */
console.log('\n3. palette build + dither + full frame round trip');
function synthFrame(W, H, t) {
  const px = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    const u = x / W, v = y / H;
    const a = Math.sin((u * 8 + t * 6.283)) * 0.5 + 0.5;
    const b = Math.sin((v * 6 - t * 6.283)) * 0.5 + 0.5;
    const c = Math.sin(((u + v) * 5 + t * 12.566)) * 0.5 + 0.5;
    px[i] = a * 255; px[i + 1] = b * 200 + 30; px[i + 2] = c * 255; px[i + 3] = 255;
  }
  return px;
}
{
  const W = 320, H = 180, N = 8;
  const hist = new Uint32Array(262144);
  for (let f = 0; f < N; f++) {
    const px = synthFrame(W, H, f / N);
    for (let p = 0; p < px.length; p += 4)
      hist[((px[p] >> 2) << 12) | ((px[p + 1] >> 2) << 6) | (px[p + 2] >> 2)]++;
  }
  for (const K of [256, 64, 16, 8, 4]) {
    const t0 = Date.now();
    const r = ALGO.buildPalette(hist, K, K <= 64);
    ok(r.pal.length === K * 3, 'palette K=' + K + ' has ' + K + ' entries (' + (Date.now() - t0) + ' ms, ' + r.used + ' used)');
    let cacheOk = true;
    for (let i = 0; i < 262144; i += 977) if (r.cache[i] >= K) { cacheOk = false; break; }
    ok(cacheOk, '  cache indices all < K');
    const tableSize = Math.max(4, 1 << Math.ceil(Math.log2(Math.max(2, K))));
    const mcs = Math.max(2, Math.round(Math.log2(tableSize)));
    for (const dither of ['fs', 'sierra', 'atkinson', 'bayer8', 'bayer4', 'none']) {
      const px = synthFrame(W, H, 0.3);
      const bytes = ALGO.encodeFrame(px, W, H, r.pal, r.cache, dither, 0.9, -1, 128, mcs);
      const dec = lzwDecode(bytes);
      let good = dec.length === W * H;
      if (good) for (let i = 0; i < dec.length; i++) if (dec[i] < 0 || dec[i] >= tableSize) { good = false; break; }
      ok(good, '  ' + dither.padEnd(9) + ' -> ' + String(bytes.length).padStart(7) + ' B, decodes to ' + dec.length + ' px');
    }
  }
}

/* =================================================================== */
console.log('\n4. transparency path');
{
  const W = 160, H = 90;
  const px = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4;
    px[i] = x * 255 / W; px[i + 1] = y * 255 / H; px[i + 2] = 128;
    px[i + 3] = (x - W / 2) * (x - W / 2) + (y - H / 2) * (y - H / 2) < 900 ? 255 : 0;
  }
  const hist = new Uint32Array(262144);
  for (let p = 0; p < px.length; p += 4) if (px[p + 3] >= 128)
    hist[((px[p] >> 2) << 12) | ((px[p + 1] >> 2) << 6) | (px[p + 2] >> 2)]++;
  const K = 128;
  const r = ALGO.buildPalette(hist, K, true);
  const transIdx = K, tableSize = 256, mcs = 8;
  const bytes = ALGO.encodeFrame(px, W, H, r.pal, r.cache, 'fs', 0.9, transIdx, 128, mcs);
  const dec = lzwDecode(bytes);
  ok(dec.length === W * H, 'transparent frame decodes to ' + dec.length + ' px');
  let transCount = 0, opaqueWrong = 0;
  for (let i = 0; i < dec.length; i++) {
    const isT = px[i * 4 + 3] < 128;
    if (isT) { if (dec[i] === transIdx) transCount++; else opaqueWrong++; }
    else if (dec[i] === transIdx) opaqueWrong++;
  }
  ok(opaqueWrong === 0, 'every alpha<128 pixel is index ' + transIdx + ' and no opaque pixel is (' + transCount + ' transparent px)');
}

/* =================================================================== */
console.log('\n5. write a real .gif and sanity check the bytes');
{
  const W = 240, H = 135, N = 12, dur = 1.0;
  const hist = new Uint32Array(262144);
  for (let f = 0; f < N; f++) {
    const px = synthFrame(W, H, f / N);
    for (let p = 0; p < px.length; p += 4)
      hist[((px[p] >> 2) << 12) | ((px[p + 1] >> 2) << 6) | (px[p + 2] >> 2)]++;
  }
  const K = 256;
  const r = ALGO.buildPalette(hist, K, true);
  const delays = CONT.delayTable(N, dur);
  const parts = [Buffer.from(CONT.gifHeader(W, H, r.pal, 256, 0))];
  for (let f = 0; f < N; f++) {
    const px = synthFrame(W, H, f / N);
    parts.push(Buffer.from(CONT.gifFrameHeader(W, H, delays[f], -1)));
    parts.push(Buffer.from(ALGO.encodeFrame(px, W, H, r.pal, r.cache, 'fs', 0.9, -1, 128, 8)));
  }
  parts.push(Buffer.from([0x3B]));
  const gif = Buffer.concat(parts);
  fs.writeFileSync(path.join(__dirname, 'roundtrip.gif'), gif);
  ok(gif.slice(0, 6).toString('latin1') === 'GIF89a', 'signature GIF89a');
  ok(gif[10] === 0xF7, 'logical screen packed byte 0xF7 (global table, 256 entries), got 0x' + gif[10].toString(16));
  ok(gif.readUInt16LE(6) === W && gif.readUInt16LE(8) === H, 'canvas ' + gif.readUInt16LE(6) + 'x' + gif.readUInt16LE(8));
  const netscape = gif.indexOf(Buffer.from('NETSCAPE2.0', 'latin1'));
  ok(netscape > 0, 'NETSCAPE2.0 loop extension present at ' + netscape);
  ok(gif[netscape + 11] === 0x03 && gif[netscape + 12] === 0x01 &&
     gif.readUInt16LE(netscape + 13) === 0, 'loop count 0 = forever');
  ok(gif[gif.length - 1] === 0x3B, 'trailer 0x3B');
  // walk every block to prove the structure parses end to end
  let p = 13 + 768, frames = 0, walkOk = true, totalDelay = 0;
  p += 19; // netscape ext
  while (p < gif.length) {
    if (gif[p] === 0x3B) break;
    if (gif[p] === 0x21 && gif[p + 1] === 0xF9) {
      totalDelay += gif.readUInt16LE(p + 4);
      p += 8;
      if (gif[p] !== 0x2C) { walkOk = false; break; }
      p += 10;
      p++; // min code size
      for (;;) { const l = gif[p++]; if (!l) break; p += l; }
      frames++;
    } else { walkOk = false; break; }
  }
  ok(walkOk && frames === N, 'walked ' + frames + '/' + N + ' image blocks cleanly');
  ok(totalDelay === Math.round(dur * 100), 'delays in the file sum to ' + totalDelay + ' cs = ' + dur + 's');
  console.log('  wrote build/roundtrip.gif  (' + (gif.length / 1024).toFixed(1) + ' KB)');
}

console.log('\n' + (fails ? fails + ' FAILURE(S)' : 'ALL PASS'));
process.exit(fails ? 1 : 0);
