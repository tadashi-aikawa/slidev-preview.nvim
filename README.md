# slidev-preview.nvim

Neovim plugin that syncs your Slidev presentation in the browser with your cursor position in `slides.md`.

## Features

- 📍 Cursor position → slide page synchronization
- 👆 Clicks increment/decrement commands for animations
- 🚀 Auto-start/stop Slidev dev server from Neovim
- ⚡ Debounced cursor tracking (no lag, no spam)
- 🧩 Frontmatter-aware slide parser (handles per-slide YAML frontmatter)
- 🔌 Pure Lua — no external dependencies

## Requirements

- Neovim ≥ 0.10
- Node.js (for Slidev)
- [Slidev](https://sli.dev/) installed in your project (`npm i @slidev/cli @slidev/theme-default`)

## Installation

### lazy.nvim

```lua
{
  'tadashi-aikawa/slidev-preview.nvim',
  ft = 'markdown',
  opts = {},
}
```

### Custom configuration

```lua
{
  'tadashi-aikawa/slidev-preview.nvim',
  ft = 'markdown',
  opts = {
    port = 3030,               -- Slidev dev server port
    debounce_ms = 200,         -- Cursor debounce interval (ms)
    slidev_bin = 'npx slidev', -- Command to run Slidev
  },
}
```

## Usage

### Commands

| Command | Description |
|---|---|
| `:SlidevPreviewStart` | Start Slidev dev server without opening browser. Enables cursor sync. |
| `:SlidevPreviewStartAndOpen` | Start Slidev dev server, then open browser. Enables cursor sync. |
| `:SlidevPreviewStop` | Stop the dev server and disable cursor sync. |
| `:SlidevPreviewRestart` | Restart the dev server without opening browser. Enables cursor sync. |
| `:SlidevPreviewOpen` | Open browser to the current slide (server must be running). |
| `:SlidevPreviewClicksIncrement` | Increment clicks for the previewed slide. |
| `:SlidevPreviewClicksDecrement` | Decrement clicks for the previewed slide. |
| `:SlidevPreviewNext` | Move to the next slide and sync the Neovim cursor. |
| `:SlidevPreviewPrevious` | Move to the previous slide and sync the Neovim cursor. |
| `:SlidevPreviewStatus` | Show current status (server, port, tracking, page). |

### Keymaps

The plugin does not set default keymaps. Assign the clicks commands to any keys you prefer:

```lua
vim.keymap.set('n', '<leader>sj', '<cmd>SlidevPreviewClicksIncrement<cr>', { desc = 'Slidev clicks +1' })
vim.keymap.set('n', '<leader>sk', '<cmd>SlidevPreviewClicksDecrement<cr>', { desc = 'Slidev clicks -1' })
vim.keymap.set('n', '<leader>sn', '<cmd>SlidevPreviewNext<cr>', { desc = 'Slidev next slide' })
vim.keymap.set('n', '<leader>sp', '<cmd>SlidevPreviewPrevious<cr>', { desc = 'Slidev previous slide' })
```

### Workflow

1. Open `slides.md` in Neovim
2. Run `:SlidevPreviewStart`
3. Open the browser later with `:SlidevPreviewOpen`, or use `:SlidevPreviewStartAndOpen` if you want to open it immediately
4. Move your cursor — the browser follows!

If you prefer to start the Slidev dev server yourself (e.g., in a separate terminal), just use `:SlidevPreviewOpen` to open the browser and enable cursor sync.

## How it Works

```
Neovim (CursorMoved + debounce)
  → Parse slides.md to determine current page
  → HTTP POST to Slidev's /@server-reactive/nav endpoint
  → vite-plugin-vue-server-ref broadcasts via WebSocket
  → Browser navigates to the target slide
```

The plugin communicates with Slidev's built-in `vite-plugin-vue-server-ref` infrastructure. No additional Slidev addons or browser extensions are required.

> **Note**: The `--remote` flag is automatically passed to `slidev dev` to enable shared navigation state.

## Testing

```bash
nvim --headless -l tests/parser_spec.lua
nvim --headless -l tests/clicks_spec.lua
```

## License

MIT
