class_name BoxFootprint
extends RefCounted
## Flat (x, z) geometry of a box that only turns around Y, shared by the vision occluders.


## The four ground corners of a box of `size` centred at `transform`, in order around it.
static func corners(transform: Transform3D, size: Vector3) -> PackedVector2Array:
	var result := PackedVector2Array()
	for local: Vector3 in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]:
		var point := transform * (local * size / 2.0)
		result.append(Vector2(point.x, point.z))
	return result


## Thickness of the box behind its face with outward normal `normal`.
static func depth(basis: Basis, size: Vector3, normal: Vector3) -> float:
	var local := basis.orthonormalized().inverse() * normal
	return absf(local.x) * size.x + absf(local.z) * size.z
