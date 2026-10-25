$env.EDITOR = "emacsclient -nw"
$env.VISUAL = "emacsclient -c"
$env.JJ_EDITOR = "emacsclient -nw"
$env.LSP_USE_PLISTS = "true"
$env.DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env.DOTNET_ROLL_FORWARD = "Major"
$env.config.table.mode = "none"

if (sys host | get name) == "Darwin" {
    $env.DOTNET_ROOT = "/usr/local/share/dotnet"
    $env.TMPDIR = "/tmp"
    let sdk = ($env.HOME | path join "Library/Android/sdk")
    $env.ANDROID_SDK_ROOT = $sdk
    $env.ANDROID_HOME = $sdk
}

if (sys host | get name) == "Linux" {
    $env.FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0"
    if "LD_LIBRARY_PATH" in $env {
        hide-env LD_LIBRARY_PATH
    }
    $env.__EGL_VENDOR_LIBRARY_FILENAMES = "/usr/share/glvnd/egl_vendor.d/50_mesa.json"
    $env.__GLX_VENDOR_LIBRARY_NAME = "mesa"
    $env.LIBGL_DRIVERS_PATH = "/usr/lib64/dri"
    $env.GBM_BACKENDS_PATH = "/usr/lib64/gbm"
    $env.VDPAU_DRIVER_PATH = "/usr/lib64/vdpau"
    $env.VK_ICD_FILENAMES = "/usr/share/vulkan/icd.d/asahi_icd.aarch64.json"
    $env.VK_LAYER_PATH = "/usr/share/vulkan/explicit_layer.d:/usr/share/vulkan/implicit_layer.d"
    $env.XDG_DATA_DIRS = (($env.XDG_DATA_DIRS? | default "") | split row (char esep) | where {|path| $path != "" and not ($path starts-with "/nix/store") and not ($path starts-with "/opt/homebrew/") and not ($path | str contains "/Library/")})
        | append ["/usr/local/share" "/usr/share" ($env.HOME | path join ".local/share/flatpak/exports/share") "/var/lib/flatpak/exports/share"]
        | uniq
    if "QT_PLUGIN_PATH" in $env {
        hide-env QT_PLUGIN_PATH
    }
}

let extra_paths = [
    "/usr/local/bin"
    ($env.HOME | path join ".local/bin")
    ($env.HOME | path join "bin")
    ($env.HOME | path join ".config/bin")
    ($env.HOME | path join ".config/scripts")
    ($env.HOME | path join ".local/share/mise/shims")
    ($env.HOME | path join ".local/share/uv/tools")
    ($env.HOME | path join ".cargo/bin")
    ($env.HOME | path join "go/bin")
    ($env.HOME | path join ".go/bin")
    ($env.HOME | path join ".steel/bin")
    ($env.HOME | path join ".local/share/steel/bin")
]
let platform_paths = if (sys host | get name) == "Darwin" {
    let sdk = ($env.HOME | path join "Library/Android/sdk")
    ["/opt/homebrew/sbin" "/opt/homebrew/bin" "/opt/homebrew/opt/libpq/bin"
        ($env.HOME | path join ".orbstack/bin")
        ($sdk | path join "cmdline-tools/latest/bin") ($sdk | path join "platform-tools")]
} else { ["/usr/sbin" "/usr/bin" "/usr/local/bin"] }
$env.PATH = ($platform_paths | append $extra_paths | append $env.PATH | uniq)

mkdir $nu.cache-dir
^carapace _carapace nushell | save --force $"($nu.cache-dir)/carapace.nu"

