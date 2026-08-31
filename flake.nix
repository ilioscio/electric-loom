{
  description = "Electric Loom - perfectly looping GIF, WebM and PNG backgrounds, rendered entirely in the browser";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems
        (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (system: pkgs: rec {
        electric-loom = pkgs.callPackage ./nix/package.nix { };
        default = electric-loom;
      });

      # final.callPackage so the package composes with other overlays
      overlays.default = final: _prev: {
        electric-loom = final.callPackage ./nix/package.nix { };
      };

      # Importable as inputs.electric-loom.nixosModules.default
      nixosModules.electric-loom = { pkgs, lib, ... }: {
        imports = [ ./nix/module.nix ];
        services.electric-loom.package =
          lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.electric-loom;
      };
      nixosModules.default = self.nixosModules.electric-loom;

      # nix flake check builds the site and runs the GIF encoder round-trip
      # suite against the file that would actually be served.
      checks = forAll (system: pkgs: {
        build-and-test = self.packages.${system}.electric-loom;
      });

      # nix run .# -- [port]
      apps = forAll (system: pkgs: rec {
        preview = {
          type = "app";
          program = "${pkgs.writeShellApplication {
            name = "electric-loom-preview";
            runtimeInputs = [ pkgs.python3 ];
            text = ''
              port="''${1:-8777}"
              echo "Electric Loom on http://127.0.0.1:$port"
              cd "${self.packages.${system}.electric-loom}"
              exec python3 -m http.server "$port" --bind 127.0.0.1
            '';
          }}/bin/electric-loom-preview";
        };
        default = preview;
      });

      devShells = forAll (system: pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.nodejs pkgs.python3 pkgs.gzip pkgs.brotli ];
          shellHook = ''
            echo "Electric Loom dev shell"
            echo "  OUT=dist ./build.sh            build the site"
            echo "  OUT=. SINGLE_FILE=1 ./build.sh regenerate the committed index.html"
            echo "  node build/test_gif.js         run the GIF encoder tests"
            echo "  python3 build/headertest.py    serve dist/ with production headers"
          '';
        };
      });

      formatter = forAll (_system: pkgs: pkgs.nixpkgs-fmt);
    };
}
