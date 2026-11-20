#!/usr/bin/env python3
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ElementTree
from pathlib import Path

APPCAST = "https://blob.superlogical.com/public/rex-app/preview/appcast.xml"
APPLICATION = Path("/Applications/Rex.app")
CLI = APPLICATION / "Contents" / "Helpers" / "Rex Server.rex" / "Contents" / "MacOS" / "rex"


def latest_dmg() -> str:
    with urllib.request.urlopen(APPCAST, timeout=30) as response:
        channel = ElementTree.parse(response).getroot().find("channel")
    enclosure = channel.find("item/enclosure") if channel is not None else None
    url = enclosure.get("url", "") if enclosure is not None else ""
    if not url.endswith(".dmg"):
        raise RuntimeError(f"no Rex disk image in {APPCAST}")
    return url


def install_application() -> None:
    url = latest_dmg()
    with tempfile.TemporaryDirectory() as directory:
        image = Path(directory) / "Rex.dmg"
        mount = Path(directory) / "mount"
        print(f"[rex] downloading {url}")
        urllib.request.urlretrieve(url, image)
        subprocess.run(
            ["/usr/bin/hdiutil", "attach", "-nobrowse", "-readonly", "-mountpoint", str(mount), str(image)],
            check=True, stdout=subprocess.DEVNULL,
        )
        try:
            bundle = mount / APPLICATION.name
            subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
            subprocess.run(["/usr/sbin/spctl", "--assess", "--type", "execute", str(bundle)], check=True)
            shutil.copytree(bundle, APPLICATION, symlinks=True)
        finally:
            subprocess.run(["/usr/bin/hdiutil", "detach", str(mount)], check=False, stdout=subprocess.DEVNULL)


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] != "macos":
        return
    if not APPLICATION.exists():
        install_application()
    subprocess.run([str(CLI), "skill", "setup"], check=True)


if __name__ == "__main__":
    main()
