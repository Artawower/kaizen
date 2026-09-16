import json
import subprocess


def _trun():
    """Pick and run a project task using runner + fzf."""

    result = subprocess.run(
        ["runner", "list", "--json", "--schema-version", "1"],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(result.stderr, end="")
        return

    data = json.loads(result.stdout)
    tasks = data.get("tasks", [])

    if not tasks:
        print("No tasks found.")
        return

    lines = []

    for i, task in enumerate(tasks):
        name = task["name"]
        source = task["source"]

        description = (
            task.get("description")
            or task.get("alias_of")
            or task.get("passthrough_to")
            or ""
        )

        lines.append(f"{i}\t{name}\t{source}\t{description}")

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

    name = task["name"]
    source = task["source"]

    # Qualify the task so the exact selected provider is used.
    target = f"{source}:{name}"

    subprocess.run(["run", target])


aliases["trun"] = _trun
