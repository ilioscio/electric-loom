{ lib
, stdenvNoCC
, gzip
, brotli
, nodejs
, writeText

  # Everything below is what an operator can vary without touching the source.
, siteUrl ? ""       # absolute base for og: tags, e.g. "https://loom.example.com"
, headSnippet ? ""   # HTML injected just before </head>  (ad loader, CMP, analytics)
, adSnippet ? ""     # HTML injected into the sponsored rail
, bodySnippet ? ""   # HTML injected at the end of <body>
, runChecks ? true   # run the GIF encoder round-trip suite against the built file
}:

stdenvNoCC.mkDerivation {
  pname = "electric-loom";
  version = "1.1.0";

  # Only the inputs the build actually reads. Keeping dist/ and result out
  # means an uncommitted local build does not change the store hash.
  src = builtins.path {
    path = ../.;
    name = "electric-loom-source";
    filter = path: _type:
      let base = baseNameOf (toString path); in
      base != ".git" && base != "result" && !(lib.hasPrefix "dist" base);
  };

  nativeBuildInputs = [ gzip brotli ] ++ lib.optionals runChecks [ nodejs ];

  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    export OUT="$PWD/site"
    export SITE_URL=${lib.escapeShellArg siteUrl}
    ${lib.optionalString (headSnippet != "")
      ''export HEAD_SNIPPET=${writeText "electric-loom-head.html" headSnippet}''}
    ${lib.optionalString (adSnippet != "")
      ''export AD_SNIPPET=${writeText "electric-loom-ad.html" adSnippet}''}
    ${lib.optionalString (bodySnippet != "")
      ''export BODY_SNIPPET=${writeText "electric-loom-body.html" bodySnippet}''}

    sh ./build.sh

    runHook postBuild
  '';

  doCheck = runChecks;
  checkPhase = ''
    runHook preCheck
    node build/test_gif.js "$PWD/site/index.html"
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r site/. "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Self-contained generator for perfectly looping GIF, WebM and PNG backgrounds";
    longDescription = ''
      A single-page WebGL2 tool that renders seamlessly looping animated
      backgrounds and encodes them to GIF, WebM or a PNG sequence entirely in
      the visitor's browser. The server only ever ships one static file, so
      hosting cost does not scale with how much anyone renders.
    '';
    platforms = lib.platforms.all;
  };
}
