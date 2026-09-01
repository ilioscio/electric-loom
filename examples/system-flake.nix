# Example NixOS system flake that serves Electric Loom.
#
# Copy this into your own configuration; the only parts that matter are the
# electric-loom input and the two lines in the modules list.

{
  description = "example host serving Electric Loom";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # From GitHub:
    electric-loom.url = "github:ilioscio/electric-loom";
    # ...or from your own git remote:
    # electric-loom.url = "git+https://git.example.com/electric-loom.git";
    # ...or a local checkout while you are iterating:
    # electric-loom.url = "path:/home/you/src/electric-loom";

    # Optional but recommended: build it against the same nixpkgs as the host
    # so you are not pulling a second copy of the world into the closure.
    electric-loom.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, electric-loom, ... }: {
    nixosConfigurations.web = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        electric-loom.nixosModules.default
        ./electric-loom-host.nix
        # ...the rest of your host configuration
      ];
    };
  };
}
