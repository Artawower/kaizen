local command = "sensors macsmc_hwmon-isa-0000 2>/dev/null | grep 'WiFi/BT Module Temp' | awk '{print int($4)}'"
local temperature = "--°C"
local refreshing = false

local function render()
  barWidget.setGlyph("temperature")
  barWidget.setText(temperature)
  barWidget.setTooltip("WiFi/BT module temperature: " .. temperature)
end

local function refresh()
  if refreshing then
    return
  end

  refreshing = true
  local started = noctalia.runAsync(command, function(result)
    refreshing = false
    local degrees = tonumber(result.stdout)
    if result.exitCode == 0 and degrees ~= nil then
      temperature = tostring(math.floor(degrees)) .. "°C"
    else
      temperature = "--°C"
    end
    render()
  end)

  if not started then
    refreshing = false
    temperature = "--°C"
    render()
  end
end

function update()
  noctalia.setUpdateInterval(5000)
  render()
  refresh()
end
