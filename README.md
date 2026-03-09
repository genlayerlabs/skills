# GenLayer Skills

A [Claude Code](https://claude.ai/code) plugin marketplace providing operational skills for GenLayer infrastructure.

## Installation

```bash
# Add the marketplace
/plugin marketplace add genlayerlabs/claude-code-skills

# Install a plugin
/plugin install genlayernode@genlayerlabs
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| `genlayernode` | Interactive wizard to set up a GenLayer validator node on Linux. |

## Usage

After installing a plugin, invoke its skill with a specific command:

### genlayernode

| Command | Description |
|---------|-------------|
| `/genlayernode install` | Install a new GenLayer validator node |
| `/genlayernode update` | Update an existing validator node to the latest version |
| `/genlayernode configure grafana` | Configure Grafana monitoring for your node |