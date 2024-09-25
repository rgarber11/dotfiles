# Dotfiles

All of my dotfiles

1. **Neovim**: My config is based on an old version of [Kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim). However, it has been thoroughly changed, and now doesn't really resemble its ancestor. Quite maximalist, so is very batteries included.
2. **Hyprland**: My current WM. Relies on [Hyprnvidia](https://github.com/rgarber11/small_scripts/tree/master/hyprnvidia) for Optimus, and calls into scripts in the [nwg_panel folder](nwg-panel/executors/keyboard_layout.py). Also uses `nwg-panel`, `nwg-dock-hyprland`, `anyrun`, `hypridle`, `hyprlock`, etc. Beyond that, I think these are some pretty sane defaults.
3. **Nwg-Panel**: Custom executors for switching Hyprland Keyboard Layouts, night-light and icons for numlock and capslock. Solarized Tray menu, but not the panel itself, since it looks wrong then to me. Requires [`gammastep`](https://gitlab.com/chinstrap/gammastep) for night color.  
   _Note:_ I have an executor for when CapsLock is _on_, and one for when Numlock is _off_. Sue me.
4. **NWG-Dock-Hyprland**, **Anyrun**: Mostly cosmetic changes to make them _solarized_
5. **Kitty** is my current terminal. I have not changed much, aside from using a solarized theme.
6. **Alacritty** is my backup terminal. All I've done is changed themes.
7. **Zsh**: My `.zshrc` is a mess, and needs updating. Overall, the only thing in here that I'd keep is my comment formatting script for copying into Jupyter Notebooks, and my script that gives me a cowsay fortune, with proper split on English and Russian Fortunes (note: The in-built `fortune -n 30% a -n 70% b` did not work for me.) Hopefully will be editing this down soon. :tm:
8. **Komorebi**: My preferred tiling window manager for Windows. My dislike for gaps is on display here as well. The rest is mostly default config (I might want to change the shortcuts to match Hyprland at some point). `applications.yaml` contains my attempt at managing Mullvad VPN, which at this point is a failure (so not upstream).
9. **SwayNC**: Simple Notification Center and Daemon. I did my best to solarize it.
