package main

import SDL "vendor:sdl2"
import mu "vendor:microui"
import "core:math"

Direction :: enum {
    North,
    East,
    South,
    West
}

Coords :: [2] i32

DirectionCoords := map [Direction] Coords {
    .North = {0, -1},
    .East = {+1, 0},
    .South = {0, +1},
    .West = {-1, 0},
}
CoordsDirection := map [Coords] Direction {
    {0, -1} = .North,
    {+1, 0} = .East,
    {0, +1} = .South,
    {-1, 0} = .West
}

DirectionSet :: bit_set[Direction; u8]

Path :: [dynamic] Coords

Labyrinth :: struct {
    directions : [dynamic][dynamic] DirectionSet,
    size : Coords
}

Program :: struct {
    quit : bool,
    ui : UI,
    labyrinth : Labyrinth,
    path : Path,
    history : Path,
}

initProgram :: proc(program : ^Program) {
    using program

    assert(SDL.Init(SDL.INIT_VIDEO) == 0, SDL.GetErrorString())
    initUI(&ui)
}

destroyProgram :: proc(program :^ Program) {
    using program

    delete(path)
    delete(history)
    destroyLabyrinth(&labyrinth)
    destroyUI(&ui)
    SDL.Quit()
}

main :: proc() {
    program : Program
    initProgram(&program)
    defer destroyProgram(&program)

    using program

    start := SDL.GetTicks()
    for !quit {
        handleInputEvent(&program)

        mu.begin(ui.ctx)
        handleMenuWindow(&ui, &labyrinth, &path, &history)
        handleFieldWindow(&ui, &labyrinth)
        mu.end(ui.ctx)

        current := SDL.GetTicks()
        if current - start > u32(math.round(f32(1000.0/MAX_FPS))) {
            start = current
        
            startRender(&ui)
            renderLabyrinth(&labyrinth, &ui)
            renderPath(&path, &ui)
            renderCommands(&ui)
            finishRender(&ui)
        }
    }
}