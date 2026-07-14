"""Python preset: pyright + ty"""


def servers():
    return [
        ["codebook-lsp", "serve"],
        ["ty", "server"],
        # ["pyrefly", "lsp"], Currently, pyrefly doesn't work for all scenarios.
    ]
