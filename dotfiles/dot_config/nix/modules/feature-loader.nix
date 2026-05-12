{ config, lib, ... }:

let
  featureDir   = ./features;
  featureFiles = builtins.attrNames (builtins.readDir featureDir);
  nixFiles     = builtins.filter (f: lib.hasSuffix ".nix" f) featureFiles;
  featurePaths = map (f: featureDir + "/${f}") nixFiles;
in

{
  imports = featurePaths;

  home.activation.generateFeatureMeta = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/kaizen"
    cat > "$HOME/.config/kaizen/feature-meta.json" <<'EOF'
    ${builtins.toJSON config.conf.featureRegistry}
    EOF
  '';
}
