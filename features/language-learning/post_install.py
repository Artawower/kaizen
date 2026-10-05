#!/usr/bin/env python3
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

ANKI_CONNECT_ADDON_ID = 2055492159
LINUX_TTS_ADDON_ID = 704375187
ANKI_DOWNLOAD_URL = "https://ankiweb.net/shared/download/{addon_id}?v=2.1&p=260903"
USER_AGENT = "Anki/26.09.3"


def get_addons_directories(os_name: str) -> list[Path]:
    home = Path.home()
    directories: list[Path] = []
    if os_name == "macos":
        directories.append(
            home / "Library" / "Application Support" / "Anki2" / "addons21"
        )
    elif os_name == "linux":
        flatpak_dir = (
            home
            / ".var"
            / "app"
            / "net.ankiweb.Anki"
            / "data"
            / "Anki2"
            / "addons21"
        )
        native_dir = home / ".local" / "share" / "Anki2" / "addons21"
        if flatpak_dir.parent.exists():
            directories.append(flatpak_dir)
        if native_dir.parent.exists():
            directories.append(native_dir)
        if not directories:
            directories.append(flatpak_dir)
    return directories


def install_addon(addon_id: int, addons_dir: Path) -> None:
    target_dir = addons_dir / str(addon_id)
    if target_dir.is_dir() and any(target_dir.iterdir()):
        return

    url = ANKI_DOWNLOAD_URL.format(addon_id=addon_id)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request) as response:
            archive_data = response.read()
    except Exception as exc:
        print(f"failed to download anki add-on {addon_id}: {exc}", file=sys.stderr)
        return

    target_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(archive_data)) as archive:
        archive.extractall(target_dir)


def main() -> int:
    os_name = sys.argv[1] if len(sys.argv) > 1 else "linux"
    addons_to_install = [ANKI_CONNECT_ADDON_ID]
    if os_name == "linux":
        addons_to_install.append(LINUX_TTS_ADDON_ID)

    for directory in get_addons_directories(os_name):
        directory.mkdir(parents=True, exist_ok=True)
        for addon_id in addons_to_install:
            install_addon(addon_id, directory)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
