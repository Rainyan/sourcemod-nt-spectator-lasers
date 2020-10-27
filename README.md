# sourcemod-nt-spectator-lasers
SourceMod plugin for Neotokyo: Draw laser lines for spectators to visualize which direction each player is aiming towards.

![Image of the plugin's visual effect](https://github.com/Rainyan/sourcemod-nt-spectator-lasers/raw/main/promo/example.png)

## Compile requirements
- SourceMod 1.7 or newer (tested on 1.10 branch)
- SourceMod [Neotokyo include](https://github.com/softashell/sourcemod-nt-include)

## ConVars
- *sm_speclaser_offset_x/y/z* - Relative laser start position offset from the center of player's eye position.
- *sm_speclaser_beam_width* - Width of the laser.
- *sm_speclaser_color_r/g/b/a* - RGBA color of the laser. The color is also affected by the used texture, so it's not a pure RGBA color.
