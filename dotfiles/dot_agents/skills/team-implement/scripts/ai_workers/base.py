from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class Tab:
    tab_id: str
    workspace_id: str
    label: str


@dataclass
class Pane:
    pane_id: str
    tab_id: str
    label: str


@dataclass
class Agent:
    name: str
    status: str
    cwd: str
    pane_id: str
    tab_id: str


class MultiplexerAdapter(ABC):
    @abstractmethod
    def is_available(self) -> bool:
        """Return True if this multiplexer is active in the current environment."""

    @abstractmethod
    def current_workspace_id(self, cwd: str) -> str | None:
        """Return workspace ID whose cwd matches the given path, or None."""

    @abstractmethod
    def list_tabs(self, workspace_id: str) -> list[Tab]:
        """Return all tabs in the given workspace."""

    @abstractmethod
    def create_tab(self, workspace_id: str, label: str, cwd: str) -> tuple[Tab, Pane]:
        """Create a tab in workspace and return (tab, root_pane)."""

    @abstractmethod
    def list_panes_in_tab(self, tab_id: str) -> list[Pane]:
        """Return all panes belonging to the given tab."""

    @abstractmethod
    def rename_pane(self, pane_id: str, label: str) -> None:
        """Set a human-readable label on a pane."""

    @abstractmethod
    def split_pane(self, pane_id: str, direction: str) -> Pane:
        """Split pane in given direction ('right' or 'down'), return new pane."""

    @abstractmethod
    def pane_alive(self, pane_id: str) -> bool:
        """Return True if the pane still exists."""

    @abstractmethod
    def get_pane_agent_status(self, pane_id: str) -> str:
        """Return agent_status of the pane: idle/working/blocked/done/unknown."""

    @abstractmethod
    def run_in_pane(self, pane_id: str, command: str) -> None:
        """Run a shell command in a pane that has an active shell (not pi)."""

    @abstractmethod
    def wait_pane_idle(self, pane_id: str, timeout_ms: int) -> bool:
        """Block until the pane's agent reaches idle status. Return False on timeout."""
