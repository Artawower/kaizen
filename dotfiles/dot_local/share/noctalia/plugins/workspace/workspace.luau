local command = 'if [ -n "$MANGO_INSTANCE_SIGNATURE" ] && command -v mmsg >/dev/null 2>&1; then mmsg get all-monitors 2>/dev/null | jq -r \'.monitors[] | select(.active) | .active_tags[0] // empty\'; elif [ -n "$NIRI_SOCKET" ] && command -v niri >/dev/null 2>&1; then niri msg -j workspaces 2>/dev/null | jq -r \'.[] | select(.is_active) | (.name // .idx) // empty\'; elif [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && command -v hyprctl >/dev/null 2>&1; then hyprctl activeworkspace -j 2>/dev/null | jq -r \'.name // .id // empty\'; elif [ -n "$SWAYSOCK" ] && command -v swaymsg >/dev/null 2>&1; then swaymsg -t get_workspaces 2>/dev/null | jq -r \'.[] | select(.focused) | .name // empty\'; elif command -v mmsg >/dev/null 2>&1; then mmsg get all-monitors 2>/dev/null | jq -r \'.monitors[] | select(.active) | .active_tags[0] // empty\'; elif command -v niri >/dev/null 2>&1; then niri msg -j workspaces 2>/dev/null | jq -r \'.[] | select(.is_active) | (.name // .idx) // empty\'; elif command -v hyprctl >/dev/null 2>&1; then hyprctl activeworkspace -j 2>/dev/null | jq -r \'.name // .id // empty\'; elif command -v swaymsg >/dev/null 2>&1; then swaymsg -t get_workspaces 2>/dev/null | jq -r \'.[] | select(.focused) | .name // empty\'; fi'

local TAG_NAMES = {
  [1] = "SOC",
  [2] = "TRM",
  [3] = "WEB",
  [4] = "DEV",
  [5] = "ENT",
  [6] = "THR",
  [7] = "STU",
  [8] = "AI",
  [9] = "PRD",
}

local workspace = "--"
local refreshing = false

local function formatWorkspace(raw: string): string
  local num = tonumber(raw)
  if num ~= nil and TAG_NAMES[num] ~= nil then
    return TAG_NAMES[num]
  end
  return raw
end

local function render()
  barWidget.setText(workspace)
  barWidget.setTooltip("Active Workspace: " .. workspace)
end

local function refresh()
  if refreshing then
    return
  end

  refreshing = true
  local started = noctalia.runAsync(command, function(result)
    refreshing = false
    local text = string.match(result.stdout or "", "%S+")
    if result.exitCode == 0 and text ~= nil and text ~= "null" and text ~= "" then
      workspace = formatWorkspace(text)
    else
      workspace = "--"
    end
    render()
  end)

  if not started then
    refreshing = false
    workspace = "--"
    render()
  end
end

function update()
  noctalia.setUpdateInterval(250)
  render()
  refresh()
end
