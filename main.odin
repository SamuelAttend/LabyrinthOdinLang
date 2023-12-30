package main

import SDL "vendor:sdl2"
import mu "vendor:microui"
import "core:math"

Program :: struct {
    quit : bool,
    logic : Logic,
    ui : UI
}

initProgram :: proc(program : ^Program) {
    using program

    assert(SDL.Init(SDL.INIT_VIDEO) == 0, SDL.GetErrorString())
    initLogic(&logic)
    initUI(&ui)
}

destroyProgram :: proc(program :^ Program) {
    using program

    destroyUI(&ui)
    destroyLogic(&logic)
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
        handleMenuWindow(&ui, &logic)
        handleFieldWindow(&ui, &logic)
        mu.end(ui.ctx)

        current := SDL.GetTicks()
        if current - start > u32(math.round(f32(1000.0/MAX_FPS))) {
            start = current
        
            startRender(&ui)
            renderField(&ui, &logic)
            renderMenu(&ui)
            finishRender(&ui)
        }
    }
}