#!/usr/bin/env python3
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class MacOSDefault:
    domain: str
    key: str
    value_type: str
    value: str

    def apply(self) -> None:
        subprocess.run(
            [
                "/usr/bin/defaults",
                "write",
                self.domain,
                self.key,
                f"-{self.value_type}",
                self.value,
            ],
            check=True,
        )


class MacOSSettings:
    def __init__(self) -> None:
        screenshots = Path.home() / "Pictures" / "screenshots"
        self._screenshots = screenshots
        self._defaults = (
            MacOSDefault("com.apple.dock", "autohide", "bool", "true"),
            MacOSDefault("com.apple.dock", "tilesize", "int", "32"),
            MacOSDefault("com.apple.dock", "largesize", "int", "48"),
            MacOSDefault("com.apple.dock", "magnification", "bool", "true"),
            MacOSDefault("com.apple.dock", "show-recents", "bool", "false"),
            MacOSDefault("com.apple.dock", "workspaces-auto-swoosh", "bool", "false"),
            MacOSDefault(
                "com.apple.screencapture", "location", "string", str(screenshots)
            ),
            MacOSDefault("com.apple.screensaver", "askForPasswordDelay", "int", "30"),
        )

    def apply(self) -> None:
        self._screenshots.mkdir(parents=True, exist_ok=True)
        for setting in self._defaults:
            setting.apply()
        subprocess.run(["/usr/bin/killall", "Dock"], check=False)


if len(sys.argv) > 1 and sys.argv[1] == "macos":
    MacOSSettings().apply()
