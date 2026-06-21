# slidev-preview.nvim

Neovim plugin that syncs your Slidev presentation in the browser with your cursor position in `slides.md`.

## Features

- 📍 Cursor position → slide page synchronization
- 👆 Clicks increment/decrement commands for animations
- 🎮 Control mode for repeated slide/click operations
- 🪟 Winbar indicator showing the synced buffer and control-mode state
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
    slide_position = 'zz',     -- Cursor screen position after slide navigation: 'zt', 'zz', or 'zb'
    control = {
      keys = {
        next_slide = { 'j' },
        previous_slide = { 'k' },
        first_slide = { 'gg' },
        last_slide = { 'G' },
        forward = { 'l' },
        backward = { 'h' },
        exit = { 'q', '<Esc>', '<C-c>' },
      },
    },
    ui = {
      winbar = true,             -- Show a winbar indicator on the synced buffer
      icons = {
        slide = 'page',         -- Icon shown before the page number
        click = 'click',        -- Icon shown before the clicks (control mode)
        control = 'control',    -- Icon shown in control mode
      },
    },
  },
}
```

### Winbar indicator

When the preview is running, the synced buffer shows a winbar so you can tell at
a glance that the buffer is being mirrored to the browser, and whether control
mode is active. Normal mode shows the page number with a total; control mode
prepends the control icon and adds the current clicks:

```
  3/10              (normal: <slide icon> page/total)
  control   3/10   1/2   (control mode: <control icon>  <slide> page/total  <click> clicks)
```

The icons use Nerd Font glyphs by default; override `ui.icons` (set any to `''`
to hide it) if your font differs. Set `ui.winbar = false` to disable the winbar
entirely. The colors come from two highlight groups that you can override:

```lua
vim.api.nvim_set_hl(0, 'SlidevPreviewWinbar', { link = 'WinBar' })    -- normal
vim.api.nvim_set_hl(0, 'SlidevPreviewControl', { link = 'IncSearch' }) -- control mode
```

#### Using it with lualine

If you use a winbar/statusline plugin such as
[lualine](https://github.com/nvim-lualine/lualine.nvim), it manages the `winbar`
option and overrides the one this plugin sets. Disable the built-in winbar and
add `require('slidev-preview').winbar` as a lualine component instead:

```lua
require('slidev-preview').setup({
  ui = { winbar = false }, -- let lualine own the winbar
})

require('lualine').setup({
  winbar = {
    lualine_c = { require('slidev-preview').winbar },
  },
  inactive_winbar = {
    lualine_c = { require('slidev-preview').winbar },
  },
})
```

`require('slidev-preview').winbar` returns an empty string for any window that is
not the synced Slidev buffer, so it stays out of the way elsewhere. It also works
in lualine's `sections` (statusline) if you prefer it there.

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
| `:SlidevPreviewControl` | Enter control mode for repeated slide/click operations. |
| `:SlidevPreviewStatus` | Show current status (server, port, tracking, page). |

### Keymaps

The plugin does not set default keymaps. Assign the clicks commands to any keys you prefer:

```lua
vim.keymap.set('n', '<leader>sj', '<cmd>SlidevPreviewClicksIncrement<cr>', { desc = 'Slidev clicks +1' })
vim.keymap.set('n', '<leader>sk', '<cmd>SlidevPreviewClicksDecrement<cr>', { desc = 'Slidev clicks -1' })
vim.keymap.set('n', '<leader>sn', '<cmd>SlidevPreviewNext<cr>', { desc = 'Slidev next slide' })
vim.keymap.set('n', '<leader>sp', '<cmd>SlidevPreviewPrevious<cr>', { desc = 'Slidev previous slide' })
vim.keymap.set('n', '<leader>sm', '<cmd>SlidevPreviewControl<cr>', { desc = 'Slidev control mode' })
```

### Control mode

Run `:SlidevPreviewControl` to enter a temporary control mode. By default, press `j` for next slide, `k` for previous slide, `{count}j` or `{count}k` to move multiple slides, `gg` for the first slide, `G` for the last slide, `{count}G` for a numbered slide, `l` to move forward through clicks or slides, `h` to move backward through clicks or slides, and `q`, `<Esc>`, or `<C-c>` to exit. Count prefixes apply to the configured `next_slide`, `previous_slide`, and `last_slide` keys.

You can replace any action keys in `opts.control.keys`:

```lua
require('slidev-preview').setup({
  control = {
    keys = {
      next_slide = { '<Down>' },
      previous_slide = { '<Up>' },
      first_slide = { 'gg' },
      last_slide = { 'G' },
      forward = { '<Right>' },
      backward = { '<Left>' },
      exit = { 'q', '<Esc>' },
    },
  },
})
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
nvim --headless -l tests/control_spec.lua
nvim --headless -l tests/parser_spec.lua
nvim --headless -l tests/clicks_spec.lua
nvim --headless -l tests/ui_spec.lua
```

## License

MIT
