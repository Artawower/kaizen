{
  description = "Nix configuration";

  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url   = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url     = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    darwin-login-items.url = "github:uncenter/nix-darwin-login-items";
    zen-browser.url    = "github:youwen5/zen-browser-flake";
    dms.url            = "github:AvengeMedia/DankMaterialShell";
    noctalia.url       = "github:noctalia-dev/noctalia-shell";
  };

  outputs = { self, nix-darwin, nixpkgs, home-manager, darwin-login-items, dms, ... }@inputs:
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
        modules = [
          darwin-login-items.darwinModules.default
          ({ pkgs, ... }: import ./darwin.nix { inherit self pkgs user; })
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
