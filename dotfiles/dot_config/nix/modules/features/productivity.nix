{ pkgs, ... }:
{
  description = "Productivity tools: notes, tasks, time-tracking, voice";
  category    = "productivity";
  packages.darwin.casks = [
    "shottr" "chatgpt" "voiceink" "wakatime" "loom"
    "obsidian" "ticktick" "stretchly" "blankie"
  ];
  packages.linux.nix = with pkgs; [ obsidian wakatime-cli ];
}
