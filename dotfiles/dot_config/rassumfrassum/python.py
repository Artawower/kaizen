"""Use ty as primary because Rass routes hover requests to the first server."""


def servers():
    return [
        ["ty", "server"],
        ["codebook-lsp", "serve"],
        # ["pyrefly", "lsp"], Currently, pyrefly doesn't work for all scenarios.
    ]
