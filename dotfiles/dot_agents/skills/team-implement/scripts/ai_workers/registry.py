from .base import MultiplexerAdapter
from .adapters.herdr import HerdrAdapter
from .adapters.tmux import TmuxAdapter
from .adapters.zellij import ZellijAdapter

_ADAPTERS: list[MultiplexerAdapter] = [
    HerdrAdapter(),
    ZellijAdapter(),
    TmuxAdapter(),
]


def detect() -> MultiplexerAdapter:
    for adapter in _ADAPTERS:
        if adapter.is_available():
            return adapter
    raise RuntimeError(
        "No supported multiplexer detected. "
        "Run inside herdr (HERDR_ENV=1), zellij (ZELLIJ), or tmux (TMUX)."
    )
