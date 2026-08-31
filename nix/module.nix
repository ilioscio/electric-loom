{ config, lib, pkgs, ... }:

let
  cfg = config.services.electric-loom;
  inherit (lib) mkEnableOption mkOption mkIf mkDefault types
                optionalString concatStringsSep optionals;

  join = concatStringsSep " ";
  csp = cfg.contentSecurityPolicy;

  # Locked down by default. Everything the application itself needs is here and
  # nothing else, so adding an ad network is a deliberate, visible act: without
  # listing its hosts the browser refuses to load it and says so in the console.
  #
  # 'unsafe-inline' is required because the whole application is one inline
  # <script>; 'unsafe-eval' because the GIF encoder falls back to new Function
  # when workers are unavailable. blob: covers the worker pool.
  cspValue = concatStringsSep "; " [
    "default-src 'none'"
    (join ([ "script-src" "'self'" "'unsafe-inline'" "'unsafe-eval'" "blob:" ] ++ csp.extraScriptSrc))
    "worker-src blob:"
    (join ([ "style-src" "'self'" "'unsafe-inline'" ] ++ csp.extraStyleSrc))
    (join ([ "img-src" "'self'" "data:" "blob:" ] ++ csp.extraImgSrc))
    "media-src 'self' blob:"
    (join ([ "connect-src" "'self'" "blob:" "data:" ] ++ csp.extraConnectSrc))
    (join ([ "frame-src" ] ++ (if csp.extraFrameSrc == [ ] then [ "'none'" ] else csp.extraFrameSrc)))
    "font-src 'self' data:"
    "base-uri 'none'"
    "form-action 'none'"
    "frame-ancestors 'none'"
    "object-src 'none'"
  ];

  # nginx add_header does not inherit into a location that sets its own, so
  # every location below has to repeat these.
  securityHeaders = ''
    ${optionalString csp.enable ''add_header Content-Security-Policy "${cspValue}" always;''}
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "${cfg.referrerPolicy}" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=(), payment=(), usb=()" always;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
  '';

  staticCompression = ''
    ${optionalString cfg.gzipStatic "gzip_static on;"}
    ${optionalString cfg.brotliStatic "brotli_static on;"}
  '';

  site = cfg.package.override {
    inherit (cfg) siteUrl;
    headSnippet = cfg.ads.headSnippet;
    adSnippet = cfg.ads.railSnippet;
    bodySnippet = cfg.ads.bodySnippet;
    tipUrl = cfg.tip.url;
    tipLabel = cfg.tip.label;
    tipNote = cfg.tip.note;
  };
in
{
  options.services.electric-loom = {
    enable = mkEnableOption "the Electric Loom static site served by nginx";

    domain = mkOption {
      type = types.str;
      example = "loom.example.com";
      description = "Virtual host name to serve the site under.";
    };

    package = mkOption {
      type = types.package;
      description = ''
        The Electric Loom package. Must be a callPackage result, because the
        module calls .override on it to bake in the site URL and any ad
        snippets. The flake's nixosModule sets this for you.
      '';
    };

    siteUrl = mkOption {
      type = types.str;
      default = "https://${cfg.domain}";
      defaultText = "https://\${domain}";
      description = ''
        Absolute base URL, used only for the og: and twitter: card tags so
        that link previews resolve. Set to "" to leave them relative.
      '';
    };

    enableACME = mkOption {
      type = types.bool;
      default = true;
      description = "Obtain a certificate for this host with ACME.";
    };

    forceSSL = mkOption {
      type = types.bool;
      default = true;
      description = "Redirect plain HTTP to HTTPS.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open ports 80 and 443 in the firewall.";
    };

    gzipStatic = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Serve the pre-compressed .gz files the build produces instead of
        gzipping on every request. Needs nginx built with
        http_gzip_static_module, which the nixpkgs default is. If your nginx
        is built without it, nginx will refuse the config at rebuild time and
        you should set this to false.
      '';
    };

    brotliStatic = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Serve the pre-compressed .br files. Requires the brotli module, which
        is not in the default nginx build:

          services.nginx.additionalModules = [ pkgs.nginxModules.brotli ];
      '';
    };

    referrerPolicy = mkOption {
      type = types.str;
      default = "no-referrer";
      description = ''
        Referrer-Policy header. Some ad networks want at least
        "strict-origin-when-cross-origin" to attribute traffic.
      '';
    };

    tip = {
      url = mkOption {
        type = types.str;
        default = "";
        example = "https://ko-fi.com/yourname";
        description = ''
          Link for the tip button. Must be http:// or https://; the build
          rejects anything else and the page ignores it a second time at
          runtime, so a typo cannot turn into a javascript: link.

          Empty, the default, means no tip button anywhere.

          Unlike the ad snippets this needs no Content-Security-Policy
          change and loads no third-party code: it is a plain anchor.
        '';
      };
      label = mkOption {
        type = types.str;
        default = "";
        example = "Buy me a coffee";
        description = ''Text on the button. Defaults to "Tip the developer".'';
      };
      note = mkOption {
        type = types.str;
        default = "";
        example = "Built in the open. Tips keep the lights on.";
        description = ''
          One line shown on the card that appears after a render finishes.
          Leave empty for the stock wording.
        '';
      };
    };

    ads = {
      headSnippet = mkOption {
        type = types.lines;
        default = "";
        example = lib.literalExpression ''
          '''
            <script async src="https://example-network.test/loader.js"></script>
          '''
        '';
        description = ''
          HTML injected immediately before </head>. This is where an ad
          network loader, a consent management platform, or analytics goes.

          Whatever hosts it contacts must also be added to
          contentSecurityPolicy.extraScriptSrc and friends, or the browser
          will block them.

          Leaving every snippet empty produces a build that makes no network
          requests at all, which is the default.
        '';
      };

      railSnippet = mkOption {
        type = types.lines;
        default = "";
        description = ''
          HTML injected into the sponsored rail in the right-hand column. The
          rail deletes itself at boot when this is empty, and carries a
          "Sponsored" label when it is not.
        '';
      };

      bodySnippet = mkOption {
        type = types.lines;
        default = "";
        description = "HTML injected at the very end of <body>.";
      };
    };

    contentSecurityPolicy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Send a Content-Security-Policy header.";
      };
      extraScriptSrc = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "https://pagead2.googlesyndication.com" ];
        description = "Extra script-src origins, for an ad or analytics loader.";
      };
      extraStyleSrc = mkOption { type = types.listOf types.str; default = [ ]; description = "Extra style-src origins."; };
      extraImgSrc = mkOption { type = types.listOf types.str; default = [ ]; description = "Extra img-src origins, usually needed for creatives and tracking pixels."; };
      extraConnectSrc = mkOption { type = types.listOf types.str; default = [ ]; description = "Extra connect-src origins, for ad auction XHRs."; };
      extraFrameSrc = mkOption { type = types.listOf types.str; default = [ ]; description = "Extra frame-src origins. Most display ad units are iframes."; };
    };

    extraLocationConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Extra nginx directives inside the main location block.";
    };

    virtualHostConfig = mkOption {
      type = types.attrs;
      default = { };
      description = "Merged into the generated nginx virtual host, for anything not covered above.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = cfg.tip.url == "" || lib.hasPrefix "http://" cfg.tip.url
                                    || lib.hasPrefix "https://" cfg.tip.url;
      message = "services.electric-loom.tip.url must start with http:// or https://";
    }];

    services.nginx = {
      enable = true;
      recommendedGzipSettings = mkDefault true;
      recommendedOptimisation = mkDefault true;
      recommendedTlsSettings = mkDefault true;

      virtualHosts.${cfg.domain} = lib.mkMerge [
        {
          inherit (cfg) enableACME forceSSL;
          root = "${site}";

          locations."/" = {
            index = "index.html";
            extraConfig = ''
              ${securityHeaders}
              ${staticCompression}
              # One file, no content hash in the name, so it must revalidate.
              # It is 56 kB gzipped and a 304 costs nothing.
              add_header Cache-Control "no-cache" always;
              try_files $uri $uri/ =404;
              ${cfg.extraLocationConfig}
            '';
          };

          # Images never change without changing name, so let them sit in cache.
          locations."~* \\.(jpg|jpeg|png|webp|svg|ico|woff2)$" = {
            extraConfig = ''
              ${securityHeaders}
              add_header Cache-Control "public, max-age=604800" always;
            '';
          };

          locations."= /robots.txt" = {
            extraConfig = ''
              ${securityHeaders}
              add_header Cache-Control "public, max-age=86400" always;
            '';
          };
        }
        cfg.virtualHostConfig
      ];
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [ 80 ] ++ optionals cfg.forceSSL [ 443 ];
    };
  };
}
