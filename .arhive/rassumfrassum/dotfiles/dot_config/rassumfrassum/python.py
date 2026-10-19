"""Use ty as primary because Rass routes hover requests to the first server."""


def servers():
    return [
        ["ruff", "server"],
        ["ty", "server"],
        ["codebook-lsp", "serve"],
        # ["pyrefly", "lsp"], Currently, pyrefly doesn't work for all scenarios.
    ]
