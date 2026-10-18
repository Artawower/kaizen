#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$repo_root" <<'PY'
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

source = Path(sys.argv[1]) / "dotfiles/dot_config/scripts/executable_devcache"
loader = importlib.machinery.SourceFileLoader("devcache_test", str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
devcache = importlib.util.module_from_spec(spec)
loader.exec_module(devcache)


def command(*args):
    stdout, stderr = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
        code = devcache.cli(list(args))
    return code, stdout.getvalue(), stderr.getvalue()


with tempfile.TemporaryDirectory() as directory:
    home = Path(directory) / "home"
    environment = {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "DEVCACHE_TEST_MODE": "1",
    }
    with patch.dict(os.environ, environment), patch.object(sys, "platform", "linux"):
        paths = devcache.layout()
        assert not home.exists()
        assert command("status")[:2] == (0, "Not configured\n")
        assert not home.exists()
        code, out, err = command("setup", "--local-only", "--adapters", "npm,pip", "--dry-run")
        assert code == 0, err
        assert "per command" in out
        assert not home.exists()

        code, _, err = command("setup", "--local-only", "--adapters", "npm,pip", "--yes")
        assert code == 0, err
        config = devcache.load()
        assert config["routing"] == "per-command"
        assert config["adapters"] == ["npm", "pip"]
        assert paths["config"].name == "config.json"
        assert paths["root"].is_symlink()
        assert paths["root"].resolve() == paths["local"].resolve()
        assert not paths["unit_dir"].exists()
        assert paths["env"].is_file()
        status = json.loads(command("status")[1])
        assert status["route"] == "per-command"
        assert status["ordinary_commands"] == "local"
        assert status["automatic_cleanup"] is False
        assert command("doctor")[0] == 0
        assert str(paths["local"] / "npm") in command("env", "--shell", "bash")[1]
        assert str(paths["local"] / "pip") in command("env", "--shell", "xonsh")[1]

        with patch.object(devcache.subprocess, "run", return_value=subprocess.CompletedProcess([], 7)) as run:
            assert command("run", "--", "sample-tool", "arg")[0] == 7
            run.assert_called_once()
            assert run.call_args.args[0] == ["sample-tool", "arg"]
            assert run.call_args.kwargs["env"]["npm_config_cache"] == str(paths["local"] / "npm")
        with patch.object(devcache.subprocess, "run") as run:
            assert command("gc", "--auto")[0] == 0
            run.assert_not_called()

        with devcache.lock():
            code, _, err = command("disable")
            assert code == 1 and "busy" in err
        assert devcache.load()["enabled"] is True

        invalid = dict(config, adapters=["npm", "npm"])
        try:
            devcache.validate_config(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("duplicate adapters accepted")

        assert command("disable")[0] == 0
        assert devcache.load()["enabled"] is False
        assert command("enable")[0] == 0
        assert devcache.load()["enabled"] is True
        paths["config"].write_text("invalid JSON")
        assert command("status")[0] == 1
        assert command("recover-config")[0] == 0
        assert devcache.load()["enabled"] is True

        marker = paths["local"] / "keep"
        marker.write_text("cache data")
        paths["env"].write_text("USER_SETTING=preserve\n")
        assert command("uninstall")[0] == 0
        assert not paths["config"].exists()
        assert not paths["root"].is_symlink()
        assert marker.read_text() == "cache data"
        assert paths["env"].read_text() == "USER_SETTING=preserve\n"

print("Rootless DevCache regression tests passed")
PY
