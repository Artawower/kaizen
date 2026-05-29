import os
import subprocess

from ..base import Agent, MultiplexerAdapter, Pane, Tab


class TmuxAdapter(MultiplexerAdapter):
    def is_available(self) -> bool:
        return "TMUX" in os.environ

    def current_workspace_id(self, cwd: str) -> str | None:
        result = subprocess.run(
            ["tmux", "display-message", "-p", "#{session_id}"],
            capture_output=True, text=True,
        )
        return result.stdout.strip() or None

    def list_tabs(self, workspace_id: str) -> list[Tab]:
        result = subprocess.run(
            ["tmux", "list-windows", "-t", workspace_id, "-F", "#{window_id}|#{window_name}"],
            capture_output=True, text=True,
        )
        tabs = []
        for line in result.stdout.strip().splitlines():
            win_id, name = line.split("|", 1)
            tabs.append(Tab(tab_id=win_id, workspace_id=workspace_id, label=name))
        return tabs

    def create_tab(self, workspace_id: str, label: str, cwd: str) -> tuple[Tab, Pane]:
        subprocess.run(["tmux", "new-window", "-t", workspace_id, "-n", label, "-c", cwd], check=True)
        result = subprocess.run(
            ["tmux", "display-message", "-p", "#{window_id}|#{pane_id}"],
            capture_output=True, text=True,
        )
        win_id, pane_id = result.stdout.strip().split("|", 1)
        return Tab(tab_id=win_id, workspace_id=workspace_id, label=label), Pane(pane_id=pane_id, tab_id=win_id, label="")

    def list_panes_in_tab(self, tab_id: str) -> list[Pane]:
        result = subprocess.run(
            ["tmux", "list-panes", "-t", tab_id, "-F", "#{pane_id}"],
            capture_output=True, text=True,
        )
        return [Pane(pane_id=p.strip(), tab_id=tab_id, label="") for p in result.stdout.strip().splitlines() if p.strip()]

    def rename_pane(self, pane_id: str, label: str) -> None:
        subprocess.run(["tmux", "select-pane", "-t", pane_id, "-T", label], check=True)

    def split_pane(self, pane_id: str, direction: str) -> Pane:
        flag = "-h" if direction == "right" else "-v"
        result = subprocess.run(
            ["tmux", "split-window", flag, "-t", pane_id, "-P", "-F", "#{pane_id}"],
            capture_output=True, text=True, check=True,
        )
        new_pane_id = result.stdout.strip()
        win = subprocess.run(
            ["tmux", "display-message", "-t", new_pane_id, "-p", "#{window_id}"],
            capture_output=True, text=True,
        )
        return Pane(pane_id=new_pane_id, tab_id=win.stdout.strip(), label="")

    def pane_alive(self, pane_id: str) -> bool:
        result = subprocess.run(
            ["tmux", "display-message", "-t", pane_id, "-p", "#{pane_id}"],
            capture_output=True, text=True,
        )
        return result.returncode == 0

    def get_pane_agent_status(self, pane_id: str) -> str:
        result = subprocess.run(
            ["tmux", "display-message", "-t", pane_id, "-p", "#{pane_dead}"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            return "unknown"
        return "done" if result.stdout.strip() == "1" else "idle"

    def run_in_pane(self, pane_id: str, command: str) -> None:
        subprocess.run(["tmux", "send-keys", "-t", pane_id, command, "Enter"], check=True)

    def wait_pane_idle(self, pane_id: str, timeout_ms: int) -> bool:
        raise NotImplementedError("tmux adapter: wait_pane_idle not implemented")
