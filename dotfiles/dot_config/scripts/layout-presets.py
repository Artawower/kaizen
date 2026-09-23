#!/usr/bin/env python3
from __future__ import annotations

import argparse
from abc import ABC, abstractmethod
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
import re
import shlex
import subprocess
import sys
import time
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

def _env_float(name: str, default: str) -> float:
    try:
        return float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return float(default)


SHELL_READY_TIMEOUT = _env_float("LAYOUT_SHELL_READY_TIMEOUT", "20")
POLL_INTERVAL = _env_float("LAYOUT_POLL_INTERVAL", "1.0")


class CommandError(RuntimeError):
    pass


def run_process(argv: list[str], *, input_text: str | None = None) -> str:
    result = subprocess.run(argv, input=input_text, capture_output=True, text=True)
    if result.returncode != 0:
        raise CommandError(
            f"Command failed ({result.returncode}): {' '.join(argv)}\n"
            f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return result.stdout.strip()


def parse_key_values(output: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for token in output.split():
        if ":" in token:
            key, value = token.split(":", 1)
            if key and value:
                fields[key] = f"{key}:{value}"
        elif "=" in token:
            key, value = token.split("=", 1)
            if key and value:
                fields[key] = value
    return fields


@dataclass(frozen=True)
class TerminalInfo:
    ref: str
    title: str | None
    kind: str
    handle: Any


class Backend(ABC):
    name: str

    @abstractmethod
    def current_workspace(self) -> str: ...

    @abstractmethod
    def root_group(self, workspace: str) -> Any: ...

    @abstractmethod
    def split_group(self, workspace: str, parent: Any, direction: str) -> Any: ...

    @abstractmethod
    def create_terminal(self, workspace: str, group: Any, title: str, cwd: str) -> Any: ...

    def reuse_terminal(self, group: Any, title: str) -> Any | None:
        return None

    @abstractmethod
    def send_command(self, terminal: Any, command: str) -> None: ...

    @abstractmethod
    def wait_ready(self, terminal: Any) -> None: ...

    @abstractmethod
    def list_terminals(self, workspace: str) -> list[TerminalInfo]: ...

    @abstractmethod
    def close_launcher(self, workspace: str) -> bool: ...

    @abstractmethod
    def describe_group(self, group_id: str, group: Any) -> dict[str, Any]: ...

    @abstractmethod
    def describe_terminal(self, terminal: Any) -> dict[str, Any]: ...


# ---------- cmux backend ----------


@dataclass(frozen=True)
class SurfaceTarget:
    workspace: str
    ref: str
    uuid: str
    pane_ref: str | None
    pane_uuid: str | None


@dataclass(frozen=True)
class PaneTarget:
    workspace: str
    ref: str
    uuid: str
    selected_surface_ref: str | None
    selected_surface_uuid: str | None


def run_cmux(
    args: list[str], *, json_output: bool = False, id_format: str | None = None
) -> Any:
    command = ["cmux"]
    if json_output:
        command.append("--json")
    if id_format:
        command.extend(["--id-format", id_format])
    command.extend(args)
    output = run_process(command)
    if not json_output:
        return output
    if not output:
        return {}
    try:
        return json.loads(output)
    except json.JSONDecodeError as exc:
        raise CommandError(f"cmux returned invalid JSON: {exc}\n{output}") from exc


def cmux_parse_workspace_ref(text: str) -> str:
    match = re.search(r"workspace:\d+|[0-9A-Fa-f-]{36}", text)
    if not match:
        raise CommandError(f"Could not parse workspace from: {text!r}")
    return match.group(0)


def cmux_normalize_panel(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "ref": entry.get("ref") or entry.get("surface") or entry.get("panel"),
        "id": entry.get("id") or entry.get("surface_id") or entry.get("panel_id"),
        "title": entry.get("title"),
        "focused": bool(entry.get("focused", False)),
        "type": entry.get("type"),
        "pane_ref": entry.get("pane_ref"),
        "pane_id": entry.get("pane_id"),
    }


def cmux_normalize_pane(entry: dict[str, Any]) -> dict[str, Any]:
    return {
        "ref": entry.get("ref") or entry.get("pane"),
        "id": entry.get("id") or entry.get("pane_id"),
        "focused": bool(entry.get("focused", False)),
        "selected_surface_ref": entry.get("selected_surface_ref"),
        "selected_surface_id": entry.get("selected_surface_id"),
    }


def cmux_list_panels(workspace: str) -> list[dict[str, Any]]:
    data = run_cmux(
        ["list-panels", "--workspace", workspace], json_output=True, id_format="both"
    )
    items = data.get("surfaces") or data.get("panels") or []
    return [cmux_normalize_panel(item) for item in items]


def cmux_list_panes(workspace: str) -> list[dict[str, Any]]:
    data = run_cmux(
        ["list-panes", "--workspace", workspace], json_output=True, id_format="both"
    )
    items = data.get("panes") or []
    return [cmux_normalize_pane(item) for item in items]


def cmux_get_surface_health(workspace: str) -> list[dict[str, Any]]:
    data = run_cmux(["surface-health", "--workspace", workspace], json_output=True)
    return data.get("surfaces") or data.get("panels") or []


class CmuxBackend(Backend):
    name = "cmux"

    @staticmethod
    def detect() -> bool:
        return bool(os.environ.get("CMUX_WORKSPACE_ID"))

    def current_workspace(self) -> str:
        env_workspace = os.environ.get("CMUX_WORKSPACE_ID")
        if env_workspace:
            return env_workspace
        return cmux_parse_workspace_ref(run_cmux(["current-workspace"]))

    def root_group(self, workspace: str) -> PaneTarget:
        panes = cmux_list_panes(workspace)
        if not panes:
            raise CommandError(f"No panes found in workspace {workspace}")
        pane = next((item for item in panes if item.get("focused")), panes[0])
        return self._pane_target(workspace, pane)

    def _pane_target(self, workspace: str, pane: dict[str, Any]) -> PaneTarget:
        pane_uuid = pane.get("id")
        pane_ref = pane.get("ref")
        if not pane_uuid or not pane_ref:
            raise CommandError(f"Pane identifiers are incomplete: {pane!r}")
        return PaneTarget(
            workspace=workspace,
            ref=pane_ref,
            uuid=pane_uuid,
            selected_surface_ref=pane.get("selected_surface_ref"),
            selected_surface_uuid=pane.get("selected_surface_id"),
        )

    def split_group(self, workspace: str, parent: PaneTarget, direction: str) -> PaneTarget:
        before = cmux_list_panes(workspace)
        before_ids = {item["id"] for item in before if item.get("id")}
        before_refs = {item["ref"] for item in before if item.get("ref")}

        surface_id = parent.selected_surface_uuid or parent.selected_surface_ref
        split_args = ["new-split", direction, "--workspace", workspace]
        if surface_id:
            split_args.extend(["--surface", surface_id])
        output = run_cmux(split_args)
        fields = parse_key_values(output)
        created_ref = fields.get("pane")

        after = cmux_list_panes(workspace)
        created_pane: dict[str, Any] | None = None
        if created_ref:
            created_pane = next(
                (item for item in after if item.get("ref") == created_ref), None
            )
            if created_pane is None:
                raise CommandError(
                    "cmux reported a created pane ref but it was not visible in list-panes. "
                    f"new-split output={output!r}"
                )
        if created_pane is None:
            new_panes = [
                item
                for item in after
                if item.get("id") not in before_ids and item.get("ref") not in before_refs
            ]
            if len(new_panes) != 1:
                raise CommandError(
                    "Could not uniquely identify the newly created pane. "
                    f"new-split output={output!r}"
                )
            created_pane = new_panes[0]
        return self._pane_target(workspace, created_pane)

    def create_terminal(self, workspace: str, group: PaneTarget, title: str, cwd: str) -> SurfaceTarget:
        before = cmux_list_panels(workspace)
        before_ids = {item["id"] for item in before if item.get("id")}
        before_refs = {item["ref"] for item in before if item.get("ref")}

        created_output = run_cmux(
            [
                "new-surface",
                "--workspace",
                workspace,
                "--pane",
                group.uuid,
                "--type",
                "terminal",
            ]
        )
        fields = parse_key_values(created_output)
        created_ref = fields.get("surface")

        after = cmux_list_panels(workspace)
        created_panel: dict[str, Any] | None = None
        if created_ref:
            created_panel = next(
                (item for item in after if item.get("ref") == created_ref), None
            )
            if created_panel is None:
                raise CommandError(
                    "cmux reported a created surface ref but it was not visible in list-panels. "
                    f"new-surface output={created_output!r}"
                )
        if created_panel is None:
            new_panels = [
                item
                for item in after
                if item.get("id") not in before_ids and item.get("ref") not in before_refs
            ]
            if len(new_panels) != 1:
                raise CommandError(
                    "Could not uniquely identify the newly created surface. "
                    f"new-surface output={created_output!r}"
                )
            created_panel = new_panels[0]

        surface = self._surface_target(workspace, created_panel)
        self._rename_surface(surface, title)
        return surface

    def _surface_target(self, workspace: str, panel: dict[str, Any]) -> SurfaceTarget:
        surface_uuid = panel.get("id")
        surface_ref = panel.get("ref")
        if not surface_uuid or not surface_ref:
            raise CommandError(f"Surface IDs are incomplete: {panel!r}")
        return SurfaceTarget(
            workspace=workspace,
            ref=surface_ref,
            uuid=surface_uuid,
            pane_ref=panel.get("pane_ref"),
            pane_uuid=panel.get("pane_id"),
        )

    def reuse_terminal(self, group: PaneTarget, title: str) -> SurfaceTarget | None:
        if not group.selected_surface_ref or not group.selected_surface_uuid:
            return None
        surface = SurfaceTarget(
            workspace=group.workspace,
            ref=group.selected_surface_ref,
            uuid=group.selected_surface_uuid,
            pane_ref=group.ref,
            pane_uuid=group.uuid,
        )
        self._rename_surface(surface, title)
        return surface

    def _rename_surface(self, surface: SurfaceTarget, title: str) -> None:
        run_cmux(
            [
                "rename-tab",
                "--workspace",
                surface.workspace,
                "--surface",
                surface.uuid,
                title,
            ]
        )

    def send_command(self, terminal: SurfaceTarget, command: str) -> None:
        run_cmux(
            ["send", "--workspace", terminal.workspace, "--surface", terminal.uuid, command]
        )
        run_cmux(
            [
                "send-key",
                "--workspace",
                terminal.workspace,
                "--surface",
                terminal.uuid,
                "Enter",
            ]
        )

    def _read_screen(self, surface: SurfaceTarget, *, lines: int = 120) -> str:
        return run_cmux(
            [
                "read-screen",
                "--workspace",
                surface.workspace,
                "--surface",
                surface.uuid,
                "--scrollback",
                "--lines",
                str(lines),
            ]
        )

    def _surface_is_ready(self, surface: SurfaceTarget) -> bool:
        for item in cmux_get_surface_health(surface.workspace):
            item_ref = item.get("ref") or item.get("surface") or item.get("panel")
            item_id = item.get("id") or item.get("surface_id") or item.get("panel_id")
            if item_ref == surface.ref or item_id == surface.uuid:
                return bool(item.get("in_window"))
        return False

    def wait_ready(self, terminal: SurfaceTarget) -> None:
        deadline = time.time() + SHELL_READY_TIMEOUT
        consecutive_reads = 0
        while time.time() < deadline:
            if not self._surface_is_ready(terminal):
                time.sleep(POLL_INTERVAL)
                continue
            try:
                self._read_screen(terminal)
                consecutive_reads += 1
            except CommandError:
                consecutive_reads = 0
                time.sleep(POLL_INTERVAL)
                continue
            if consecutive_reads >= 2:
                return
            time.sleep(POLL_INTERVAL)
        raise CommandError(
            f"Surface {terminal.ref} ({terminal.uuid}) did not become ready within {SHELL_READY_TIMEOUT}s"
        )

    def list_terminals(self, workspace: str) -> list[TerminalInfo]:
        infos = []
        for panel in cmux_list_panels(workspace):
            panel_type = panel.get("type") or "terminal"
            infos.append(
                TerminalInfo(
                    ref=panel.get("ref") or "?",
                    title=panel.get("title"),
                    kind=panel_type,
                    handle=self._surface_target(workspace, panel)
                    if panel_type == "terminal"
                    else None,
                )
            )
        return infos

    def close_launcher(self, workspace: str) -> bool:
        calling_surface = os.environ.get("CMUX_SURFACE_ID")
        if not calling_surface:
            return False
        try:
            run_cmux(
                [
                    "close-surface",
                    "--workspace",
                    workspace,
                    "--surface",
                    calling_surface,
                ]
            )
            return True
        except CommandError:
            return False

    def describe_group(self, group_id: str, group: PaneTarget) -> dict[str, Any]:
        return {"id": group_id, "pane_ref": group.ref, "pane_uuid": group.uuid}

    def describe_terminal(self, terminal: SurfaceTarget) -> dict[str, Any]:
        return {
            "surface_ref": terminal.ref,
            "surface_uuid": terminal.uuid,
            "pane_ref": terminal.pane_ref,
            "pane_uuid": terminal.pane_uuid,
        }


# ---------- herdr backend ----------


@dataclass(frozen=True)
class HerdrGroup:
    workspace: str
    tab_id: str | None = None


@dataclass(frozen=True)
class HerdrTerminal:
    workspace: str
    tab_id: str
    pane_id: str


def run_herdr(args: list[str]) -> Any:
    output = run_process(["herdr", *args])
    if output.lstrip().startswith("{"):
        try:
            payload = json.loads(output)
        except json.JSONDecodeError as exc:
            raise CommandError(f"herdr returned invalid JSON: {exc}\n{output}") from exc
        if "error" in payload:
            error = payload["error"]
            message = error.get("message", output) if isinstance(error, dict) else str(error)
            raise CommandError(f"herdr {' '.join(args)}: {message}")
        return payload.get("result", payload)
    return output


class HerdrBackend(Backend):
    name = "herdr"
    _split_warned = False

    @staticmethod
    def detect() -> bool:
        return bool(
            os.environ.get("HERDR_WORKSPACE_ID") or os.environ.get("HERDR_SOCKET_PATH")
        )

    def current_workspace(self) -> str:
        env_workspace = os.environ.get("HERDR_WORKSPACE_ID")
        if env_workspace:
            return env_workspace
        result = run_herdr(["pane", "current"])
        workspace = result.get("pane", {}).get("workspace_id")
        if not workspace:
            raise CommandError("Could not determine current herdr workspace")
        return workspace

    def root_group(self, workspace: str) -> HerdrGroup:
        return HerdrGroup(workspace=workspace)

    def split_group(self, workspace: str, parent: HerdrGroup, direction: str) -> HerdrGroup:
        if not HerdrBackend._split_warned:
            HerdrBackend._split_warned = True
            print(
                "warning: herdr backend flattens pane splits into workspace tabs",
                file=sys.stderr,
            )
        return HerdrGroup(workspace=workspace)

    def create_terminal(self, workspace: str, group: HerdrGroup, title: str, cwd: str) -> HerdrTerminal:
        result = run_herdr(
            ["tab", "create", "--workspace", workspace, "--label", title, "--cwd", cwd]
        )
        tab_id = result.get("tab", {}).get("tab_id")
        pane_id = result.get("root_pane", {}).get("pane_id")
        if not tab_id or not pane_id:
            raise CommandError(f"herdr tab create returned incomplete ids: {result!r}")
        return HerdrTerminal(workspace=workspace, tab_id=tab_id, pane_id=pane_id)

    def send_command(self, terminal: HerdrTerminal, command: str) -> None:
        run_herdr(["pane", "run", terminal.pane_id, command])

    def _read_pane(self, terminal: HerdrTerminal) -> str:
        output = run_herdr(["pane", "read", terminal.pane_id])
        return output if isinstance(output, str) else ""

    def wait_ready(self, terminal: HerdrTerminal) -> None:
        deadline = time.time() + SHELL_READY_TIMEOUT
        consecutive_reads = 0
        while time.time() < deadline:
            try:
                if self._read_pane(terminal).strip():
                    consecutive_reads += 1
                else:
                    consecutive_reads = 0
            except CommandError:
                consecutive_reads = 0
            if consecutive_reads >= 2:
                return
            time.sleep(POLL_INTERVAL)
        raise CommandError(
            f"Pane {terminal.pane_id} did not become ready within {SHELL_READY_TIMEOUT}s"
        )

    def list_terminals(self, workspace: str) -> list[TerminalInfo]:
        result = run_herdr(["pane", "list", "--workspace", workspace])
        panes = result.get("panes") if isinstance(result, dict) else None
        if panes is None:
            raise CommandError(f"herdr pane list returned unexpected data: {result!r}")
        infos = []
        for pane in panes:
            pane_id = pane.get("pane_id")
            if not pane_id:
                continue
            kind = "agent" if pane.get("agent") else "terminal"
            infos.append(
                TerminalInfo(
                    ref=pane_id,
                    title=pane.get("terminal_title_stripped") or pane.get("terminal_title"),
                    kind=kind,
                    handle=HerdrTerminal(
                        workspace=workspace,
                        tab_id=pane.get("tab_id") or "",
                        pane_id=pane_id,
                    ),
                )
            )
        return infos

    def close_launcher(self, workspace: str) -> bool:
        tab_id = os.environ.get("HERDR_TAB_ID")
        if not tab_id:
            return False
        try:
            run_herdr(["tab", "close", tab_id])
            return True
        except CommandError:
            return False

    def describe_group(self, group_id: str, group: HerdrGroup) -> dict[str, Any]:
        return {"id": group_id}

    def describe_terminal(self, terminal: HerdrTerminal) -> dict[str, Any]:
        return {"herdr_tab_id": terminal.tab_id, "herdr_pane_id": terminal.pane_id}


# ---------- backend selection ----------


def detect_backend(requested: str) -> Backend:
    name = requested
    if name == "auto":
        if CmuxBackend.detect():
            name = "cmux"
        elif HerdrBackend.detect():
            name = "herdr"
        else:
            raise CommandError(
                "Could not detect terminal backend (neither CMUX_WORKSPACE_ID nor "
                "HERDR_WORKSPACE_ID is set); pass --backend cmux|herdr"
            )
    backends: dict[str, type[Backend]] = {"cmux": CmuxBackend, "herdr": HerdrBackend}
    return backends[name]()


# ---------- preset model ----------


@dataclass(frozen=True)
class PiLaunch:
    role: str


@dataclass(frozen=True)
class TabSpec:
    name: str
    command: str | None
    pi: PiLaunch | None
    pane_id: str
    split_from: str | None
    split_direction: str | None


@dataclass(frozen=True)
class Preset:
    path: Path
    id: str
    name: str
    description: str | None
    tabs: tuple[TabSpec, ...]


@dataclass(frozen=True)
class RenderedTab:
    pane_id: str
    order: int
    title: str
    startup_command: str | None


def render_template(text: str, *, dir_name: str, cwd: str) -> str:
    return text.format(dir=dir_name, cwd=cwd)


def build_pi_command(pi: PiLaunch, *, dir_name: str, cwd: str) -> str:
    link_name = f"{dir_name}@{pi.role}"
    return f"pi-link {shlex.quote(link_name)}"


def parse_pi_launch(
    source_path: Path, layout_id: str, tab_index: int, entry: dict[str, Any]
) -> PiLaunch:
    role = entry.get("role")
    if not isinstance(role, str) or not role.strip():
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} tab #{tab_index} has invalid pi.role; expected a non-empty string"
        )
    return PiLaunch(role=role.strip())


def parse_tab_entry(
    source_path: Path, layout_id: str, tab_index: int, tab_entry: dict[str, Any]
) -> TabSpec:
    tab_name = tab_entry.get("name")
    if not isinstance(tab_name, str) or not tab_name.strip():
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} tab #{tab_index} is missing a non-empty 'name'"
        )

    pane_id = tab_entry.get("pane") or "root"
    if not isinstance(pane_id, str) or not pane_id.strip():
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} tab #{tab_index} has an invalid 'pane'"
        )
    pane_id = pane_id.strip()

    split_from = tab_entry.get("split_from")
    if split_from is not None and (
        not isinstance(split_from, str) or not split_from.strip()
    ):
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} tab #{tab_index} has an invalid 'split_from'"
        )
    split_from = split_from.strip() if isinstance(split_from, str) else None

    split_direction = tab_entry.get("split")
    if split_direction is not None and split_direction not in {
        "left",
        "right",
        "up",
        "down",
    }:
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} tab #{tab_index} has invalid split direction {split_direction!r}"
        )

    command = tab_entry.get("command")
    if command is not None and (not isinstance(command, str) or not command.strip()):
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} tab #{tab_index} has an invalid 'command'"
        )

    pi_entry = tab_entry.get("pi")
    pi: PiLaunch | None = None
    if pi_entry is not None:
        if not isinstance(pi_entry, dict):
            raise CommandError(
                f"{source_path.name} layout {layout_id!r} tab #{tab_index} has an invalid [pi] table"
            )
        pi = parse_pi_launch(source_path, layout_id, tab_index, pi_entry)

    if command is not None and pi is not None:
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} tab #{tab_index} cannot define both command and pi"
        )

    return TabSpec(
        name=tab_name.strip(),
        command=command.strip() if isinstance(command, str) else None,
        pi=pi,
        pane_id=pane_id,
        split_from=split_from,
        split_direction=split_direction,
    )


def validate_tab_panes(source_path: Path, layout_id: str, tabs: list[TabSpec]) -> None:
    pane_defs: dict[str, tuple[str | None, str | None]] = {}
    pane_order: list[str] = []
    for tab in tabs:
        definition = (tab.split_from, tab.split_direction)
        if tab.pane_id in pane_defs:
            if pane_defs[tab.pane_id] != definition:
                raise CommandError(
                    f"{source_path.name} layout {layout_id!r} defines pane {tab.pane_id!r} with conflicting split settings"
                )
        else:
            pane_defs[tab.pane_id] = definition
            pane_order.append(tab.pane_id)

    root_candidates = [
        pane_id
        for pane_id, definition in pane_defs.items()
        if definition == (None, None)
    ]
    if len(root_candidates) != 1:
        raise CommandError(
            f"{source_path.name} layout {layout_id!r} must have exactly one root pane (tabs without split/split_from)"
        )

    for pane_id in pane_order:
        split_from, split_direction = pane_defs[pane_id]
        if split_from is None and split_direction is None:
            continue
        if split_from is None or split_direction is None:
            raise CommandError(
                f"{source_path.name} layout {layout_id!r} pane {pane_id!r} must define both split_from and split"
            )
        if split_from not in pane_defs:
            raise CommandError(
                f"{source_path.name} layout {layout_id!r} pane {pane_id!r} references unknown split_from {split_from!r}"
            )
        if pane_order.index(split_from) >= pane_order.index(pane_id):
            raise CommandError(
                f"{source_path.name} layout {layout_id!r} pane {pane_id!r} must appear after split_from pane {split_from!r}"
            )


def parse_preset_entry(source_path: Path, entry: dict[str, Any], index: int) -> Preset:
    preset_id = entry.get("id")
    if not isinstance(preset_id, str) or not preset_id.strip():
        raise CommandError(
            f"{source_path.name} layout #{index} is missing a non-empty 'id'"
        )
    preset_id = preset_id.strip()

    name = entry.get("name")
    if not isinstance(name, str) or not name.strip():
        raise CommandError(
            f"{source_path.name} layout {preset_id!r} is missing a non-empty 'name'"
        )

    description = entry.get("description")
    if description is not None and not isinstance(description, str):
        raise CommandError(
            f"{source_path.name} layout {preset_id!r} has a non-string 'description'"
        )

    tabs_data = entry.get("tabs")
    if not isinstance(tabs_data, list) or not tabs_data:
        raise CommandError(
            f"{source_path.name} layout {preset_id!r} must define a non-empty tabs array"
        )

    tabs: list[TabSpec] = []
    for tab_index, tab_entry in enumerate(tabs_data, start=1):
        if not isinstance(tab_entry, dict):
            raise CommandError(
                f"{source_path.name} layout {preset_id!r} tab #{tab_index} must be a table"
            )
        tabs.append(parse_tab_entry(source_path, preset_id, tab_index, tab_entry))

    validate_tab_panes(source_path, preset_id, tabs)

    return Preset(
        path=source_path,
        id=preset_id,
        name=name.strip(),
        description=description.strip() if isinstance(description, str) else None,
        tabs=tuple(tabs),
    )


def discover_presets(preset_dir: Path) -> list[Preset]:
    catalog_path = preset_dir / "layouts.toml"
    if not catalog_path.exists():
        raise CommandError(f"Preset catalog not found: {catalog_path}")

    with catalog_path.open("rb") as fh:
        data = tomllib.load(fh)

    layouts = data.get("layouts")
    if not isinstance(layouts, list) or not layouts:
        raise CommandError(
            f"{catalog_path.name} must define a non-empty [[layouts]] array"
        )

    presets = [
        parse_preset_entry(catalog_path, entry, index)
        for index, entry in enumerate(layouts, start=1)
    ]
    seen_ids: set[str] = set()
    for preset in presets:
        if preset.id in seen_ids:
            raise CommandError(
                f"Duplicate layout id in {catalog_path.name}: {preset.id}"
            )
        seen_ids.add(preset.id)
    return presets


def shutil_which(binary: str) -> str | None:
    import shutil

    return shutil.which(binary)


def choose_preset_with_fzf(presets: list[Preset]) -> Preset:
    fzf_path = shutil_which("fzf")
    if not fzf_path:
        raise CommandError("fzf is required when no preset is specified")

    lines = []
    lookup: dict[str, Preset] = {}
    for preset in presets:
        desc = preset.description or ""
        line = f"{preset.id}\t{preset.name}\t{desc}"
        lines.append(line)
        lookup[line] = preset

    selected = run_process(
        [fzf_path, "--with-nth=1,2,3", "--delimiter=\t", "--prompt", "layout preset> "],
        input_text="\n".join(lines),
    )
    preset = lookup.get(selected)
    if preset is None:
        raise CommandError("fzf returned an unknown preset selection")
    return preset


def resolve_preset(presets: list[Preset], query: str | None) -> Preset:
    if query is None:
        return choose_preset_with_fzf(presets)

    by_id = next((preset for preset in presets if preset.id == query), None)
    if by_id is not None:
        return by_id

    raise CommandError(f"Unknown preset: {query}")


def render_preset(preset: Preset, cwd: str) -> list[RenderedTab]:
    dir_name = os.path.basename(cwd)
    rendered_tabs: list[RenderedTab] = []
    for index, tab in enumerate(preset.tabs):
        if tab.command is not None:
            startup_command = render_template(tab.command, dir_name=dir_name, cwd=cwd)
        elif tab.pi is not None:
            startup_command = build_pi_command(tab.pi, dir_name=dir_name, cwd=cwd)
        else:
            startup_command = None
        rendered_tabs.append(
            RenderedTab(
                pane_id=tab.pane_id,
                order=index,
                title=render_template(tab.name, dir_name=dir_name, cwd=cwd),
                startup_command=startup_command,
            )
        )
    return rendered_tabs


# ---------- launch algorithms (backend-neutral) ----------


def initialize_tab(backend: Backend, terminal: Any, startup_command: str | None) -> None:
    if not startup_command:
        return
    backend.wait_ready(terminal)
    backend.send_command(terminal, startup_command)


def launch_preset(backend: Backend, preset: Preset) -> dict[str, Any]:
    workspace = backend.current_workspace()
    cwd = os.getcwd()
    rendered_tabs = render_preset(preset, cwd)

    group_targets: dict[str, Any] = {}
    root_group = backend.root_group(workspace)

    pane_sequence: list[TabSpec] = []
    seen_panes: set[str] = set()
    for tab in preset.tabs:
        if tab.pane_id not in seen_panes:
            pane_sequence.append(tab)
            seen_panes.add(tab.pane_id)

    for tab in pane_sequence:
        if tab.split_from is None:
            group_targets[tab.pane_id] = root_group
        else:
            parent = group_targets.get(tab.split_from)
            if parent is None:
                raise CommandError(
                    f"Pane {tab.pane_id!r} references split_from {tab.split_from!r} before it exists"
                )
            group_targets[tab.pane_id] = backend.split_group(
                workspace, parent, tab.split_direction or "right"
            )

    created_tabs: list[tuple[RenderedTab, Any]] = []
    reused_selected_by_pane: set[str] = set()
    for tab in reversed(rendered_tabs):
        group_target = group_targets[tab.pane_id]
        terminal = None
        if tab.pane_id != "root" and tab.pane_id not in reused_selected_by_pane:
            terminal = backend.reuse_terminal(group_target, tab.title)
            if terminal is not None:
                reused_selected_by_pane.add(tab.pane_id)
        if terminal is None:
            terminal = backend.create_terminal(workspace, group_target, tab.title, cwd)
        created_tabs.append((tab, terminal))

    initialization_errors: list[str] = []
    with ThreadPoolExecutor(max_workers=len(created_tabs) or 1) as executor:
        future_to_rendered = {
            executor.submit(initialize_tab, backend, terminal, rendered.startup_command): rendered
            for rendered, terminal in created_tabs
        }
        for future in as_completed(future_to_rendered):
            rendered = future_to_rendered[future]
            try:
                future.result()
            except (CommandError, OSError, ValueError, KeyError, TypeError) as exc:
                initialization_errors.append(f"{rendered.title}: {exc}")

    if initialization_errors:
        raise CommandError("; ".join(initialization_errors))

    launched = [
        {
            "pane_id": rendered.pane_id,
            "title": rendered.title,
            "startup_command": rendered.startup_command,
            **backend.describe_terminal(terminal),
        }
        for rendered, terminal in sorted(created_tabs, key=lambda item: item[0].order)
    ]

    panes = [
        backend.describe_group(group_id, group_targets[group_id])
        for group_id in group_targets
    ]

    launcher_closed = backend.close_launcher(workspace)

    return {
        "status": "ok",
        "backend": backend.name,
        "preset": preset.id,
        "name": preset.name,
        "description": preset.description,
        "workspace": workspace,
        "cwd": cwd,
        "parallel": True,
        "panes": panes,
        "launched": launched,
        "launcher_closed": launcher_closed,
    }


def collect_unique_tabs(presets: list[Preset]) -> list[TabSpec]:
    seen: set[tuple[str | None, str | None]] = set()
    result: list[TabSpec] = []
    for preset in presets:
        for tab in preset.tabs:
            pi_role = tab.pi.role if tab.pi else None
            key = (tab.command, pi_role)
            if key not in seen:
                seen.add(key)
                result.append(tab)
    return result


def choose_tab_with_fzf(tabs: list[TabSpec]) -> TabSpec:
    fzf_path = shutil_which("fzf")
    if not fzf_path:
        raise CommandError("fzf is required for tab selection")

    lines: list[str] = []
    lookup: dict[str, TabSpec] = {}
    for tab in tabs:
        if tab.pi:
            detail = f"pi: {tab.pi.role}"
        elif tab.command:
            detail = f"cmd: {tab.command}"
        else:
            detail = "shell"
        line = f"{tab.name}\t{detail}"
        lines.append(line)
        lookup[line] = tab

    selected = run_process(
        [fzf_path, "--with-nth=1,2", "--delimiter=\t", "--prompt", "add tab> "],
        input_text="\n".join(lines),
    )
    tab = lookup.get(selected)
    if tab is None:
        raise CommandError("fzf returned an unknown tab selection")
    return tab


def add_single_tab(backend: Backend, tab: TabSpec) -> dict[str, Any]:
    workspace = backend.current_workspace()
    cwd = os.getcwd()
    dir_name = os.path.basename(cwd)

    current_group = backend.root_group(workspace)

    title = render_template(tab.name, dir_name=dir_name, cwd=cwd)
    terminal = backend.create_terminal(workspace, current_group, title, cwd)

    if tab.command is not None:
        startup_command = render_template(tab.command, dir_name=dir_name, cwd=cwd)
    elif tab.pi is not None:
        startup_command = build_pi_command(tab.pi, dir_name=dir_name, cwd=cwd)
    else:
        startup_command = None

    initialize_tab(backend, terminal, startup_command)

    return {
        "status": "ok",
        "backend": backend.name,
        "action": "add",
        "tab_title": title,
        "startup_command": startup_command,
        **backend.describe_terminal(terminal),
        **backend.describe_group("current", current_group),
    }


def choose_dir_with_zoxide_fzf() -> str:
    zoxide_path = shutil_which("zoxide")
    if not zoxide_path:
        raise CommandError("zoxide is required for pick-dir")

    fzf_path = shutil_which("fzf")
    if not fzf_path:
        raise CommandError("fzf is required for pick-dir")

    candidates = run_process([zoxide_path, "query", "-l"])
    if not candidates:
        raise CommandError("zoxide returned no directories")

    selected = run_process(
        [fzf_path, "--prompt", "workspace dir> "],
        input_text=candidates,
    )
    path = Path(selected).expanduser()
    if not path.is_dir():
        raise CommandError(f"Selected path is not a directory: {selected}")
    return str(path)


def pick_workspace_dir(backend: Backend) -> dict[str, Any]:
    workspace = backend.current_workspace()
    selected_dir = choose_dir_with_zoxide_fzf()
    terminals = backend.list_terminals(workspace)

    changed: list[dict[str, str | None]] = []
    skipped: list[dict[str, str | None]] = []
    errors: list[str] = []
    cd_command = f"cd {shlex.quote(selected_dir)}"

    for info in terminals:
        if info.kind != "terminal":
            skipped.append(
                {"title": info.title, "ref": info.ref, "type": info.kind}
            )
            continue

        try:
            backend.send_command(info.handle, cd_command)
            changed.append({"title": info.title, "ref": info.ref})
        except (CommandError, OSError, ValueError, KeyError, TypeError) as exc:
            errors.append(f"{info.title or info.ref}: {exc}")

    if errors:
        raise CommandError("; ".join(errors))

    return {
        "status": "ok",
        "backend": backend.name,
        "action": "pick-dir",
        "workspace": workspace,
        "cwd": selected_dir,
        "changed": changed,
        "skipped": skipped,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Launch terminal layouts from TOML presets (cmux/herdr)"
    )
    parser.add_argument(
        "--backend",
        choices=["auto", "cmux", "herdr"],
        default=os.environ.get("LAYOUT_BACKEND", "auto"),
        help="Terminal multiplexer backend (default: auto-detect from environment)",
    )
    subparsers = parser.add_subparsers(dest="action")

    launch = subparsers.add_parser("launch", help="Launch a full layout preset")
    launch.add_argument(
        "preset",
        nargs="?",
        help="Layout id; if omitted, choose with fzf",
    )

    subparsers.add_parser("add", help="Add a single tab to current pane")

    subparsers.add_parser(
        "pick-dir",
        aliases=["pd"],
        help="Pick a zoxide directory and cd all terminal tabs in current workspace",
    )

    return parser


def main(argv: list[str]) -> int:
    raw_args = argv[1:]

    # Backward compat: no subcommand or non-subcommand first arg → treat as "launch"
    if not raw_args or (
        raw_args[0] not in ("launch", "add", "pick-dir", "pd", "--help", "-h")
        and not raw_args[0].startswith("-")
    ):
        raw_args = ["launch"] + raw_args

    parser = build_parser()
    args = parser.parse_args(raw_args)

    action = getattr(args, "action", None) or "launch"

    preset_dir = Path(__file__).resolve().parent
    try:
        backend = detect_backend(args.backend)
        if action == "add":
            presets = discover_presets(preset_dir)
            tabs = collect_unique_tabs(presets)
            tab = choose_tab_with_fzf(tabs)
            result = add_single_tab(backend, tab)
        elif action in ("pick-dir", "pd"):
            result = pick_workspace_dir(backend)
        else:
            presets = discover_presets(preset_dir)
            preset = resolve_preset(presets, args.preset)
            result = launch_preset(backend, preset)
    except Exception as exc:
        print(json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=False))
        return 1

    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
