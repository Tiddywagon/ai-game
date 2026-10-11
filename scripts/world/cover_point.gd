class_name CoverPoint
extends RefCounted
## A spot next to a CoverBox where someone can take cover (DESIGN.md §13.3). Made by CoverSystem.

var box: CoverBox
## Which side of the box (see CoverBox.get_face()).
var face := 0
## Where the actor stands: on the ground, next to the cover.
var position := Vector3.ZERO
## Points away from the cover, toward the actor.
var normal := Vector3.ZERO
## Runs along the cover's side.
var tangent := Vector3.ZERO
## Low cover: crouch behind it and peek over. Tall cover: lean against it and peek around an end.
var is_low := false
## False when peeking is impossible here: something blocks the view, or no end is close enough.
var can_peek := false
## Tall cover: the sideways step that leans out past the end. Zero for low cover.
var peek_offset := Vector3.ZERO
var material := CoverBox.CoverMaterial.CONCRETE
