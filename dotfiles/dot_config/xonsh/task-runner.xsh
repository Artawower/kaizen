import json
import os
import subprocess
import time

from xonsh.completers.tools import RichCompletion

_CACHE_TTL_SECONDS = 5.0
_tasks_cache = {}


def _list_tasks():
    now = time.monotonic()
    cwd = os.getcwd()
    cached = _tasks_cache.get(cwd)

    if cached and now - cached[0] < _CACHE_TTL_SECONDS:
        return cached[1]

    result = subprocess.run(
        ["runner", "list", "--json", "--schema-version", "1"],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        return []

    tasks = json.loads(result.stdout).get("tasks", [])
    _tasks_cache.clear()
    _tasks_cache[cwd] = (now, tasks)
    return tasks


def _task_description(task):
    return (
        task.get("description")
        or task.get("alias_of")
        or task.get("passthrough_to")
        or ""
    )


def _trun_completer(prefix, line, begidx, endidx, ctx):
    words = line.split()

    if not words or words[0] != "trun":
        return None

    if len(words) > 2 or (len(words) == 2 and line.endswith(" ")):
        return None

    grouped = {}
    for task in _list_tasks():
        grouped.setdefault(task["name"], []).append(task)

    completions = set()

    for name, group in grouped.items():
        for task in group:
            value = name if len(group) == 1 else f"{task['source']}:{name}"

            if not (value.startswith(prefix) or name.startswith(prefix)):
                continue

            completions.add(RichCompletion(
                value,
                display=name,
                description=f"[{task['source']}] {_task_description(task)}",
                append_space=True,
            ))

    return completions if completions else None


def _run_task(target, tasks):
    if ":" in target:
        subprocess.run(["run", target])
        return

    matches = [task for task in tasks if task["name"] == target]

    if not matches:
        print(f"No such task: {target}")
        return

    if len(matches) > 1:
        sources = ", ".join(task["source"] for task in matches)
        print(f"Task '{target}' is ambiguous ({sources}), use source:name")
        return

    subprocess.run(["run", target])


def _pick_task(tasks):
    lines = []

    for i, task in enumerate(tasks):
        lines.append("\t".join([
            str(i),
            task["name"],
            task["source"],
            _task_description(task),
        ]))

    selected = subprocess.run(
        [
            "fzf",
            "--delimiter=\t",
            "--with-nth=2,3,4",
            "--prompt=Run ❯ ",
            "--header=COMMAND\tSOURCE\tDESCRIPTION",
            "--reverse",
            "--border=rounded",
            "--height=60%",
        ],
        input="\n".join(lines),
        capture_output=True,
        text=True,
    )

    if selected.returncode != 0 or not selected.stdout.strip():
        return

    index = int(selected.stdout.split("\t", 1)[0])
    task = tasks[index]

    # Qualify the task so the exact selected provider is used.
    subprocess.run(["run", f"{task['source']}:{task['name']}"])


def _trun(args):
    """Pick and run a project task using runner + fzf."""

    tasks = _list_tasks()

    if not tasks:
        print("No tasks found.")
        return

    if args:
        _run_task(args[0], tasks)
    else:
        _pick_task(tasks)


aliases["trun"] = _trun

__xonsh__.completers["trun"] = _trun_completer
__xonsh__.completers.move_to_end("trun", last=False)
