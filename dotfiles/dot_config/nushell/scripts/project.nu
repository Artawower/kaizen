export def --env angular-init [
    name: string
    --ngrx = false
    --tailwind = false
    --eslint = true
    --prettier = true
    --flat = false
    --actions = false
] {
    let directory = if $flat { "." } else { $name }

    bunx @angular/cli new $name --directory $directory --strict --routing --style=css --package-manager=bun --defaults

    if $env.LAST_EXIT_CODE != 0 {
        error make { msg: "Angular setup failed" }
    }

    if not $flat {
        cd $name
    }

    if not ("angular.json" | path exists) {
        error make { msg: $"Not an Angular workspace: (pwd)" }
    }

    if $tailwind {
        bunx ng add tailwindcss --defaults
        check-exit "Tailwind setup failed"
    }

    if $eslint {
        bunx ng add angular-eslint --defaults
        check-exit "ESLint setup failed"
    }

    if $ngrx {
        bunx ng add @ngrx/store --defaults
        check-exit "NgRx setup failed"
    }

    if $prettier {
        bun add -d prettier
        check-exit "Prettier installation failed"

        '{ "singleQuote": true }' | save -f .prettierrc
    }

    if $actions {
        setup-ci
    }
}

def check-exit [message: string] {
    if $env.LAST_EXIT_CODE != 0 {
        error make { msg: $message }
    }
}

def setup-ci [] {
    mkdir .github/workflows

    let content = r##'
name: CI and deployment

on:
  pull_request:
    branches:
      - master
  push:
    branches:
      - master

permissions:
  contents: read

jobs:
  conventional-commits:
    name: Validate Conventional Commits
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    steps:
      - name: Check out repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          persist-credentials: false

      - name: Lint commit messages
        uses: wagoid/commitlint-github-action@v6

  quality:
    name: Lint, test, and build
    needs: conventional-commits
    runs-on: ubuntu-latest
    steps:
      - name: Check out repository
        uses: actions/checkout@v4
        with:
          persist-credentials: false

      - name: Set up Bun
        uses: oven-sh/setup-bun@v2

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Lint
        run: bun run lint

      - name: Test
        run: bun run test -- --run
'##

    $content | str trim | save -f .github/workflows/ci.yml
}
