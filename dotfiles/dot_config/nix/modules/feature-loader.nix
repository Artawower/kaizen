{ config, lib, pkgs, user ? { }, ... }:

let
  featureDir = ./features;
  featureFiles = builtins.filter
    (f: lib.hasSuffix ".nix" f && !lib.hasSuffix ".darwin.nix" f)
    (builtins.attrNames (builtins.readDir featureDir));

  # Platform detection via builtins.currentSystem avoids depending on `pkgs`
  # and thereby avoids the module fixed-point cycle that causes infinite recursion.
  isDarwin = lib.hasSuffix "-darwin" builtins.currentSystem;
  isLinux  = lib.hasSuffix "-linux"  builtins.currentSystem;

  # mkRecipeModule accepts { name, path } so it works for both built-in features
  # (featureDir) and user features (arbitrary paths).
  mkRecipeModule = { name, path }:
    { config, lib, pkgs, user ? { }, ... }:
    let
      recipe = import path { inherit pkgs lib user; };
    in
    if recipe == { } then { }
    else {
      options.conf.features.${name}.enable =
        (lib.mkEnableOption (recipe.description or name)) //
        (lib.optionalAttrs (recipe.defaultEnable or false) { default = true; });

      # Pre-check recipe ? hmConfig outside any lib.mkIf / lib.optionalAttrs:
      # - lib.mkIf content is unconditionally forced by pushDownProperties → "hmConfig missing"
      # - lib.optionalAttrs forces its condition (config.conf.features.X.enable) during
      #   pushDownProperties, causing a fixed-point cycle → infinite recursion
      # Solution: inject the lib.mkIf element into the merge list only when hmConfig exists.
      # recipe ? hmConfig is a pure attrset key-check (no config.X reference, no pkgs).
      config = lib.mkMerge (
        [
          {
            conf.featureRegistry.${name} = {
              description = recipe.description or "";
              category    = recipe.category or "other";
              bump        = recipe.bump or { };
              update      = recipe.update or [ ];
            };
          }
          (lib.mkIf config.conf.features.${name}.enable {
            conf.packages.nix =
              (recipe.packages.nix or [ ]) ++
              (lib.optionals isLinux (recipe.packages.linux.nix or [ ]));

            conf.packages.darwinBrews        = lib.optionals isDarwin (recipe.packages.darwin.brews    or [ ]);
            conf.packages.darwinCasks        = lib.optionals isDarwin (recipe.packages.darwin.casks    or [ ]);
            conf.packages.darwinTaps         = lib.optionals isDarwin (recipe.packages.darwin.taps     or [ ]);
            conf.packages.darwinBrewFormulas =
              lib.optionalString isDarwin (recipe.packages.darwin.brewBundle or "");

            conf.darwin.activationScripts =
              lib.optionalAttrs isDarwin (recipe.activation.darwin or { });

            home.activation =
              lib.optionalAttrs isLinux (
                lib.mapAttrs
                  (_: text: lib.hm.dag.entryAfter [ "writeBoundary" ] text)
                  (recipe.activation.linux or { })
              );
          })
        ]
        # Only append the hmConfig mkIf element when the recipe actually defines hmConfig.
        # This avoids pushDownProperties forcing recipe.hmConfig for recipes that lack it.
        ++ lib.optional (recipe ? hmConfig) (
          lib.mkIf config.conf.features.${name}.enable
            (recipe.hmConfig { inherit lib isDarwin isLinux; })
        )
      );
    };

  builtinRecipes = map
    (fileName: mkRecipeModule {
      name = lib.removeSuffix ".nix" fileName;
      path = featureDir + "/${fileName}";
    })
    featureFiles;

  # User features: auto-detect recipe vs legacy HM module via functionArgs.
  # Legacy modules declare `config` as a formal parameter; recipes do not.
  userFeaturesPath = "${builtins.getEnv "HOME"}/.config/kaizen/user-features";
  userNixFiles =
    if builtins.pathExists userFeaturesPath then
      builtins.filter (f: lib.hasSuffix ".nix" f && !lib.hasSuffix ".darwin.nix" f)
        (builtins.attrNames (builtins.readDir userFeaturesPath))
    else
      [ ];

  userModules =
    if builtins.pathExists userFeaturesPath then
      map (fileName:
        let path = userFeaturesPath + "/${fileName}"; in
        if (builtins.functionArgs (import path)) ? config
        then path
        else mkRecipeModule {
          name = lib.removeSuffix ".nix" fileName;
          inherit path;
        }
      ) userNixFiles
    else
      [ ];
in

{
  imports = builtinRecipes ++ userModules;

  home.activation.generateFeatureMeta = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/kaizen"
    cat > "$HOME/.config/kaizen/feature-meta.json" <<'EOF'
    ${builtins.toJSON config.conf.featureRegistry}
    EOF
  '';

  home.activation.generateDarwinDeps = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/kaizen"
    cat > "$HOME/.config/kaizen/darwin-deps.json" <<'DARWIN_EOF'
    ${builtins.toJSON {
      brews             = config.conf.packages.darwinBrews;
      casks             = config.conf.packages.darwinCasks;
      taps              = config.conf.packages.darwinTaps;
      brewFormulas      = config.conf.packages.darwinBrewFormulas;
      activationScripts = config.conf.darwin.activationScripts;
    }}
    DARWIN_EOF
  '';
}
