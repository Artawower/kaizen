{
  description = "Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.url = "github:youwen5/zen-browser-flake";
    dms.url = "github:AvengeMedia/DankMaterialShell";
    noctalia.url = "github:noctalia-dev/noctalia-shell";
  };

  outputs =
    {
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      baseUser = import ./user.nix;
      currentSystem = if builtins ? currentSystem then builtins.currentSystem else "";
      isDarwin = nixpkgs.lib.hasSuffix "-darwin" currentSystem;
      envHome = builtins.getEnv "HOME";
      envUser = builtins.getEnv "USER";
      envSudoUser = builtins.getEnv "SUDO_USER";
      envKaizenHome = builtins.getEnv "KAIZEN_HOME";
      envKaizenUser = builtins.getEnv "KAIZEN_USER";
      usableUser = name: name != "" && name != "root";
      username =
        if usableUser envKaizenUser then
          envKaizenUser
        else if usableUser envUser then
          envUser
        else if usableUser envSudoUser then
          envSudoUser
        else if usableUser (baseNameOf envHome) then
          baseNameOf envHome
        else
          baseUser.username;
      homeDirectory =
        if envKaizenHome != "" then
          envKaizenHome
        else if envHome != "" && baseNameOf envHome == username then
          envHome
        else
          baseUser.homeDirectory or (if isDarwin then "/Users/${username}" else "/home/${username}");
      user = baseUser // {
        inherit username homeDirectory;
      };
      darwinSystem = if isDarwin then currentSystem else "aarch64-darwin";

      mkDarwinHome =
        system: extraModules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          modules = [
            { _module.args = { inherit user; }; }
          ]
          ++ extraModules;
        };

      mkLinuxHome =
        system: extraModules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              # Obsidian pins an EOL electron that nixpkgs marks insecure. Allow it
              # explicitly (version-resilient, unlike permittedInsecurePackages).
              allowInsecurePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "electron" ];
            };
          };
          extraSpecialArgs = { inherit inputs; };
          modules = [
            { _module.args = { inherit user; }; }
          ]
          ++ extraModules;
        };

      darwinConfiguration = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit self user darwinSystem; };
        modules = [
          ./darwin.nix
        ];
      };
    in
    {
      darwinConfigurations = {
        mac = darwinConfiguration;
      }
      // nixpkgs.lib.optionalAttrs (user.hostname != "mac") {
        ${user.hostname} = darwinConfiguration;
      };

      homeConfigurations = {
        "${user.username}@mac" = mkDarwinHome darwinSystem [
          ./hosts/mac.nix
        ];

        "${user.username}@linux" = mkLinuxHome "aarch64-linux" [
          ./hosts/linux.nix
        ];
      };
    };
}
