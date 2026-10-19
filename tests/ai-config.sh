#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/source"
cp "$repo_root/dotfiles/.chezmoidata.toml" "$tmp_dir/source/.chezmoidata.toml"

for target in eca/config opencode/opencode; do
    chezmoi execute-template \
        --source "$tmp_dir/source" \
        --file "$repo_root/dotfiles/dot_config/$target.json.tmpl" \
        > "$tmp_dir/${target%%/*}.json"
done

python3 - "$repo_root" "$tmp_dir" <<'PY'
import json
import re
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
rendered = Path(sys.argv[2])
pi_root = root / 'dotfiles/dot_pi/agent'
pi = json.loads((pi_root / 'settings.json').read_text())
mcp = json.loads((pi_root / 'mcp.json').read_text())['mcpServers']
eca = json.loads((rendered / 'eca.json').read_text())
opencode = json.loads((rendered / 'opencode.json').read_text())
models = tomllib.loads((root / 'dotfiles/.chezmoidata.toml').read_text())['models']

packages = [entry if isinstance(entry, str) else entry['source'] for entry in pi['packages']]
assert len(packages) == len(set(packages))
assert all(entry.startswith(('npm:', 'git:')) for entry in packages)
assert packages.count('git:github.com/Artawower/pi-servitors') == 1
assert 'npm:pi-open-agents' in packages
assert 'npm:pi-mermaid' not in packages
assert 'npm:@singh-gur/pi-usage' in packages
assert all('extension' not in entry for entry in pi['packages'] if isinstance(entry, dict))
assert 'pi-servitors' in (pi_root / 'AGENTS.md').read_text()
assert not (pi_root / 'extensions/swarm-prompt.ts').exists()
assert not (pi_root / 'agents_old').exists()
print('PASS: Pi package and orchestration configuration')

assert pi['defaultProvider'] == 'openai-codex'
assert pi['defaultModel'] == models['research'].split('/', 1)[1]
assert all(model.split('/', 1)[0] in {'anthropic', 'openai', 'google'} for model in models.values())
assert eca['defaultModel'] == opencode['model'] == models['default']
assert opencode['small_model'] == models['quick']
assert 'models' not in opencode['provider']['openai']
assert not any(name.startswith('opencode-openai-codex-auth') for name in opencode['plugin'])
assert '{file:' not in opencode['agent']['translator']['prompt']
print('PASS: client-specific model routes and native OpenCode catalog')

allowed_mcp_keys = {'command', 'args', 'url', 'headers', 'enabled', 'exposure', 'description'}
assert {name for name, server in mcp.items() if server.get('enabled', True)} == {'context7', 'exa'}
for server in mcp.values():
    assert not set(server) - allowed_mcp_keys
    assert ('url' in server) != ('command' in server)
    assert server['exposure'] == 'codemode'
    assert server['description']
for servers in [mcp, eca['mcpServers'], opencode['mcp']]:
    assert 'youtrack' not in servers
for server in [mcp['context7'], eca['mcpServers']['context7'], opencode['mcp']['context7']]:
    assert server['url'] == 'https://mcp.context7.com/mcp'
    assert 'command' not in server
for name in ['sequential-thinking', 'deepcontext', 'qmd']:
    assert mcp[name]['enabled'] is False
    assert eca['mcpServers'][name]['disabled'] is True
    assert opencode['mcp'][name]['enabled'] is False
assert mcp['context-mode']['enabled'] is False
assert opencode['mcp']['context-mode']['enabled'] is False
assert 'context-mode' not in opencode['plugin']
assert mcp['serena']['enabled'] is False
assert 'serena-agent' in mcp['serena']['args']
assert not eca['mcpServers']['serena'].get('disabled', False)
assert eca['mcpToolSearch'] == {'includePattern': ['.*']}
print('PASS: bounded MCP defaults and native HTTP')

assert eca['defaultAgent'] == 'code'
assert 'behavior' not in eca
assert 'toolCall' not in eca
assert eca['prompts']['completion'].endswith('/.config/eca/agents/completion.md}')
print('PASS: ECA uses native approval defaults and optional orchestration')

skills = root / 'dotfiles/dot_agents/skills'
playwright = skills / 'playwright-cli'
skill = (playwright / 'SKILL.md').read_text()
assert '\nname: playwright-cli\n' in skill
references = re.findall(r'\]\((references/[^)]+)\)', skill)
assert references
assert all((playwright / reference).is_file() for reference in references)
assert not (playwright / 'LICENSE').exists()
assert not (playwright / 'UPSTREAM.md').exists()
assert not (root / 'dotfiles/dot_agents/private_skill-lock.json').exists()
assert not (root / 'dotfiles/dot_agents/private_dot_skill-lock.json').exists()
assert any(entry['path'].endswith('/.agents/skills/playwright-cli') for entry in eca['skills'])
tools = tomllib.loads((root / 'features/tools.toml').read_text())['ai']['tools']
assert tools['npm:@playwright/cli'] == '0.1.22'
assert tools['npm:skills'] == 'latest'
for servers in [mcp, eca['mcpServers'], opencode['mcp']]:
    assert 'playwright' not in servers
print('PASS: Playwright CLI skill and ECA discovery replace browser MCP')

policy = root / 'dotfiles/dot_agents/references/code-reviewer.md'
assert policy.is_file()
assert 'arbitrary line limit' in policy.read_text()
for name in ['writing-for-agents', 'grilling', 'domain-modeling']:
    assert (skills / name / 'SKILL.md').is_file(), name
agent_guidance = (root / 'dotfiles/literal_AGENTS.md').read_text()
assert 'nearest project-specific `AGENTS.md`' in agent_guidance
assert 'Use Jujutsu (`jj`) for all repository version-control work' in agent_guidance
assert 'Never invoke `git` directly' in agent_guidance
assert 'stop and ask; do not fall back to Git' in agent_guidance
assert 'External skills are immutable' in agent_guidance
assert 'Never manually edit, reformat, patch, or add files' in agent_guidance
assert 'Never change a lock-file hash to legitimize a local patch' in agent_guidance
assert 'chezmoi source-path' in agent_guidance
assert 'nix-darwin' not in agent_guidance
assert 'immutable external dependencies' in (root / 'AGENTS.md').read_text()
for name in ['consensus-review', 'jj-review', 'pr-review']:
    assert '../../references/code-reviewer.md' in (skills / name / 'SKILL.md').read_text(), name
    assert not (skills / name / 'references/code-reviewer.md').exists(), name
assert not (skills / 'code-review/references/code-reviewer.md').exists()
assert 'when requested' in (skills / 'consensus-review/SKILL.md').read_text()
context = (skills / 'context-mode/SKILL.md').read_text()
assert 'Optional indexed analysis' in context
assert 'continue with native tools' in context
assert 'MANDATORY RULE' not in context
for name in ['link-implement', 'link-msg', 'link-review']:
    content = (skills / name / 'SKILL.md').read_text()
    assert 'pi-servitors' in content
    assert 'link_prompt' not in content
for client, directory in [('eca', 'commands'), ('opencode', 'command')]:
    command = (root / f'dotfiles/dot_config/{client}/{directory}/one-shot.md').read_text()
    assert 'jj diff' in command
    assert all(name not in command for name in ['TodoWrite', 'call_omo_agent', 'NON-NEGOTIABLE'])
for path in (root / 'dotfiles/dot_config/eca/agents').glob('*.md*'):
    if path.stem in {'manager', 'completion', 'executor'}:
        continue
    header = path.read_text().split('---', 2)[1]
    assert 'disabledTools:' in header, path
    assert all(f'- {tool}' in header for tool in ['write_file', 'edit_file', 'move_file', 'shell_command', 'spawn_agent']), path
for path in [root / 'dotfiles/dot_config/eca/agents/code-reviewer.md', root / 'dotfiles/dot_config/opencode/agent/code-reviewer.md']:
    assert '~/.agents/references/code-reviewer.md' in path.read_text()
assert '~/.config/ai/skills/' not in (skills / 'pr-review/SKILL.md').read_text()
print('PASS: local review policy, immutable external skills, Jujutsu guidance and delegation contract')
PY

cp "$repo_root/dotfiles/.chezmoiremove" "$tmp_dir/source/.chezmoiremove"
cp "$repo_root/dotfiles/literal_AGENTS.md" "$tmp_dir/source/literal_AGENTS.md"
mkdir -p "$tmp_dir/source/dot_agents/references"
cp "$repo_root/dotfiles/dot_agents/references/code-reviewer.md" "$tmp_dir/source/dot_agents/references/code-reviewer.md"
python3 - "$tmp_dir" <<'PY'
import sys
from pathlib import Path

temporary = Path(sys.argv[1])
for name in (temporary / 'source/.chezmoiremove').read_text().splitlines():
    path = temporary / 'target' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('legacy artifact')
sentinel = temporary / 'target/.pi/agent/agents_old/user-note.md'
sentinel.write_text('preserve unrelated files')
PY

chezmoi --source "$tmp_dir/source" --destination "$tmp_dir/target" --force apply
python3 - "$tmp_dir" <<'PY'
import sys
from pathlib import Path

temporary = Path(sys.argv[1])
for name in (temporary / 'source/.chezmoiremove').read_text().splitlines():
    assert not (temporary / 'target' / name).exists(), name
assert (temporary / 'target/.pi/agent/agents_old/user-note.md').read_text() == 'preserve unrelated files'
assert (temporary / 'target/AGENTS.md').read_bytes() == (temporary / 'source/literal_AGENTS.md').read_bytes()
assert (temporary / 'target/.agents/references/code-reviewer.md').read_bytes() == (temporary / 'source/dot_agents/references/code-reviewer.md').read_bytes()
print('PASS: chezmoi deploys global guidance and local policy, removing only named obsolete artifacts')
PY
