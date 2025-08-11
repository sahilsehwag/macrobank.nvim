# macrobank.nvim

A powerful Neovim plugin for managing, editing, and organizing macros with persistent storage across sessions and projects.

## ✨ Features

- 📝 **Live Macro Editor**: Edit macros in real-time with quick navigation (a-z keys) and clean interface
- 💾 **Persistent Storage**: Save macros globally or per-project with multiple scoping options
- 🎯 **Smart Selection**: Interactive macro picker with fuzzy matching
- 🔄 **Quick Playback**: Execute saved macros instantly with commands or keymaps
- 📁 **Project Support**: Automatic project-local macro discovery
- 🎨 **Rich UI**: Clean interface with Nerd Font icons (optional)
- ⚡ **Fast Access**: Built-in commands and customizable key mappings

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "sahilsehwag/macrobank.nvim",
  config = function()
    require("macrobank").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "sahilsehwag/macrobank.nvim",
  config = function()
    require("macrobank").setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'sahilsehwag/macrobank.nvim'
```

Then add to your `init.lua`:
```lua
require("macrobank").setup()
```

## ⚙️ Configuration

### Default Configuration

```lua
require("macrobank").setup({
  -- Global store (always read; also the fallback write target)
  store_path_global = vim.fn.stdpath('config') .. '/macrobank_store.json',

  -- Project-local store discovery:
  --  - string: override defaults (single relative path, e.g. '.nvim/macrobank.json')
  --  - list:   merge with defaults below
  project_store_paths = nil, -- {'.macrobank.json', '.nvim/macrobank.json'} or '.macrobank.json'

  default_select_register = 'q',  -- register to load selected macro into
  default_play_register   = 'q',  -- temporary register used to play from bank
  nerd_icons = true,              -- use nerdfont icons in UI labels

  window = {                     -- editor window dimensions
    width  = 0.7,                -- fraction of columns or absolute number
    height = 0.7,                -- fraction of lines   or absolute number
  },

  -- Editor buffer mappings override (optional)
  live_editor_mappings = {},      -- override live editor buffer mappings: {action_name = 'keymap' | false}
  bank_editor_mappings = {},      -- override bank editor buffer mappings: {action_name = 'keymap' | false}
})
```

### Custom Configuration Example

```lua
require("macrobank").setup({
  -- Use larger editor window
  window = {
    width = 0.8,
    height = 0.8,
  },
  
  -- Custom project store paths
  project_store_paths = {'.macros.json', '.config/macros.json'},
  
  -- Different default registers
  default_select_register = 'x',
  default_play_register = 'y',
  
  -- Disable nerd font icons
  nerd_icons = false,
  
  -- Override editor buffer mappings (optional)
  live_editor_mappings = {
    save = '<leader>s',       -- change save key from <C-s> to <leader>s
    delete = false,           -- disable delete key entirely
    play = '<Space>',         -- change play key from <CR> to <Space>
  },
  bank_editor_mappings = {
    search = '/',             -- change search key from g/ back to /
    history = false,          -- disable history feature
    load = '<leader>l',       -- change load key from @ to <leader>l
  },
})
```

## 🚀 Usage

### Commands

| Command | Description |
|---------|-------------|
| `:MacroBankLive` | Open the Live Macro Editor to view/edit current registers |
| `:MacroBank` | Open the Macro Bank to manage saved macros |
| `:MacroBankSelect [name]` | Load a macro into the default register (interactive picker if no name) |
| `:MacroBankSelect! [name]` | Same as above but shows all scopes |
| `:MacroBankPlay [name]` | Execute a macro directly (interactive picker if no name) |
| `:MacroBankPlay! [name]` | Same as above but shows all scopes |



### Keymaps

You can set up your own keymaps to open the Live Macro Editor or Macro Bank using `vim.keymap.set` or `vim.cmd`.

**Using `vim.keymap.set` (recommended):**

```lua
vim.keymap.set('n', '<leader>mm', function() require('macrobank.editor').open() end, { desc = '[Macrobank]: Edit macros' })
vim.keymap.set('n', '<leader>mb', function() require('macrobank.bank_editor').open() end, { desc = '[MacroBank] Edit saved macros' })
```

**Using `vim.cmd`:**

```lua
vim.keymap.set('n', '<leader>mm', ':MacroBankLive<CR>', { desc = '[Macrobank]: Edit macros' })
vim.keymap.set('n', '<leader>mb', ':MacroBank<CR>', { desc = '[MacroBank] Edit saved macros' })
```

### Live Macro Editor Keymaps

When in the Live Macro Editor (`:MacroBankLive`):

| Key | Action | Description |
|-----|--------|-------------|
| `<C-s>` | Save | Save the register under cursor with edited content |
| `<CR>` | Play | Execute the macro under cursor |
| `D` | Delete | Clear the macro register |
| `@` | Load | Load macro from picker (current context) into register under cursor |
| `` ` `` | Load (All) | Load macro from picker (all scopes) into register under cursor |
| `a-z` | Navigate | Jump directly to that register (e.g., `f` jumps to register f) |
| `<Tab>` | Switch | Toggle between register and saved macro views |
| `<Esc>` | Quit | Close the editor |

### Save Scopes (Live Editor)

When saving macros from the Live Editor:

| Key | Scope | Description |
|-----|-------|-------------|
| `<C-g>` | Global | Save macro under cursor to global macro store |
| `<C-t>` | Filetype | Save macro under cursor scoped to current filetype |
| `<C-f>` | File | Save macro under cursor scoped to current file |
| `<C-d>` | Directory | Save macro under cursor scoped to current directory |
| `<C-c>` | CWD | Save macro under cursor scoped to current working directory |
| `<C-p>` | Project | Save macro under cursor to nearest project macrobank.json file |

### Macro Bank Editor Keymaps

When in the Macro Bank (`:MacroBank`):

| Key | Action | Description |
|-----|--------|-------------|
| `<CR>` | Execute | Run the selected macro |
| `@@` | Load | Load macro into default register |
| `@<reg>` | Load | Load macro into specified register |
| `D` | Delete | Remove macro from bank |
| `<C-s>` | Save | Save macro under cursor with edited content |
| `<C-h>` | History | View/rollback to previous versions |
| `g/` | Search | Search for macros with picker |
| `<Tab>` | Switch | Toggle to Live Macro Editor |
| `<Esc>` | Quit | Close the editor |

### Scope Change (Bank Editor)

Change the scope of the macro under cursor:

| Key | Scope | Description |
|-----|-------|-------------|
| `<C-g>` | Global | Change to global scope |
| `<C-t>` | Filetype | Change to filetype scope |
| `<C-f>` | File | Change to file scope |
| `<C-d>` | Directory | Change to directory scope |
| `<C-c>` | CWD | Change to CWD scope |
| `<C-p>` | Project | Change to project scope |

## 📁 Storage

### Global Storage
Macros are stored globally in `~/.config/nvim/macrobank_store.json` by default.

### Project Storage
The plugin automatically discovers project-local macro files by searching upward from the current file:
- `.macrobank.json`
- `.nvim/macrobank.json`

### Scoped Macros
Macros can be scoped to different contexts:
- **Global**: Available everywhere
- **Filetype**: Only available for specific filetypes (e.g., `lua`, `python`)
- **File**: Only available for specific files
- **Directory**: Available when in a specific directory tree
- **CWD**: Available when the current working directory matches
- **Project**: Available within the current project (saved to nearest macrobank.json file)

## 🎯 Workflow Examples

### Basic Macro Workflow
1. Record a macro: `qa` (record into register 'a')
2. Open Live Editor: `<leader>mm`
3. Navigate quickly: Press `a` to jump directly to register 'a'
4. Edit if needed, then save: `<C-s>` to save changes to register (or `D` to clear)
5. Save to bank: `<C-g>` (save globally) and name it
6. Later, load and use: `:MacroBankSelect my_macro`

### Project-Specific Macros
1. Create `.macrobank.json` in your project root
2. Record and save macros with `<C-p>` (project scope), `<C-f>` (file), or `<C-d>` (directory) scopes
3. Macros will be automatically available when working in the project

### Quick Macro Execution
```vim
" Execute a macro by name
:MacroBankPlay my_useful_macro

" Execute on a range
:1,10MacroBankPlay format_lines

" Interactive selection
:MacroBankPlay
```

## 🔧 Advanced Usage

### Tab Completion
All commands support tab completion for macro names:
```vim
:MacroBankSelect <Tab>  " Shows all available macro names
:MacroBankPlay my_<Tab> " Shows macros starting with "my_"
```

### Range Support
`:MacroBankPlay` supports range execution:
```vim
:5,15MacroBankPlay format_macro  " Apply macro to lines 5-15
:%MacroBankPlay global_fix       " Apply to entire file
```

### Custom Project Paths
Configure custom project store paths:
```lua
require("macrobank").setup({
  project_store_paths = {
    '.config/macros.json',
    'tools/macros.json',
    '.vim/macros.json'
  }
})
```

### Macro History and Versioning
The plugin maintains a history of macro changes, allowing you to:
- View previous versions of a macro with `<C-h>` in the Macro Bank
- Rollback to any previous version
- Track when macros were modified

### Search
Use `g/` in the Macro Bank to open a picker for searching macros by name or content.

### Custom Buffer Mappings
Override default editor keymaps in your configuration:

```lua
require("macrobank").setup({
  live_editor_mappings = {
    save = '<leader>s',       -- change save key from <C-s> to <leader>s  
    delete = false,           -- disable delete key entirely
    play = '<Space>',         -- change play key from <CR> to <Space>
    load = '<leader>@',       -- change load key from @ to <leader>@
  },
  bank_editor_mappings = {
    search = '/',             -- change search key from g/ back to /
    history = false,          -- disable history feature
    load = '<leader>l',       -- change load key from @ to <leader>l
    switch = '<C-Tab>',       -- change switch key from <Tab> to <C-Tab>
  },
})
```

**Mapping Options:**
- Set a new key string to override the default
- Set `false` to disable a mapping entirely
- Leave unspecified to keep default behavior

**Live Editor Action Names:**
- `save` - Save register content (`<C-s>`)
- `play` - Play macro (`<CR>`)
- `delete` - Clear register (`D`)
- `repeat` - Repeat last macro (`.`)
- `load` - Load macro from bank (available only) (`@`)
- `load_all` - Load macro from bank (all scopes) (`` ` ``)
- `save_global`, `save_filetype`, `save_file`, `save_directory`, `save_cwd`, `save_project` - Save with specific scope (`<C-g>`, `<C-t>`, `<C-f>`, `<C-d>`, `<C-c>`, `<C-p>`)
- `switch` - Switch to bank editor (`<Tab>`)
- `close` - Close editor (`<Esc>`)
- `jump_a` through `jump_z` - Jump to specific register (`a`-`z`)

**Bank Editor Action Names:**
- `save` - Save macro content (`<C-s>`)
- `delete` - Delete macro (`D`)
- `play` - Execute macro (`<CR>`)
- `load` - Load into register (`@`)
- `history` - View/rollback history (`<C-h>`)
- `search` - Search macros (`g/`)
- `switch` - Switch to live editor (`<Tab>`)
- `change_scope_global`, `change_scope_filetype`, `change_scope_file`, `change_scope_directory`, `change_scope_cwd`, `change_scope_project` - Change macro scope (`<C-g>`, `<C-t>`, `<C-f>`, `<C-d>`, `<C-c>`, `<C-p>`)
- `close` - Close editor (`<Esc>`)

### Advanced Scope Matching
The plugin intelligently matches macros based on context:
- **Directory scopes** match when you're editing files within that directory tree
- **File scopes** only activate for the specific file
- **Filetype scopes** activate based on the current buffer's filetype
- **CWD scopes** activate when the current working directory matches
- **Project scopes** work anywhere within the project directory

### Context-Aware Commands
The commands behave differently based on whether you use the bang (`!`) modifier:

**Without bang** - Shows only context-applicable macros:
- `:MacroBankSelect macro_name` - Only searches macros that match your current context
- `:MacroBankPlay macro_name` - Only searches macros that match your current context
- Tab completion shows only applicable macro names

**With bang** - Shows all macros regardless of context:
- `:MacroBankSelect! macro_name` - Searches all macros
- `:MacroBankPlay! macro_name` - Searches all macros  
- Tab completion shows all macro names

## 📚 Lua API

The plugin exposes several Lua functions for programmatic access:

### Core Functions

```lua
-- Setup plugin with configuration
require("macrobank").setup({...})

-- Open Live Macro Editor
require("macrobank.editor").open(ctx)

-- Open Macro Bank Editor  
require("macrobank.bank_editor").open(ctx)
```

### UI Functions

```lua
local UI = require("macrobank.ui")

-- Show macro selection picker
UI.select_macro(function(macro)
  if macro then
    print("Selected:", macro.name)
  end
end, ctx, show_all)

-- Show search picker
UI.search_macros(function(macro)
  if macro then
    print("Found:", macro.name)
  end
end, ctx)

-- Input macro name with scope context
UI.input_name("default_name", function(name)
  print("Entered name:", name)
end, scope)

-- Select scope type
UI.input_scope(function(scope)
  print("Selected scope:", scope.type)
end, ctx)
```

### Store Functions

```lua
local Store = require("macrobank.store")

-- Get all macros for context
local macros = Store.all(ctx)

-- Add new macros
Store.add_many({{name="test", keys="itest", scope={type="global"}}}, ctx)

-- Update existing macro
Store.update(macro_id, {name="new_name", keys="inew"}, ctx)

-- Delete macro
Store.delete(macro_id, ctx)

-- Find macro by name and scope
local macro = Store.find_by_name_scope("test", {type="global"}, ctx)

-- Get macro history
local history = Store.history(macro_id, ctx)

-- Get context-aware macro partitions
local active, inactive = Store.partition_by_context(ctx)
```

### Scope Functions

```lua
local S = require("macrobank.scopes")

-- Get current context
local ctx = S.current_context(function() return Store.get_session_id() end)

-- Check if macro scope matches context
local matches = S.matches(macro.scope, ctx)

-- Get default value for scope type
local value = S.default_value_for("filetype", ctx)

-- Get scope icon
local icon = S.icon_only("global", true) -- true = nerd icons

-- Get human readable scope label
local label = S.label(scope, true)
```

### Utility Functions

```lua
local U = require("macrobank.util")

-- Convert termcodes
local keys = U.to_termcodes("\\<Esc>iHello")

-- Make keys readable for display  
local display = U.readable("\\<Esc>iHello") -- "⎋iHello"

-- Parse bank editor line
local parsed = U.parse_bank_line("macro_name  ⎋itest")

-- Create horizontal rule
local hr = U.hr("Title", 80, "=")

-- Show info/warning messages
U.info("Macro saved")
U.warn("No macro found")
```

### Example Usage

```lua
-- Programmatically save current register to bank
local ctx = require("macrobank.scopes").current_context()
local keys = vim.fn.getreg("q")
if keys ~= "" then
  require("macrobank.store").add_many({
    {name="my_macro", keys=keys, scope={type="global"}}
  }, ctx)
end

-- Load a specific macro into register
local Store = require("macrobank.store") 
local macro = Store.find_by_name_scope("my_macro", {type="global"})
if macro then
  vim.fn.setreg("q", macro.keys, "n")
end
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the need for better macro management in Neovim
- Thanks to the Neovim community for their excellent plugin ecosystem
