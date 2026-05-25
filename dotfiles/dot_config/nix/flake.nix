{
  description = "Nix configuration";

  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url   = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url     = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.url    = "github:youwen5/zen-browser-flake";
    dms.url            = "github:AvengeMedia/DankMaterialShell";
    noctalia.url       = "github:noctalia-dev/noctalia-shell";
  };

  outputs = { self, nix-darwin, nixpkgs, home-manager, dms, ... }@inputs:
    let
      user = import ./user.nix;

      mkDarwinHome = system: extraModules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          modules = [
            { _module.args = { inherit user; }; }
          ] ++ extraModules;
        };

      mkLinuxHome = system: extraModules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          extraSpecialArgs = { inherit inputs; };
          modules = [
            { _module.args = { inherit user; }; }
          ] ++ extraModules;
        };
    in
    {
      darwinConfigurations.${user.hostname} = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit self user; };
        modules = [
          ./darwin.nix
        ];
      };

      homeConfigurations = {
        "${user.username}@mac" = mkDarwinHome "aarch64-darwin" [
          ./hosts/mac.nix
        ];

        "${user.username}@linux" = mkLinuxHome "aarch64-linux" [
          ./hosts/linux.nix
        ];
      };
    };
}
