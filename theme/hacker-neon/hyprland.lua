-- Hacker Neon: a Matrix green to cyberpunk cyan border and a green glow on the
-- focused window, dim green on the rest, sharp corners and tight gaps.
local active_border_color = { colors = { "rgba(00ff9cee)", "rgba(00e5ffee)" }, angle = 45 }
local inactive_border_color = "rgba(1d5442aa)"

hl.config({
  general = {
    border_size = 2,
    gaps_in = 3,
    gaps_out = 6,
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    rounding = 0,

    -- A wide, soft shadow in the accent color reads as a glow.
    shadow = {
      enabled = true,
      range = 12,
      render_power = 3,
      color = "rgba(00ff9c55)",
      color_inactive = "rgba(00ff9c12)",
    },
  },
})

-- Neon Dock: frosted glass behind the dock. Blur is on for the dock's layer
-- only (its see-through capsule), and every window keeps the look it has with
-- blur off. Settings match Omarchy's own glass (default/hypr/glass.lua).
hl.config({
  decoration = {
    blur = {
      enabled = true,
      size = 4,
      passes = 2,
      new_optimizations = true,
      xray = false,
      contrast = 1.0,
      brightness = 0.75,
      noise = 0.01,
      vibrancy = 0.35,
      vibrancy_darkness = 0.35,
      popups = false,
      special = false,
    },
  },
})

hl.layer_rule({
  match = { namespace = "^omarchy-dock$" },
  blur = true,
  ignore_alpha = 0.3,
})

-- Neon HUD: the same frosted glass behind the desktop panels.
hl.layer_rule({
  match = { namespace = "^neon-hud$" },
  blur = true,
  ignore_alpha = 0.3,
})

hl.window_rule({
  match = { class = ".*" },
  no_blur = true,
})
