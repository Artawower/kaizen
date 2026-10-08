#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path

MODPROBE_PATH = Path("/etc/modprobe.d/hid_apple.conf")
PARAM_PATH = Path("/sys/module/hid_apple/parameters/fnmode")
EXPECTED_LINE = "options hid_apple fnmode=2\n"


def configure_hid_apple() -> None:
    needs_modprobe = not MODPROBE_PATH.exists() or MODPROBE_PATH.read_text() != EXPECTED_LINE
    if needs_modprobe:
        subprocess.run(
            ["sudo", "tee", str(MODPROBE_PATH)],
            input=EXPECTED_LINE.encode(),
            stdout=subprocess.DEVNULL,
            check=True,
        )

    if (
        Path("/sys/module/hid_apple").exists()
        and PARAM_PATH.exists()
        and PARAM_PATH.read_text().strip() != "2"
    ):
        subprocess.run(
            ["sudo", "tee", str(PARAM_PATH)],
            input=b"2\n",
            stdout=subprocess.DEVNULL,
            check=True,
        )


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "linux":
        configure_hid_apple()


if __name__ == "__main__":
    main()
