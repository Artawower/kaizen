import json
import os
import subprocess
from pathlib import Path

from ..base import Agent, MultiplexerAdapter, Pane, Tab


def _run(args: list[str]) -> dict:
    result = subprocess.run(["herdr"] + args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"herdr {' '.join(args)} failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def _run_silent(args: list[str]) -> None:
    result = subprocess.run(["herdr"] + args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"herdr {' '.join(args)} failed: {result.stderr.strip()}")


class HerdrAdapter(MultiplexerAdapter):
    def is_available(self) -> bool:
        if os.environ.get("HERDR_ENV") != "1":
            return False
        try:
            result = subprocess.run(
                ["herdr", "workspace", "list"],
                capture_output=True, text=True, timeout=3
            )
            return result.returncode == 0 and "nested herdr is disabled" not in result.stderr
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return False

    def current_workspace_id(self, cwd: str) -> str | None:
        pane_id = os.environ.get("HERDR_PANE_ID")
        if pane_id:
            data = _run(["pane", "get", pane_id])
            return data["result"]["pane"].get("workspace_id")
        data = _run(["workspace", "list"])
        target = str(Path(cwd).resolve())
        for ws in data["result"]["workspaces"]:
            if str(Path(ws.get("cwd", "")).resolve()) == target:
                return ws["workspace_id"]
        return None

    def list_tabs(self, workspace_id: str) -> list[Tab]:
        data = _run(["tab", "list"])
        return [
            Tab(tab_id=t["tab_id"], workspace_id=t["workspace_id"], label=t.get("label", ""))
            for t in data["result"]["tabs"]
            if t["workspace_id"] == workspace_id
        ]

    def create_tab(self, workspace_id: str, label: str, cwd: str) -> tuple[Tab, Pane]:
        data = _run([
            "tab", "create",
            "--workspace", workspace_id,
            "--label", label,
            "--cwd", cwd,
            "--no-focus",
        ])
        tab = Tab(tab_id=data["result"]["tab"]["tab_id"], workspace_id=workspace_id, label=label)
        root = Pane(pane_id=data["result"]["root_pane"]["pane_id"], tab_id=tab.tab_id, label="")
        return tab, root

    def list_panes_in_tab(self, tab_id: str) -> list[Pane]:
        data = _run(["pane", "list"])
        return [
            Pane(pane_id=p["pane_id"], tab_id=p["tab_id"], label="")
            for p in data["result"]["panes"]
            if p["tab_id"] == tab_id
        ]

    def rename_pane(self, pane_id: str, label: str) -> None:
        _run(["pane", "rename", pane_id, label])

    def split_pane(self, pane_id: str, direction: str) -> Pane:
        data = _run(["pane", "split", pane_id, "--direction", direction, "--no-focus"])
        return Pane(
            pane_id=data["result"]["pane"]["pane_id"],
            tab_id=data["result"]["pane"]["tab_id"],
            label="",
        )

    def pane_alive(self, pane_id: str) -> bool:
        result = subprocess.run(
            ["herdr", "pane", "get", pane_id],
            capture_output=True, text=True, timeout=3,
        )
        return result.returncode == 0

    def get_pane_agent_status(self, pane_id: str) -> str:
        try:
            data = _run(["pane", "get", pane_id])
            return data["result"]["pane"].get("agent_status", "unknown")
        except RuntimeError:
            return "unknown"

    def run_in_pane(self, pane_id: str, command: str) -> None:
        _run_silent(["pane", "run", pane_id, command])

    def wait_pane_idle(self, pane_id: str, timeout_ms: int) -> bool:
        import time
        deadline = time.monotonic() + timeout_ms / 1000
        poll_interval = 2.0
        while time.monotonic() < deadline:
            if self.get_pane_agent_status(pane_id) == "idle":
                return True
            time.sleep(poll_interval)
        return False
