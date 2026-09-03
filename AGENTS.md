# Notes for whoever works on this next

Electric Loom renders seamlessly looping animated backgrounds and encodes them
to GIF, WebM or PNG **entirely in the browser**. The server hands over one
static file and does nothing else. Read `README.md` for what it does; this file
is about how not to break it, and how to switch on the money.

---

## Rules that are not style preferences

**Never edit `index.html` by hand.** It is generated. Edit the numbered parts
in `build/` and regenerate:

```bash
OUT=. SINGLE_FILE=1 ./build.sh     # rewrites the committed index.html
node build/test_gif.js             # GIF encoder round-trip suite
```

`build.sh` is the single source of truth. The Nix derivation calls it and
`build.cmd` either delegates to it or reproduces it byte for byte.

**The loop rule.** Time enters a pattern only as `TA = 2*PI*t`, and every
coefficient multiplying it must be an integer. UI controls for those use `PI_`
(integer-stepped), not `P`. If you add a pattern or a control that varies with
time and you use `P`, you have quietly broken the loop for everyone.

**Theatre mode is the one place the loop rule does not apply, on purpose.**
`build/p09b_theatre.txt` is a fullscreen live viewer. Its slideshow blends two
different looks with transition shaders (`TRANS_FS`), which are cross-fades by
definition. That is allowed *only because theatre never exports anything* - it
is a view, not an encode. Do not "fix" the cross-fades to obey the seam, and do
not wire an export through theatre without first solving the fact that a
two-look transition cannot be a perfect loop. Theatre borrows the single `#gl`
canvas by re-parenting it into an overlay on enter and returning it on exit; it
renders through the same `render()` via the `RENDER_TARGET` hook (composite to
an FBO instead of the canvas) so look A and look B can be captured and mixed.
The build order matters: `p09b_theatre.txt` is concatenated **after**
`p09_export.txt` and **before** `p10_boot.txt` in both `build.sh` and the
`build.cmd` fallback list.

**Theatre audio reactivity lives in `build/p09c_audio.txt`** (concatenated
right after `p09b_theatre.txt`, same two files to update). Mic or tab audio
is analysed locally with an `AnalyserNode` into a few auto-gained channels
that perturb the current look per frame. Three rules keep it honest:

- **Audio never binds an `x/loop` control.** Those are coefficients on `TA`;
  bending one between frames jumps the phase `t*rate` and reads as a glitch,
  not a beat. `audioBindsFor()` refuses such a binding loudly — do not relax
  that check, extend `AUDIO_BINDS` with structural params only.
- **Looks stay immutable.** `audioApply()` installs perturbed *scratch
  copies* over `S` after `applyLookForRender`; history entries, the exit
  snapshot and the export path never see an audio-bent value.
- **Nothing leaves the page.** The stream feeds analysis only, is never
  recorded, and is released on theatre exit — the zero-network-requests
  claim in `p10_boot.txt` still holds. Keep it that way.

Auto-gain means no user calibration: each band is read against its own
rolling floor/peak, with a span gate so a silent room sits at zero. If a
new pattern is added, give it an `AUDIO_BINDS` entry (bass on its most
structural knob is the house recipe); patterns without one still get the
global bloom/exposure/zoom pulse.

**Three traps that already bit, documented so they do not bite again:**

- `mod()` is unreliable on real drivers. `mod(6.0, 6.0)` returns `6.0` where
  the reciprocal rounds down. Use `imod()` from the shader prelude for anything
  a tile index depends on.
- Wrap `t` *before* adding an LFO phase. `wrap1(1 + phase)` and
  `wrap1(0 + phase)` differ by one ULP, and `Math.round` turns that into a
  whole step on an integer control.
- Grain must be indexed modulo the frame count, and rotations wrapped to one
  turn, or the mantissa drains as spin counts climb.

**Temporal controls must be named `... x/loop`.** This is no longer only a
readability convention. `Speed` decides what to multiply by testing the label
against `/x\/loop/` (see `isTempo` in `p06_engine.txt`), so a rate whose label
omits it will be silently left out of Speed, and a structural control whose
label wrongly includes it will be scaled and deform the pattern. When adding a
control that multiplies `TA`, name it accordingly and check it appears in the
tagged set.

**The narrow-screen layout depends on two things** that are easy to undo by
accident: `.col` must be `overflow: visible` under the media query, or the
sticky preview stops sticking; and `.canvasWrap` must be `flex: 0 0 auto`
there, or its `flex-basis: 0` beats the `height` and the preview collapses to
its minimum. Both have already been fixed once.

**The default build makes zero network requests.** That is a property worth
keeping, and it is load-bearing for the in-app help text, which claims it. If
you add anything that phones home, the claim in `p10_boot.txt` must change too.

---

## Verifying a change

Beyond `node build/test_gif.js`, the useful checks run in a browser. Serve the
built site with production headers and drive it from the console:

```bash
OUT=dist ./build.sh
python3 build/headertest.py 8778 dist     # sends the exact headers the module sets
```

`build/headertest.py` mirrors `nix/module.nix`. **If you change the CSP in the
module, change it there too** — it is the only way to test the policy without a
NixOS box, and it has already caught one boot-killing bug.

The loop guarantee itself is checked in-page. Roughly:

```js
S.gen = 'warp';
render(0, 200, 112, 2); const a = readFrame(200, 112);
render(1, 200, 112, 2); const b = readFrame(200, 112);
// worst |a-b| should be <= 2 across every generator
```

And for modulators, `modSeamError(m, S.tempo.speed)` must stay under `1e-4`.

**The Flame Fractal is a special case.** It is a chaos game, so any float
difference in its coefficients is amplified exponentially over the iteration.
`TA` reaches the shader as a float32, so at `t=1` the flame can report a large
strict probe while being perfectly seamless — measured at 32/255 probe against
a seam continuity of 0.83x an ordinary frame step. Every resolved parameter
and uniform was confirmed identical at both ends, and the render is
deterministic. Judge the flame by the ratio, never by the probe. Note that the
in-app **Verify loop** reports two numbers on purpose: the strict `t=0` vs
`t=1` pixel probe over-reports at extreme settings (float32 phase error in the
shader reads as a sub-pixel shift), so the headline is seam continuity against
an ordinary frame step. Do not "fix" a large probe number by wrapping `t` in
`render()` — that would make the test vacuous rather than the loop better.

---

## Runbook: turn on the tip link

The cheapest money. It is a plain `<a href>`: no third-party script, no CSP
change, no consent banner, nothing to review.

1. Get a link — Ko-fi, Buy Me a Coffee, GitHub Sponsors, Liberapay, a Stripe
   payment link. Anything `https://`.

2. Set it in the host config:

```nix
services.electric-loom.tip = {
  url   = "https://ko-fi.com/yourname";
  label = "Buy me a coffee";              # optional
  note  = "Built solo, given away free."; # optional, shown on the card
};
```

3. Rebuild and check: a button appears in the header, and a dismissible card
   appears in the export panel **after a render finishes** — the moment the
   visitor has just got something for nothing. It shows once per session and
   stays dismissed for 60 days.

To test locally without Nix:

```bash
OUT=dist-tip TIP_URL="https://ko-fi.com/you" TIP_LABEL="Buy me a coffee" ./build.sh
```

Guardrails already in place: the URL must be `http://` or `https://` (the build
exits non-zero otherwise, and the page re-checks at runtime so a typo cannot
become a `javascript:` link), and the label and note are HTML-attribute escaped.

---

## Runbook: turn on ads

Harder, and read the "If you monetise it" section of `README.md` before
starting — a single-page tool is a poor shape for display advertising and this
audience blocks it heavily.

1. **Add content first.** Ad networks reject single-app-screen sites as "low
   value content". A gallery of example loops, OBS setup notes and real docs
   help with the review and with search traffic. Do this before applying.

2. **Get a consent management platform** if any EU or UK traffic is expected.
   Personalised ads there require a certified CMP, and it must load *before*
   the ad script — that is why `headSnippet` is a single ordered block.

3. **Wire it in.** Two places, deliberately:

```nix
services.electric-loom = {
  referrerPolicy = "strict-origin-when-cross-origin";   # most networks want this

  ads.headSnippet = ''
    <script async src="https://cmp.NETWORK.example/cmp.js"></script>
    <script async crossorigin="anonymous" src="https://ads.NETWORK.example/loader.js?id=ID"></script>
  '';
  ads.railSnippet = ''
    <ins class="..." data-ad-client="ID" data-ad-slot="SLOT"></ins>
    <script>(adsQueue = window.adsQueue || []).push({});</script>
  '';

  contentSecurityPolicy = {
    extraScriptSrc  = [ "https://ads.NETWORK.example" "https://cmp.NETWORK.example" ];
    extraFrameSrc   = [ "https://ads.NETWORK.example" ];   # display units are iframes
    extraImgSrc     = [ "https:" "data:" ];                # creatives, tracking pixels
    extraConnectSrc = [ "https://ads.NETWORK.example" ];
  };
};
```

**If you forget the CSP entries the ad silently does not load.** That is the
designed behaviour, not a bug. The browser console says exactly which directive
blocked it; check there first.

4. **Verify**, with `build/headertest.py` and the browser console:
   - the app still boots — `document.querySelectorAll('#vidCodec option').length > 0`
     is a good one-line proxy, because boot aborting leaves every control dead
     while the page still *looks* fine;
   - `#adSec` is visible and carries its "Sponsored" label;
   - no CSP violations in the console;
   - a GIF export still completes.

5. **Do not auto-refresh the unit on export completion.** It is tempting — it
   is a real attention beat — but refreshing outside a network's supported
   mechanism breaks most programme policies.

### Things that will go wrong

- **Injected markup with `class="sec"`** used to kill boot, because
  `wireSections()` dereferenced a missing `.head`. It is guarded now, but keep
  injected markup dumb: a container and the network's own tags.
- **Ad scripts are slow and occasionally throw.** They load `async` and sit
  outside the render loop, so they cannot stall a render. Keep it that way.
- **The rail is `#adRail`.** It deletes itself at boot when empty. If you add a
  second slot, follow the same pattern — absent by default, never a hole in the
  layout.

---

## Known-untested

There is **no `nix` and no `nginx`** on the machine this was built on.
`flake.nix`, `nix/package.nix` and `nix/module.nix` were checked for balanced
brackets and terminated strings by a purpose-written tokeniser, **not
evaluated**. Expect to shake out semantics on the first `nixos-rebuild`. The
likeliest snag is `gzipStatic`, which needs `http_gzip_static_module`; set it
`false` if nginx rejects the config.

The CSP, the cache headers, the ad injection and the tip link **were** all
exercised against a real browser.

There is no `LICENSE`. Deliberate, for now.
