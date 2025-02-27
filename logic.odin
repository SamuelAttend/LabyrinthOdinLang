#+feature dynamic-literals
package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:slice"

BYTE_SIZE :: 8

Direction :: enum {
	North,
	East,
	South,
	West,
}

Coords :: [2]i32

@(rodata)
DirectionCoords := [Direction]Coords {
	.North = {0, -1},
	.East  = {+1, 0},
	.South = {0, +1},
	.West  = {-1, 0},
}
CoordsDirection := map[Coords]Direction {
	{0, -1} = .North,
	{+1, 0} = .East,
	{0, +1} = .South,
	{-1, 0} = .West,
}

DirectionSet :: bit_set[Direction;u8]

Path :: [dynamic]Coords

Labyrinth :: struct {
	directions: [dynamic][dynamic]DirectionSet,
	size:       Coords,
}

BitMask :: [dynamic]bit_set[0 ..< BYTE_SIZE;u8]

METHOD :: enum u8 {
	WIENER,
	TERRY,
}

MethodProc :: proc(_: ^Path, _: i32, _: ^Labyrinth, _: ^Coords, _: ^Coords) -> i32

MethodProcs := [METHOD]MethodProc {
	.WIENER = methodOfWiener,
	.TERRY  = methodOfTerry,
}
@(rodata)
MethodNames := [METHOD]string {
	.WIENER = "Wiener",
	.TERRY  = "Terry",
}

Logic :: struct {
	labyrinth: Labyrinth,
	path:      Path,
	coords:    struct {
		start, finish: Coords,
	},
	method:    METHOD,
	step:      i32,
	maxstep:   i32,
}

initLogic :: proc(logic: ^Logic) {
	using logic

	method = .WIENER
}

destroyLogic :: proc(logic: ^Logic) {
	using logic

	delete(path)
	destroyLabyrinth(&labyrinth)
}

generateIntValue :: proc(limit: i32) -> i32 {
	return rand.int31_max(i32(limit))
}

genetateCoords :: proc(limits: ^Coords) -> Coords {
	return Coords{generateIntValue(limits.x), generateIntValue(limits.y)}
}

generateDirection :: proc() -> Direction {
	return Direction(generateIntValue(4))
}

inverseDirection :: proc(direction: Direction) -> Direction {
	return Direction((i32(direction) + 2) % 4)
}

checkCoordsInRange :: proc(coords: ^Coords, minimals: ^Coords, limits: ^Coords) -> bool {
	return(
		!(coords.x < minimals.x ||
			coords.x >= limits.x ||
			coords.y < minimals.y ||
			coords.y >= limits.y) \
	)
}

checkCoordsInLimits :: proc(coords: ^Coords, limits: ^Coords) -> bool {
	return !(coords.x < 0 || coords.x >= limits.x || coords.y < 0 || coords.y >= limits.y)
}

checkCoordsInBounds :: proc {
	checkCoordsInLimits,
	checkCoordsInRange,
}

generatePath :: proc(path: ^Path, limits: ^Coords, taken: ^BitMask) {
	current := genetateCoords(limits)
	for getBitMaskValue(taken, &current, limits) {
		current = genetateCoords(limits)
	}
	append(path, current)

	for !getBitMaskValue(taken, &current, limits) {
		next := current + DirectionCoords[generateDirection()]
		for !checkCoordsInBounds(&next, limits) {
			next = current + DirectionCoords[generateDirection()]
		}

		for coords, index in path {
			if next == coords {
				resize(path, index)
			}
		}
		current = next
		append(path, current)
	}
}

setBitMaskValue :: proc(mask: ^BitMask, coords: ^Coords, limits: ^Coords, value: bool) {
	index := coords.y * limits.x + coords.x
	if value {
		mask[index / BYTE_SIZE] += {int(index % BYTE_SIZE)}
	} else {
		mask[index / BYTE_SIZE] -= {int(index % BYTE_SIZE)}
	}
}

getBitMaskValue :: proc(mask: ^BitMask, coords: ^Coords, limits: ^Coords) -> bool {
	index := coords.y * limits.x + coords.x
	return int(index % BYTE_SIZE) in mask[index / BYTE_SIZE]
}

generateLabyrinth :: proc(labyrinth: ^Labyrinth) -> bool {
	using labyrinth

	if size.x < 1 || size.y < 1 {
		return false
	}

	taken := make(BitMask, int(math.ceil(f32(size.y * size.x) / BYTE_SIZE)))
	defer delete(taken)

	origin := genetateCoords(&size)
	setBitMaskValue(&taken, &origin, &size, true)

	counter := size.x * size.y - 1
	for counter != 0 {
		path: Path
		defer delete(path)
		generatePath(&path, &size, &taken)

		counter -= i32(len(path) - 1)
		for index in 1 ..< len(path) {
			previous, current := path[index - 1], path[index]
			direction := CoordsDirection[current - previous]
			setBitMaskValue(&taken, &previous, &size, true)
			directions[previous.y][previous.x] += {direction}
			directions[current.y][current.x] += {inverseDirection(direction)}
		}
	}
	return true
}

initLabyrinth :: proc(labyrinth: ^Labyrinth, height, width: i32) {
	using labyrinth

	size = Coords{width, height}

	directions = make([dynamic][dynamic]DirectionSet, int(size.y))
	for i in 0 ..< size.y {
		directions[i] = make([dynamic]DirectionSet, int(size.x))
	}
}

destroyLabyrinth :: proc(labyrinth: ^Labyrinth) {
	using labyrinth

	for i in 0 ..< size.y {
		delete(directions[i])
	}
	delete(directions)
}

resizeLabyrinth :: proc(labyrinth: ^Labyrinth, height, width: i32) {
	using labyrinth

	height := max(height, 0)
	width := max(width, 0)

	destroyLabyrinth(labyrinth)
	initLabyrinth(labyrinth, height, width)
}

findPath :: proc(
	path: ^Path,
	step: i32,
	labyrinth: ^Labyrinth,
	start, finish: ^Coords,
	method: MethodProc,
) -> i32 {
	using labyrinth

	clear(path)

	if (!checkCoordsInBounds(start, &size) || !checkCoordsInBounds(finish, &size)) {
		return 0
	}

	if start^ == finish^ {
		append(path, start^)
		return 0
	}

	return method(path, step, labyrinth, start, finish)
}

methodOfWiener :: proc(
	path: ^Path,
	step: i32,
	labyrinth: ^Labyrinth,
	start: ^Coords,
	finish: ^Coords,
) -> i32 {
	using labyrinth

	visited := make(BitMask, int(math.ceil(f32(size.y * size.x) / BYTE_SIZE)))
	defer delete(visited)

	current := start^
	append(path, current)
	setBitMaskValue(&visited, &current, &size, true)

	i: i32
	for i != step {
		i += 1
		proceedable := false
		for direction in Direction {
			if direction in directions[current.y][current.x] {
				next := current + DirectionCoords[direction]
				if !getBitMaskValue(&visited, &next, &size) {
					proceedable = true
					current = next
					append(path, current)
					setBitMaskValue(&visited, &next, &size, true)
					if current == finish^ {
						return i
					}
					break
				}
			}
		}
		if !proceedable {
			pop(path)
			current = path[len(path) - 1]
		}
	}
	return i
}

methodOfTerry :: proc(
	path: ^Path,
	step: i32,
	labyrinth: ^Labyrinth,
	start: ^Coords,
	finish: ^Coords,
) -> i32 {
	using labyrinth

	traveled := make([][]DirectionSet, size.y)
	for i in 0 ..< size.y {
		traveled[i] = make([]DirectionSet, size.x)
	}
	defer {
		for i in 0 ..< size.y {
			delete(traveled[i])
		}
		delete(traveled)
	}

	current := start^
	append(path, current)

	i: i32
	for i != step {
		i += 1
		proceedable := false
		for direction in Direction {
			if direction in directions[current.y][current.x] {
				if direction not_in traveled[current.y][current.x] {
					next := current + DirectionCoords[direction]
					if inverseDirection(direction) not_in traveled[next.y][next.x] {
						proceedable = true
						traveled[current.y][current.x] += {direction}
						current = next
						append(path, current)
						if current == finish^ {
							return i
						}
						break
					}
				}
			}
		}
		if !proceedable {
			removed := pop(path)
			current = path[len(path) - 1]

			direction := CoordsDirection[current - removed]
			traveled[removed.y][removed.x] += {direction}
		}
	}
	return i
}
