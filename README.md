# macrobank.nvim

A powerful Neovim plugin for managing, editing, and organizing macros with persistent storage across sessions and projects.

## ✨ Features

- 📝 **Live Macro Editor**: Edit macros in real-time with a dedicated interface
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

  mappings = {
    open_live   = '<leader>mm',   -- open Live Macro Editor (registers)
    open_bank   = '<leader>mb',   -- open Macro Bank (saved macros)
  },
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
  
  -- Custom keymaps
  mappings = {
    open_live = '<leader>ml',
    open_bank = '<leader>ms',
  },
  
  -- Disable nerd font icons
  nerd_icons = false,
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

### Default Keymaps

| Keymap | Command | Description |
|--------|---------|-------------|
| `<leader>mm` | `:MacroBankLive` | Open Live Macro Editor |
| `<leader>mb` | `:MacroBank` | Open Macro Bank |

### Live Macro Editor Keymaps

When in the Live Macro Editor (`:MacroBankLive`):

| Key | Action | Description |
|-----|--------|-------------|
| `<C-s>` | Save | Save the register under cursor with edited content |
| `<CR>` | Play | Execute the macro under cursor |
| `dd` | Delete | Clear the macro register |
| `@` | Load | Load macro from picker (current context) into register under cursor |
| `` ` `` | Load All | Load macro from picker (all scopes) into register under cursor |
| `.` | Repeat | Repeat last executed macro |
| `<Tab>` | Switch | Toggle between register and saved macro views |
| `q` | Quit | Close the editor |

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
| `dd` | Delete | Remove macro from bank |
| `<C-s>` | Save | Save macro under cursor with edited content |
| `<C-h>` | History | View/rollback to previous versions |
| `/` | Search | Fuzzy search for macros |
| `M` | Keymap | Generate keymap code for the macro |
| `X` | Export | Export macro as Lua snippet |
| `.` | Repeat | Repeat last executed macro |
| `<Tab>` | Switch | Toggle to Live Macro Editor |
| `q` | Quit | Close the editor |

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
3. Save the macro: `<C-g>` (save globally)
4. Later, load and use: `:MacroBankSelect my_macro`

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

### Fuzzy Search
Use `/` in the Macro Bank to search for macros by name or content using fuzzy matching.

### Export and Code Generation
- `X` - Export macro as a Lua snippet for use in configuration files
- `M` - Generate Vim keymap code to bind the macro to a key combination

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

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the need for better macro management in Neovim
- Thanks to the Neovim community for their excellent plugin ecosystem
