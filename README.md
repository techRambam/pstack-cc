# pstack-cc

This repository is a Claude Code marketplace with two plugins, each copied from upstream.

| Plugin | Upstream | Commit |
| --- | --- | --- |
| `pstack` | [cursor/plugins `harness/pstack/claude-code`](https://github.com/cursor/plugins/tree/6b0300214a09fd6029cfb7077043125758cd1fd2/harness/pstack/claude-code) | `6b0300214a09fd6029cfb7077043125758cd1fd2` |
| `mattpocock-skills` | [mattpocock/skills](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d) | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` |

`./sync.sh main main` copies the latest upstream `main` of both. `./sync.sh` with no arguments copies the commits in `upstream.lock` again.
