{ config, lib, ... }:

let
  featureDir = ./features;
  featureFiles = builtins.attrNames (builtins.readDir featureDir);
  nixFiles = builtins.filter (
    f: lib.hasSuffix ".nix" f && !lib.hasSuffix ".darwin.nix" f
  ) featureFiles;
  featurePaths = map (f: featureDir + "/${f}") nixFiles;

  userFeaturesPath = "${builtins.getEnv "HOME"}/.config/kaizen/user-features";
  userNixFiles =
    if builtins.pathExists userFeaturesPath then
      builtins.filter (f: lib.hasSuffix ".nix" f && !lib.hasSuffix ".darwin.nix" f) (
        builtins.attrNames (builtins.readDir userFeaturesPath)
      )
    else
      [ ];
  userFeaturePaths = map (f: userFeaturesPath + "/${f}") userNixFiles;
in

{
  imports = featurePaths ++ userFeaturePaths;

  home.activation.generateFeatureMeta = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/kaizen"
    cat > "$HOME/.config/kaizen/feature-meta.json" <<'EOF'
    ${builtins.toJSON config.conf.featureRegistry}
    EOF
  '';
}
