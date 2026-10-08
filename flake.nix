# SPDX-License-Identifier: MIT
# The nix channel: the package (`nix run` starts hi) and a home-manager module
# that writes the rc block. docs/PACKAGING.md has the user's side.
{
  description = "sshrc supercharged - your shell config, on every host you say hi to";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      # no x86_64-darwin: the pinned nixpkgs refuses to evaluate for it
      forAllSystems = lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # A flake cannot read the tag it was fetched at, so the version is the
      # commit's date and revision; an uncommitted tree has only the date.
      stamp = self.lastModifiedDate or "19700101000000";
      date = "${builtins.substring 0 4 stamp}-${builtins.substring 4 2 stamp}-${builtins.substring 6 2 stamp}";
      version = "0-unstable-${date}-${self.shortRev or self.dirtyShortRev or "dirty"}";
    in
    {
      packages = forAllSystems (
        system:
        let
          say-hi = nixpkgs.legacyPackages.${system}.callPackage ./packaging/nix/package.nix {
            src = self;
            inherit version date;
          };
        in
        {
          inherit say-hi;
          default = say-hi;
        }
      );

      # the package's own install check is the test: `hi --version` out of the store
      checks = forAllSystems (system: {
        inherit (self.packages.${system}) say-hi;
      });

      homeManagerModules.default = import ./packaging/nix/home-manager.nix self;
    };
}
