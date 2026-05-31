{
  lib,
  user ? {
    autocompleteEngine = "none";
  },
  ...
}:
let
  engine = user.autocompleteEngine or "none";
in
{
  description = "AI inline autocomplete engine";
  category = "ai";

  packages = {
    darwin.taps = lib.optionals (engine == "cotabby") [ "FuJacob/cotabby" ];
    darwin.casks = lib.optionals (engine == "cotabby") [ "cotabby" ];
  };
}
