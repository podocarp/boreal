{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f (import nixpkgs { system = s; }));
    in {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.chromium
            pkgs.nodejs
            pkgs.git
            pkgs.python3
            pkgs.python3Packages.playwright
          ];
        };
      });
    };
