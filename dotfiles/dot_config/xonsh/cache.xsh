import hashlib
import shutil
import subprocess
from pathlib import Path

CACHE_DIR = Path.home() / '.cache' / 'xonsh'


def cached_init(name, argv):
    binary = shutil.which(argv[0])
    if not binary:
        return None
    real = Path(binary).resolve()
    stat = real.stat()
    key_src = f"{argv}|{real}|{stat.st_mtime_ns}|{stat.st_size}"
    key = hashlib.sha256(key_src.encode()).hexdigest()[:16]
    cache_file = CACHE_DIR / f'{name}-{key}.xsh'
    if cache_file.exists():
        return cache_file.read_text()
    output = subprocess.run(
        [str(real), *argv[1:]],
        env=__xonsh__.env.detype(),
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    for stale in CACHE_DIR.glob(f'{name}-*.xsh'):
        stale.unlink()
    cache_file.write_text(output)
    return output
