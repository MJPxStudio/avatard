class_name ServerProjectile
extends RefCounted

# ============================================================
# SERVER PROJECTILE — generic non-piercing projectile
#
# Usage (in server_main.gd):
#
#   var proj       = ServerProjectile.new()
#   proj.peer_id   = peer_id
#   proj.pos       = caster_pos
#   proj.dir       = aim_dir.normalized()
#   proj.dmg       = 22
#   proj.range     = 320.0
#   proj.speed     = 500.0
#   proj.hit_radius = 40.0
#   proj.target_id = "wolf_0"   # optional — empty = positional only
#   proj.zone      = sp.zone
#   proj.visual_id = "air_palm" # sent via ability_visual RPC on impact
#   proj.on_stop   = func(hit_pos: Vector2): <send stop RPC>
#   _projectiles.append(proj)
#
# Then in _process: _step_projectiles(delta)
# ============================================================

var peer_id:    int     = 0
var pos:        Vector2 = Vector2.ZERO
var dir:        Vector2 = Vector2.RIGHT
var dmg:        int     = 0
var range:      float   = 320.0
var speed:      float   = 500.0
var hit_radius: float   = 40.0
var target_id:  String  = ""   # empty = positional sweep only
var zone:       String  = ""
var visual_id:  String  = ""   # ability_visual id sent to target on impact
var travelled:  float   = 0.0
var done:       bool    = false

# Called with (hit_pos: Vector2) when the projectile hits something.
# Use this to send your ability-specific stop RPC to clients.
var on_stop: Callable = Callable()
