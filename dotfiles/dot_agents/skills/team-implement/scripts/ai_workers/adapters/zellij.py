import os
import subprocess

from ..base import Agent, MultiplexerAdapter, Pane, Tab


class ZellijAdapter(MultiplexerAdapter):
    def is_available(self) -> bool:
        return "ZELLIJ" in os.environ

    def current_workspace_id(self, cwd: str) -> str | None:
        return os.environ.get("ZELLIJ_SESSION_NAME")

    def list_tabs(self, workspace_id: str) -> list[Tab]:
        result = subprocess.run(["zellij", "action", "query-tab-names"], capture_output=True, text=True)
        return [
            Tab(tab_id=str(i), workspace_id=workspace_id, label=name.strip())
            for i, name in enumerate(result.stdout.strip().splitlines())
        ]

    def create_tab(self, workspace_id: str, label: str, cwd: str) -> tuple[Tab, Pane]:
        subprocess.run(["zellij", "action", "new-tab", "--name", label, "--cwd", cwd], check=True)
        tabs = self.list_tabs(workspace_id)
        tab = next((t for t in tabs if t.label == label), tabs[-1])
        return tab, Pane(pane_id=f"{tab.tab_id}:0", tab_id=tab.tab_id, label="")

    def list_panes_in_tab(self, tab_id: str) -> list[Pane]:
        raise NotImplementedError("zellij adapter: list_panes_in_tab not implemented")

    def rename_pane(self, pane_id: str, label: str) -> None:
        subprocess.run(["zellij", "action", "rename-pane", label], check=True)

    def split_pane(self, pane_id: str, direction: str) -> Pane:
        subprocess.run(["zellij", "action", "new-pane", "--direction", direction], check=True)
        tab_id = pane_id.split(":")[0]
        return Pane(pane_id=f"{tab_id}:new", tab_id=tab_id, label="")

    def pane_alive(self, pane_id: str) -> bool:
        raise NotImplementedError("zellij adapter: pane_alive not implemented")

    def get_pane_agent_status(self, pane_id: str) -> str:
        raise NotImplementedError("zellij adapter: get_pane_agent_status not implemented")

    def run_in_pane(self, pane_id: str, command: str) -> None:
        subprocess.run(["zellij", "action", "write-chars", "--pane-id", pane_id, command + "\n"], check=True)

    def wait_pane_idle(self, pane_id: str, timeout_ms: int) -> bool:
        raise NotImplementedError("zellij adapter: wait_pane_idle not implemented")
