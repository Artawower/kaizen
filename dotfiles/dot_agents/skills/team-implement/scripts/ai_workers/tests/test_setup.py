import json
from unittest.mock import MagicMock, patch

import pytest

from ai_workers.__main__ import setup, LIVE_STATUSES
from ai_workers.base import Pane, Tab

WORKSPACE_ID = "ws-study"
TAB_ID = f"{WORKSPACE_ID}:2"
ROOT_PANE = f"{WORKSPACE_ID}-1"
CODER_PANE = f"{WORKSPACE_ID}-2"
RESEARCHER_PANE = f"{WORKSPACE_ID}-3"
SHELL_PANE = f"{WORKSPACE_ID}-4"
CWD = "/Users/darkawower/projects/study/nix"
SCOPE = "study"


def make_adapter(
    workspace_id=WORKSPACE_ID,
    tabs=None,
    pane_statuses=None,
    stored_panes_alive=True,
    tab_panes=None,
):
    statuses = pane_statuses or {}
    adapter = MagicMock()
    adapter.current_workspace_id.return_value = workspace_id
    adapter.list_tabs.return_value = tabs or []
    adapter.get_pane_agent_status.side_effect = lambda pid: statuses.get(pid, "done")
    adapter.pane_alive.return_value = stored_panes_alive
    adapter.list_panes_in_tab.return_value = tab_panes or [
        Pane(pane_id=ROOT_PANE, tab_id=TAB_ID, label="")
    ]
    adapter.create_tab.return_value = (
        Tab(tab_id=TAB_ID, workspace_id=WORKSPACE_ID, label="ai-workers"),
        Pane(pane_id=ROOT_PANE, tab_id=TAB_ID, label=""),
    )
    adapter.split_pane.side_effect = [
        Pane(pane_id=CODER_PANE, tab_id=TAB_ID, label=""),
        Pane(pane_id=RESEARCHER_PANE, tab_id=TAB_ID, label=""),
        Pane(pane_id=SHELL_PANE, tab_id=TAB_ID, label=""),
    ]
    adapter.wait_pane_idle.return_value = True
    return adapter


@pytest.fixture(autouse=True)
def tmp_state(tmp_path, monkeypatch):
    path = tmp_path / "layout.json"
    monkeypatch.setattr("ai_workers.__main__.STATE_FILE", path)
    return path


class TestAllAgentsRunning:
    def test_skips_when_all_panes_live(self, tmp_state):
        stored = {WORKSPACE_ID: {"critic": ROOT_PANE, "coder": CODER_PANE, "researcher": RESEARCHER_PANE}}
        tmp_state.write_text(json.dumps(stored))
        adapter = make_adapter(
            stored_panes_alive=True,
            pane_statuses={ROOT_PANE: "idle", CODER_PANE: "idle", RESEARCHER_PANE: "idle"},
        )
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        adapter.run_in_pane.assert_not_called()
        adapter.create_tab.assert_not_called()


class TestTiledLayout:
    def test_creates_tab_in_correct_workspace(self):
        adapter = make_adapter()
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        adapter.create_tab.assert_called_once_with(WORKSPACE_ID, "ai-workers", CWD)

    def test_splits_into_four_panes(self):
        adapter = make_adapter()
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        assert adapter.split_pane.call_count == 3

    def test_2x2_split_sequence(self):
        adapter = make_adapter()
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        calls = [(c.args[0], c.args[1]) for c in adapter.split_pane.call_args_list]
        assert calls[0] == (ROOT_PANE, "right")    # anchor → coder
        assert calls[1] == (ROOT_PANE, "down")     # anchor → researcher
        assert calls[2] == (CODER_PANE, "down")    # coder → 4th shell pane

    def test_renames_three_agent_panes(self):
        adapter = make_adapter()
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        labels = {c.args[1] for c in adapter.rename_pane.call_args_list}
        assert labels == {"critic", "coder", "researcher"}

    def test_persists_pane_ids(self, tmp_state):
        adapter = make_adapter()
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        state = json.loads(tmp_state.read_text())
        assert set(state[WORKSPACE_ID].keys()) == {"critic", "coder", "researcher"}


class TestReusesExistingTab:
    def test_does_not_create_tab_when_exists(self):
        tab = Tab(tab_id=TAB_ID, workspace_id=WORKSPACE_ID, label="ai-workers")
        adapter = make_adapter(tabs=[tab])
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        adapter.create_tab.assert_not_called()


class TestStartsOnlyDeadPanes:
    def test_skips_live_panes(self, tmp_state):
        stored = {WORKSPACE_ID: {"critic": ROOT_PANE, "coder": CODER_PANE, "researcher": RESEARCHER_PANE}}
        tmp_state.write_text(json.dumps(stored))
        adapter = make_adapter(
            stored_panes_alive=True,
            pane_statuses={CODER_PANE: "idle"},
        )
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        started = {c.args[0] for c in adapter.run_in_pane.call_args_list}
        assert CODER_PANE not in started
        assert ROOT_PANE in started
        assert RESEARCHER_PANE in started

    def test_waits_in_parallel(self, tmp_state):
        stored = {WORKSPACE_ID: {"critic": ROOT_PANE, "coder": CODER_PANE, "researcher": RESEARCHER_PANE}}
        tmp_state.write_text(json.dumps(stored))
        adapter = make_adapter(stored_panes_alive=True)
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        waited = {c.args[0] for c in adapter.wait_pane_idle.call_args_list}
        assert waited == {ROOT_PANE, CODER_PANE, RESEARCHER_PANE}

    def test_uses_model_in_command(self, tmp_state, monkeypatch):
        stored = {WORKSPACE_ID: {"critic": ROOT_PANE, "coder": CODER_PANE, "researcher": RESEARCHER_PANE}}
        tmp_state.write_text(json.dumps(stored))
        monkeypatch.setattr(
            "ai_workers.__main__.load_models",
            lambda: {"coder": "openai/gpt-5", "research": "openai/gpt-4", "reviewer": "claude-3"},
        )
        adapter = make_adapter(stored_panes_alive=True)
        with patch("ai_workers.__main__.detect", return_value=adapter):
            setup(SCOPE, CWD)
        cmds = {c.args[0]: c.args[1] for c in adapter.run_in_pane.call_args_list}
        assert "--model openai/gpt-5" in cmds[CODER_PANE]
        assert "--model openai/gpt-4" in cmds[RESEARCHER_PANE]
        assert "--model claude-3" in cmds[ROOT_PANE]


class TestErrors:
    def test_raises_when_no_workspace(self):
        adapter = make_adapter(workspace_id=None)
        with patch("ai_workers.__main__.detect", return_value=adapter):
            with pytest.raises(RuntimeError, match="No workspace found"):
                setup(SCOPE, CWD)

    def test_raises_on_timeout(self, tmp_state):
        stored = {WORKSPACE_ID: {"critic": ROOT_PANE, "coder": CODER_PANE, "researcher": RESEARCHER_PANE}}
        tmp_state.write_text(json.dumps(stored))
        adapter = make_adapter(stored_panes_alive=True)
        adapter.wait_pane_idle.return_value = False
        with patch("ai_workers.__main__.detect", return_value=adapter):
            with pytest.raises(RuntimeError, match="Timeout waiting for"):
                setup(SCOPE, CWD)
