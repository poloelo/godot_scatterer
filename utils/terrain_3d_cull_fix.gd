# Copyright © 2025 Cory Petkovsek, Roope Palmroos, and Contributors.
# Culling fix for foliage/tree MultiMeshInstance3D nodes managed by Terrain3DInstancer.
#
# Drop this node anywhere in a scene that contains a Terrain3D node.
# It traverses all MultiMeshInstance3D descendants of Terrain3D and applies
# extra_cull_margin (or a custom_aabb override) so that transparent/alpha leaves
# are not culled before they leave the camera frustum.
#
# Re-apply is triggered automatically when mesh assets change, and can be forced
# by toggling any exported property in the Inspector.
@tool
extends Node
class_name Terrain3DCullFix

## Extra cull margin (metres) added to every MultiMeshInstance3D under Terrain3D.
## Raise this value if foliage (leaves, branches) disappears too early when the
## camera moves away. Has no effect when use_custom_aabb is true.
@export var extra_cull_margin: float = 32.0:
	set(value):
		extra_cull_margin = value
		_apply_to_all()

## When true, replaces the AABB of each MultiMeshInstance3D with custom_aabb
## instead of using extra_cull_margin. Use this when the generated bounds are
## completely wrong (e.g. a flat AABB for a tall tree).
@export var use_custom_aabb: bool = false:
	set(value):
		use_custom_aabb = value
		_apply_to_all()

## Local-space AABB applied to every MultiMeshInstance3D when use_custom_aabb is true.
## The default covers a generous volume centred at the instancer origin.
@export var custom_aabb: AABB = AABB(Vector3(-64.0, -16.0, -64.0), Vector3(128.0, 96.0, 128.0)):
	set(value):
		custom_aabb = value
		if use_custom_aabb:
			_apply_to_all()

var _terrain: Terrain3D = null


func _ready() -> void:
	# Defer so Terrain3D has time to create its MultiMeshInstance3D nodes first.
	_apply_to_all.call_deferred()
	_connect_terrain_signals.call_deferred()


func _exit_tree() -> void:
	if not is_instance_valid(_terrain):
		return
	if _terrain.assets and _terrain.assets.meshes_changed.is_connected(_apply_to_all):
		_terrain.assets.meshes_changed.disconnect(_apply_to_all)
	for sig_name in ["instancer_changed", "instances_changed"]:
		if _terrain.has_signal(sig_name) and Signal(_terrain, sig_name).is_connected(_apply_to_all):
			Signal(_terrain, sig_name).disconnect(_apply_to_all)


# --------------------------------------------------------------------------- #
#  Signal wiring                                                                #
# --------------------------------------------------------------------------- #

func _connect_terrain_signals() -> void:
	_terrain = _find_terrain()
	if not _terrain:
		return

	# Re-apply when mesh assets are added, removed, or swapped.
	if _terrain.assets and \
			not _terrain.assets.meshes_changed.is_connected(_apply_to_all):
		_terrain.assets.meshes_changed.connect(_apply_to_all)

	# Re-apply whenever the instancer rebuilds its nodes (signal name may vary
	# across Terrain3D versions; guard with has_signal).
	for sig_name in ["instancer_changed", "instances_changed"]:
		if _terrain.has_signal(sig_name) and \
				not _terrain.get(sig_name).is_connected(_apply_to_all):
			_terrain.get(sig_name).connect(_apply_to_all)


# --------------------------------------------------------------------------- #
#  Terrain3D discovery                                                          #
# --------------------------------------------------------------------------- #

func _find_terrain() -> Terrain3D:
	# Walk up the scene tree first — covers the common case where this node is
	# placed as a sibling or child of Terrain3D.
	var node: Node = get_parent()
	while node:
		if node is Terrain3D:
			return node as Terrain3D
		node = node.get_parent()

	# Fall back to a full-tree search.
	if get_tree():
		return _search_tree(get_tree().root)
	return null


func _search_tree(p_node: Node) -> Terrain3D:
	if p_node is Terrain3D:
		return p_node as Terrain3D
	for child in p_node.get_children():
		var result: Terrain3D = _search_tree(child)
		if result:
			return result
	return null


# --------------------------------------------------------------------------- #
#  AABB patching                                                                #
# --------------------------------------------------------------------------- #

func _apply_to_all() -> void:
	if not is_instance_valid(_terrain):
		_terrain = _find_terrain()
	if not is_instance_valid(_terrain):
		return
	_patch_descendants(_terrain)


func _patch_descendants(p_node: Node) -> void:
	if p_node is MultiMeshInstance3D:
		_patch_mmi(p_node as MultiMeshInstance3D)
	for child in p_node.get_children():
		_patch_descendants(child)


func _patch_mmi(p_mmi: MultiMeshInstance3D) -> void:
	if use_custom_aabb:
		p_mmi.custom_aabb = custom_aabb
	else:
		p_mmi.extra_cull_margin = extra_cull_margin
