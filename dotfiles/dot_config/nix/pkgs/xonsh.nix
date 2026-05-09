# Xonsh with xontribs — the canonical nixpkgs way.
#
# pkgs.xonsh is a runCommand wrapper around python3.withPackages.
# extraPackages extends that withPackages call, so xontribs land in the same
# Python env and NIX_PYTHONPATH that xonsh itself uses. No makeWrapper needed.
#
# xontrib-sh must use pyproject = true (setuptools PEP 517 build);
# the legacy pyproject = false path silently produces an empty package.
{ pkgs }:

pkgs.xonsh.override {
  extraPackages = ps: [
    (ps.buildPythonPackage rec {
      pname = "xontrib-sh";
      version = "0.3.2";
      pyproject = true;
      src = pkgs.fetchFromGitHub {
        owner = "anki-code";
        repo = "xontrib-sh";
        rev = version;
        hash = "sha256-lojBzxgP+kp4r9FX8OrpSaukz8gVa+MKQYUTX5q+APA=";
      };
      build-system = [ ps.setuptools ];
      dependencies = [ ps.xonsh ];
      doCheck = false;
    })
  ];
}
