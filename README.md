# Dotfiles

All of my dotfiles

1. **Neovim**: My config is based on an old version of [Kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim). However, I do use this daily, and it has niceties in terms of NetRw, along with DAP, Compiler and Neorg.
2. **Hyprland**: My current WM. Relies on [Hyprnvidia](https://github.com/rgarber11/small_scripts/tree/master/hyprnvidia) for Optimus, and calls into scripts in the [nwg_panel folder](nwg-panel/executors/keyboard_layout.py). Also uses `nwg-panel`, `nwg-dock-hyprland`, `anyrun`, `hypridle`, `hyprlock`, etc. Beyond that, I think these are some pretty sane defaults.
3. **Nwg-Panel**: Few changes here, aside from executors for keyboard layout, allowing for keyboard shortcuts to change the layout, and icons for numlock and capslock.  
   _Note:_ I have an executor for when CapsLock is _on_, and one for when Numlock is _off_. Sue me.
4. **NWG-Dock-Hyprland**, **Anyrun**: Mostly cosmetic changes to make them _solarized_
5. **Kitty** is my current terminal. I have not changed much, aside from using a solarized theme.
6. **Alacritty** is my backup terminal. All I've done is changed themes.
7. **Zsh**: My `.zshrc` is a mess, and needs updating. Overall, the only thing in here that I'd keep is my comment formatting script for copying into Jupyter Notebooks, and my script that gives me a cowsay fortune, with proper split on English and Russian Fortunes (note: The in-built `fortune -n 30% a -n 70% b` did not work for me.) Hopefully will be editing this down soon. :tm:
8. **Komorebi**: My preferred tiling window manager for Windows. My dislike for gaps is on display here as well. The rest is mostly default config (I might want to change the shortcuts to match Hyprland at some point). `applications.yaml` contains my attempt at managing Mullvad VPN, which at this point is a failure (so not upstream).
