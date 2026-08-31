# Host configuration for Electric Loom. Two variants: the plain one, and one
# with a display ad network wired in.

{ pkgs, ... }:

{
  # ---------------------------------------------------------------- plain --
  # No third-party anything. The page makes zero network requests after the
  # initial 50 kB, which is worth keeping if you ever want to say so.
  services.electric-loom = {
    enable = true;
    domain = "loom.example.com";
    openFirewall = true;
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "you@example.com";
  };

  # --------------------------------------------------------------- with ads --
  # Everything below is what you would ADD to the block above. Nothing here is
  # enabled by default, and the network's hosts have to be named twice: once to
  # load the script, once in the Content-Security-Policy. That is deliberate.
  #
  # services.electric-loom = {
  #   referrerPolicy = "strict-origin-when-cross-origin";   # most networks want this
  #
  #   ads.headSnippet = ''
  #     <!-- consent management platform first, if you serve EU or UK traffic -->
  #     <script async src="https://cmp.example-network.test/cmp.js"></script>
  #     <script async crossorigin="anonymous"
  #             src="https://ads.example-network.test/loader.js?id=YOUR-ID"></script>
  #   '';
  #
  #   ads.railSnippet = ''
  #     <ins class="example-ad"
  #          style="display:block;width:100%;min-height:250px"
  #          data-ad-client="YOUR-ID"
  #          data-ad-slot="0000000000"></ins>
  #     <script>(exampleAds = window.exampleAds || []).push({});</script>
  #   '';
  #
  #   contentSecurityPolicy = {
  #     extraScriptSrc  = [ "https://ads.example-network.test" "https://cmp.example-network.test" ];
  #     extraImgSrc     = [ "https:" "data:" ];   # creatives and tracking pixels
  #     extraFrameSrc   = [ "https://ads.example-network.test" ];
  #     extraConnectSrc = [ "https://ads.example-network.test" ];
  #   };
  # };

  # -------------------------------------------------------------- optional --
  # Pre-compressed brotli is about 13% smaller than gzip here (49 kB vs 57 kB)
  # and costs the server nothing at request time, but it needs the module:
  #
  # services.nginx.additionalModules = [ pkgs.nginxModules.brotli ];
  # services.electric-loom.brotliStatic = true;
}
