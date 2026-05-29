import json
from unittest.mock import MagicMock, patch

import pytest

from ai_workers.adapters.herdr import HerdrAdapter
from ai_workers.base import Pane, Tab

WORKSPACE_ID = "w6525a650a8c6b1"
TAB_ID = f"{WORKSPACE_ID}:3"
PANE_ID = f"{WORKSPACE_ID}-7"


def resp(**kwargs) -> str:
    return json.dumps({"id": "cli:test", "result": kwargs})


@pytest.fixture
def adapter():
    return HerdrAdapter()


class TestIsAvailable:
    def test_true_when_herdr_env_set(self, adapter, monkeypatch):
        monkeypatch.setenv("HERDR_ENV", "1")
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stderr="")
            assert adapter.is_available() is True

    def test_false_without_herdr_env(self, adapter, monkeypatch):
        monkeypatch.delenv("HERDR_ENV", raising=False)
        assert adapter.is_available() is False

    def test_false_when_nested_disabled(self, adapter, monkeypatch):
        monkeypatch.setenv("HERDR_ENV", "1")
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stderr="nested herdr is disabled")
            assert adapter.is_available() is False


class TestCurrentWorkspaceId:
    def test_uses_herdr_pane_id_env(self, adapter, monkeypatch):
        monkeypatch.setenv("HERDR_PANE_ID", "p_11")
        payload = resp(pane={"pane_id": "p_11", "workspace_id": WORKSPACE_ID})
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            assert adapter.current_workspace_id("/any") == WORKSPACE_ID
        assert m.call_args[0][0] == ["herdr", "pane", "get", "p_11"]

    def test_falls_back_to_cwd(self, adapter, monkeypatch):
        monkeypatch.delenv("HERDR_PANE_ID", raising=False)
        payload = resp(workspaces=[
            {"workspace_id": "other", "cwd": "/other"},
            {"workspace_id": WORKSPACE_ID, "cwd": "/my/project"},
        ])
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            assert adapter.current_workspace_id("/my/project") == WORKSPACE_ID


class TestListTabs:
    def test_filters_by_workspace(self, adapter):
        payload = resp(tabs=[
            {"tab_id": f"{WORKSPACE_ID}:1", "workspace_id": WORKSPACE_ID, "label": "run"},
            {"tab_id": "wOTHER:1", "workspace_id": "wOTHER", "label": "x"},
        ])
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            tabs = adapter.list_tabs(WORKSPACE_ID)
        assert len(tabs) == 1
        assert tabs[0].workspace_id == WORKSPACE_ID


class TestListPanesInTab:
    def test_filters_by_tab(self, adapter):
        payload = resp(panes=[
            {"pane_id": f"{WORKSPACE_ID}-1", "tab_id": TAB_ID, "agent_status": "idle"},
            {"pane_id": f"{WORKSPACE_ID}-2", "tab_id": TAB_ID, "agent_status": "idle"},
            {"pane_id": f"{WORKSPACE_ID}-9", "tab_id": "other:1", "agent_status": "idle"},
        ])
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            panes = adapter.list_panes_in_tab(TAB_ID)
        assert len(panes) == 2
        assert all(p.tab_id == TAB_ID for p in panes)


class TestSplitPane:
    def test_returns_new_pane(self, adapter):
        payload = resp(pane={"pane_id": f"{WORKSPACE_ID}-8", "tab_id": TAB_ID})
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            pane = adapter.split_pane(PANE_ID, "right")
        assert pane.pane_id == f"{WORKSPACE_ID}-8"

    def test_passes_direction(self, adapter):
        payload = resp(pane={"pane_id": f"{WORKSPACE_ID}-8", "tab_id": TAB_ID})
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            adapter.split_pane(PANE_ID, "down")
        args = m.call_args[0][0]
        assert "--direction" in args and "down" in args


class TestGetPaneAgentStatus:
    def test_returns_status(self, adapter):
        payload = resp(pane={"pane_id": PANE_ID, "agent_status": "idle"})
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            assert adapter.get_pane_agent_status(PANE_ID) == "idle"

    def test_returns_unknown_on_error(self, adapter):
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=1, stdout="", stderr="not found")
            assert adapter.get_pane_agent_status(PANE_ID) == "unknown"


class TestRunInPane:
    def test_calls_herdr_pane_run(self, adapter):
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout="", stderr="")
            adapter.run_in_pane(PANE_ID, "pi-link study@coder --model gpt-5")
        assert m.call_args[0][0] == ["herdr", "pane", "run", PANE_ID, "pi-link study@coder --model gpt-5"]


class TestWaitPaneIdle:
    def test_true_when_pane_becomes_idle(self, adapter):
        idle_payload = resp(pane={"pane_id": PANE_ID, "agent_status": "idle"})
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=idle_payload, stderr="")
            assert adapter.wait_pane_idle(PANE_ID, 30_000) is True

    def test_false_on_timeout(self, adapter):
        working_payload = resp(pane={"pane_id": PANE_ID, "agent_status": "working"})
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=working_payload, stderr="")
            with patch("time.sleep"):
                assert adapter.wait_pane_idle(PANE_ID, 100) is False

    def test_polls_pane_status(self, adapter):
        payloads = [
            resp(pane={"pane_id": PANE_ID, "agent_status": "working"}),
            resp(pane={"pane_id": PANE_ID, "agent_status": "idle"}),
        ]
        call_count = [0]
        def fake_run(args, **kw):
            result = MagicMock(returncode=0, stdout=payloads[min(call_count[0], 1)], stderr="")
            call_count[0] += 1
            return result
        with patch("subprocess.run", side_effect=fake_run):
            with patch("time.sleep"):
                assert adapter.wait_pane_idle(PANE_ID, 10_000) is True
        assert call_count[0] >= 2


class TestCreateTab:
    def test_parses_tab_and_root_pane(self, adapter):
        payload = resp(
            tab={"tab_id": TAB_ID, "workspace_id": WORKSPACE_ID},
            root_pane={"pane_id": PANE_ID, "tab_id": TAB_ID},
        )
        with patch("subprocess.run") as m:
            m.return_value = MagicMock(returncode=0, stdout=payload, stderr="")
            tab, pane = adapter.create_tab(WORKSPACE_ID, "ai-workers", "/p")
        assert tab.tab_id == TAB_ID
        assert pane.pane_id == PANE_ID
