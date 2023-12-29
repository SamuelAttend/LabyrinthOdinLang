package main

import "core:fmt"
import "core:math"
import "core:strings"
import "core:strconv"
import SDL "vendor:sdl2"
import mu "vendor:microui"

WINDOW_WIDTH :: 640
WINDOW_HEIGHT :: 480

MAX_FPS :: 144

DEFAULT_SLIDER_VALUE :: 160
DEFAULT_FIELD_SCALE :: 1.0
FIELD_SCALE_DELTA :: 0.05
TEXTBOX_BUFFER_SIZE :: 128
LOG_SIZE :: 1024
LOG_HEIGHT :: 160
LABEL_WIDTH :: 80

Color :: enum {
    White,
    Red,
    Gray
}

Colors := [Color] mu.Color {
    .White = {255, 255, 255, 255},
    .Red = {255, 0, 0, 255},
    .Gray = {127, 127, 127, 255}
}

Textbox :: struct {
    buffer : [TEXTBOX_BUFFER_SIZE] byte,
    length : int
}

UI :: struct {
    window : ^SDL.Window,
    renderer : ^SDL.Renderer,
    atlas : ^SDL.Texture,
    ctx : ^mu.Context,
    slider : struct {
        value : i32,
        captured : bool
    },
    menu : struct {
        size : struct {
            height, width : Textbox
        },
        file : struct {
            filename : Textbox
        },
        solution : struct {
            start : [2] Textbox,
            finish : [2] Textbox,
            method : Method,
            step : i32
        },
        log : struct {
            data : string,
            updated : bool
        }
    },
    field : struct {
        origin : Coords,
        size : Coords,
        translation : Coords,
        scale : f32
    }
}

MethodName := map [Method] string {
    methodOfWiener = "Wiener",
    methodOfTerry = "Terry"
}

initUI :: proc(ui : ^UI) {
    using ui

    window = SDL.CreateWindow(
        "Labyrinth",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        SDL.WINDOW_RESIZABLE
    )
    assert(window != nil, SDL.GetErrorString())
    SDL.SetWindowMinimumSize(window, WINDOW_WIDTH, WINDOW_HEIGHT)

    renderer = SDL.CreateRenderer(window, -1, SDL.RendererFlags {.SOFTWARE})
    assert(renderer != nil, SDL.GetErrorString())

    atlas = SDL.CreateTexture(renderer, u32(SDL.PixelFormatEnum.RGBA32), .TARGET, mu.DEFAULT_ATLAS_WIDTH, mu.DEFAULT_ATLAS_HEIGHT)
    assert(atlas != nil)
    if err := SDL.SetTextureBlendMode(atlas, .BLEND); err != 0 {
		fmt.eprintln("SDL.SetTextureBlendMode:", err)
	}
    pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT)
	for alpha, i in mu.default_atlas_alpha {
		pixels[i].rgb = 0xff
		pixels[i].a   = alpha
	}
    if err := SDL.UpdateTexture(atlas, nil, raw_data(pixels), 4*mu.DEFAULT_ATLAS_WIDTH); err != 0 {
		fmt.eprintln("SDL.UpdateTexture:", err)
	}
    delete(pixels)

    ctx = new(mu.Context)
    mu.init(ctx)
    ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

    slider = {DEFAULT_SLIDER_VALUE, false}

    menu.solution.method = methodOfWiener

    field = {
        scale = DEFAULT_FIELD_SCALE
    }
}

destroyUI :: proc(ui : ^UI) {
    using ui

    delete(ui.menu.log.data)
    free(ctx)
    SDL.DestroyTexture(atlas)
    SDL.DestroyRenderer(renderer)
    SDL.DestroyWindow(window)
}

generateRoomRect :: proc(coords : ^Coords, ui : ^UI) -> SDL.Rect {
    using ui

    return SDL.Rect {
        field.origin.x + field.translation.x + i32(f32(coords.x * 2) * field.scale),
        field.origin.y + field.translation.y + i32(f32(coords.y * 2) * field.scale),
        i32(math.ceil(field.scale)),
        i32(math.ceil(field.scale))
    }
}

generateCorridorRect :: proc(room : ^SDL.Rect, direction : Direction) -> SDL.Rect {
    switch direction {
        case .North: return SDL.Rect {
                        room.x,
                        room.y - room.h,
                        room.w,
                        room.h
                    }
        case .East: return SDL.Rect {
                        room.x + room.w,
                        room.y,
                        room.w,
                        room.h
                    }
        case .South: return SDL.Rect {
                        room.x,
                        room.y + room.h,
                        room.w,
                        room.h
                    }
        case .West: return SDL.Rect {
                        room.x - room.w,
                        room.y,
                        room.w,
                        room.h
                    }
    }
    unreachable()
}

renderLabyrinth :: proc(labyrinth : ^Labyrinth, ui : ^UI) {
    using labyrinth, ui

    if size.x < 1 || size.y < 1 {
        return
    }

    color := Colors[.White]
    using color
    SDL.SetRenderDrawColor(renderer, r, g, b, a)

    for i in 0..<size.y {
        for j in 0..<size.x {
            room := generateRoomRect(&{j, i}, ui)
            SDL.RenderFillRect(renderer, &room)

            for direction in Direction {
                if direction in directions[i][j] {
                    corridor := generateCorridorRect(&room, direction)
                    SDL.RenderFillRect(renderer, &corridor)
                }
            }
        }
    }
}

renderPath :: proc(path : ^Path, ui : ^UI) {
    using ui

    if len(path) == 0 {
        return
    }
    
    color := Colors[.Red]
    using color
    SDL.SetRenderDrawColor(renderer, r, g, b, a)

    for index in 1..<len(path) {
        previous, current := path[index - 1], path[index]
        direction := CoordsDirection[current - previous]
        room := generateRoomRect(&path[index - 1], ui)
        corridor := generateCorridorRect(&room, direction)
        SDL.RenderFillRect(renderer, &room)
        SDL.RenderFillRect(renderer, &corridor)
    }
    room := generateRoomRect(&path[len(path) - 1], ui)
    SDL.RenderFillRect(renderer, &room)
}

renderTexture :: proc(ui : ^UI, dst, src: ^mu.Rect, color: ^mu.Color) {
    dst.w = src.w
    dst.h = src.h

    SDL.SetTextureAlphaMod(ui.atlas, color.a)
    SDL.SetTextureColorMod(ui.atlas, color.r, color.g, color.b)
    SDL.RenderCopy(ui.renderer, ui.atlas, &SDL.Rect{src.x, src.y, src.w, src.h}, (^SDL.Rect)(dst))
}

renderText :: proc(text : string, ui : ^UI, coords : ^Coords, color : ^mu.Color) {
    dst := mu.Rect{coords.x, coords.y, 0, 0}
    for ch in text do if ch&0xc0 != 0x80 {
        r := min(int(ch), 127)
        src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
        renderTexture(ui, &dst, &src, color)
        dst.x += dst.w
    }
}

renderCommands :: proc(ui : ^UI) {
    cmd : ^mu.Command
    for variant in mu.next_command_iterator(ui.ctx, &cmd) {
        switch cmd in variant {
        case ^mu.Command_Text:
            renderText(cmd.str, ui, &Coords{cmd.pos.x, cmd.pos.y}, &Colors[.White])
        case ^mu.Command_Rect:
            SDL.SetRenderDrawColor(ui.renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
            SDL.RenderFillRect(ui.renderer, (^SDL.Rect)(&cmd.rect))
        case ^mu.Command_Icon:
            src := mu.default_atlas[cmd.id]
            x := cmd.rect.x + (cmd.rect.w - src.w)/2
            y := cmd.rect.y + (cmd.rect.h - src.h)/2
            renderTexture(ui, &mu.Rect{x, y, 0, 0}, &src, &cmd.color)
        case ^mu.Command_Clip:
            SDL.RenderSetClipRect(ui.renderer, (^SDL.Rect)(&cmd.rect))
        case ^mu.Command_Jump:
            unreachable()
        }
    }
}

handleMenuWindow :: proc(ui : ^UI, labyrinth : ^Labyrinth, path, history : ^Path) {
    w, h : i32
    SDL.GetWindowSize(ui.window, &w, &h)

    win := mu.get_container(ui.ctx, "Menu")
    win.rect = mu.Rect {0, 0, ui.slider.value, h}
    if mu.begin_window(ui.ctx, "Menu", mu.Rect {0, 0, ui.slider.value, h}, mu.Options{.NO_CLOSE, .NO_RESIZE, .ALIGN_CENTER}) {
        r := mu.get_current_container(ui.ctx).body

        if .LEFT in ui.ctx.mouse_pressed_bits {
            if ui.ctx.mouse_pos.x >= ui.slider.value - 12 && ui.ctx.mouse_pos.x <= ui.slider.value + 12 {
                ui.slider.captured = true
            }
        }
        else if .LEFT in ui.ctx.mouse_released_bits {
            ui.slider.captured = false
        }

        if ui.slider.captured {
            ui.slider.value = clamp(ui.ctx.mouse_pos.x, DEFAULT_SLIDER_VALUE, w - DEFAULT_SLIDER_VALUE)
        }

        if .ACTIVE in mu.header(ui.ctx, "Generation", mu.Options {.EXPANDED}) {
            mu.layout_row(ui.ctx, {LABEL_WIDTH, -1}, 0)
            mu.label(ui.ctx, "Height:")
            mu.textbox(ui.ctx, ui.menu.size.height.buffer[:], &ui.menu.size.height.length)
            mu.label(ui.ctx, "Width:")
            mu.textbox(ui.ctx, ui.menu.size.width.buffer[:], &ui.menu.size.width.length)

            mu.layout_row(ui.ctx, {-1}, 0)
            if .SUBMIT in mu.button(ui.ctx, "Generate") {
                clearSolution(path, history)

                height := readBufferValue(ui.menu.size.height.buffer[:], ui.menu.size.height.length)
                width := readBufferValue(ui.menu.size.width.buffer[:], ui.menu.size.width.length)

                resizeLabyrinth(labyrinth, height, width)
                if generateLabyrinth(labyrinth) {
                    addLog(ui, "Labyrinth is generated.\n")
                }
                else {
                    addLog(ui, "Labyrinth is cleared.\n")
                }

                adjustFieldScale(ui, labyrinth)
            }
        }

        if .ACTIVE in mu.header(ui.ctx, "File") {
            mu.layout_row(ui.ctx, {LABEL_WIDTH, -1}, 0)
            mu.label(ui.ctx, "Filename:")
            mu.textbox(ui.ctx, ui.menu.file.filename.buffer[:], &ui.menu.file.filename.length)

            mu.layout_row(ui.ctx, {-1}, 0)
            if .SUBMIT in mu.button(ui.ctx, "Load") {
                clearSolution(path, history)

                filename := string(ui.menu.file.filename.buffer[:ui.menu.file.filename.length])
                if loadLabyrinth(filename, labyrinth) {
                    msg := strings.concatenate({"File '", filename, "' is successfully loaded.\n"})
                    defer delete(msg)
                    addLog(ui, msg)
                }
                else {
                    msg := strings.concatenate({"File '", filename, "' is not loaded.\n"})
                    defer delete(msg)
                    addLog(ui, msg)
                }
                adjustFieldScale(ui, labyrinth)
            }
            if .SUBMIT in mu.button(ui.ctx, "Save") {
                filename := string(ui.menu.file.filename.buffer[:ui.menu.file.filename.length])
                if saveLabyrinth(filename, labyrinth) {
                    msg := strings.concatenate({"File '", filename, "' is successfully saved.\n"})
                    defer delete(msg)
                    addLog(ui, msg)
                }
                else {
                    msg := strings.concatenate({"File '", filename, "' is not saved.\n"})
                    defer delete(msg)
                    addLog(ui, msg)
                }
            }
        }

        if .ACTIVE in mu.header(ui.ctx, "Info") {
            mu.layout_row(ui.ctx, {LABEL_WIDTH, -1}, 0)
            mu.label(ui.ctx, "Translation:")
            buffers: [3][32] byte
            translation := strings.concatenate({
                strconv.itoa(buffers.x[:], int(ui.field.translation.x)),
                ", ",
                strconv.itoa(buffers.y[:], int(ui.field.translation.y))})
            defer delete(translation)
            mu.label(ui.ctx, translation)
            mu.label(ui.ctx, "Scale:")
            mu.label(ui.ctx, strconv.ftoa(buffers.z[:], f64(ui.field.scale), 'f', 2, 64)[1:])

            mu.layout_row(ui.ctx, {-1}, 0)
            if .SUBMIT in mu.button(ui.ctx, "Adjust") {
                adjustFieldScale(ui, labyrinth)
            }
        }

        if .ACTIVE in mu.header(ui.ctx, "Solution") {
            mu.layout_row(ui.ctx, {-1}, 0)
            if .ACTIVE in mu.begin_treenode(ui.ctx, "Coords", mu.Options {.CLOSED}) {
                if .ACTIVE in mu.begin_treenode(ui.ctx, "Start", mu.Options {.CLOSED}) {
                    mu.textbox(ui.ctx, ui.menu.solution.start.x.buffer[:], &ui.menu.solution.start.x.length)
                    mu.textbox(ui.ctx, ui.menu.solution.start.y.buffer[:], &ui.menu.solution.start.y.length)
                    mu.end_treenode(ui.ctx)
                }
                if .ACTIVE in mu.begin_treenode(ui.ctx, "Finish", mu.Options {.CLOSED}) {
                    mu.textbox(ui.ctx, ui.menu.solution.finish.x.buffer[:], &ui.menu.solution.finish.x.length)
                    mu.textbox(ui.ctx, ui.menu.solution.finish.y.buffer[:], &ui.menu.solution.finish.y.length)
                    mu.end_treenode(ui.ctx)
                }
                mu.end_treenode(ui.ctx)
            }

            mu.layout_row(ui.ctx, {-1}, 0)
            if .ACTIVE in mu.begin_treenode(ui.ctx, "Method", mu.Options {.CLOSED}) {
                for method in Methods {
                    if .SUBMIT in mu.button(ui.ctx, MethodName[method]) {
                        ui.menu.solution.method = method
                    }
                }
                mu.end_treenode(ui.ctx)
            }

            solve := strings.concatenate({"Solve ( ", MethodName[ui.menu.solution.method], " )"})
            defer delete(solve)
            if .SUBMIT in mu.button(ui.ctx, solve) {
                start := Coords {
                    readBufferValue(ui.menu.solution.start.x.buffer[:], ui.menu.solution.start.x.length),
                    readBufferValue(ui.menu.solution.start.y.buffer[:], ui.menu.solution.start.y.length)
                }
                finish := Coords {
                    readBufferValue(ui.menu.solution.finish.x.buffer[:], ui.menu.solution.finish.x.length),
                    readBufferValue(ui.menu.solution.finish.y.buffer[:], ui.menu.solution.finish.y.length)
                }
                if findSolution(path, history, labyrinth, &start, &finish, ui.menu.solution.method) {
                    addLog(ui, "Solution is found.\n")
                    ui.menu.solution.step = i32(len(history) - 1)
                }
                else {
                    addLog(ui, "Coords are out of bounds.\n")
                }
            }

            if len(history) >= 1 {
                if .ACTIVE in mu.begin_treenode(ui.ctx, "Steps", mu.Options {.CLOSED}) {
                    last := ui.menu.solution.step
                    if .SUBMIT in mu.button(ui.ctx, "Previous") {
                        ui.menu.solution.step -= 1
                    }
                    if .SUBMIT in mu.button(ui.ctx, "Next") {
                        ui.menu.solution.step += 1

                    }
                    
                    if last != ui.menu.solution.step {
                        ui.menu.solution.step = clamp(ui.menu.solution.step, 0, i32(len(history) - 1))
                        findSolution(path, nil, labyrinth, &path[0], &history[ui.menu.solution.step], ui.menu.solution.method)
                    }
                    mu.end_treenode(ui.ctx)
                }
            }
        }

        if .ACTIVE in mu.header(ui.ctx, "Log") {
            mu.layout_row(ui.ctx, {-1}, LOG_HEIGHT)
            mu.begin_panel(ui.ctx, "Logbox")
            mu.layout_row(ui.ctx, {-1}, -1)
            mu.text(ui.ctx, ui.menu.log.data)
            mu.end_panel(ui.ctx)

            mu.layout_row(ui.ctx, {-1}, 0)
            if .SUBMIT in mu.button(ui.ctx, "Clear") {
                clearLog(ui)
            }
        }

        if ui.menu.log.updated {
            logbox := mu.get_container(ui.ctx, "Logbox")
            logbox.scroll.y = logbox.content_size.y
            ui.menu.log.updated = false
        }

        mu.end_window(ui.ctx)
    }
}

handleFieldWindow :: proc(ui : ^UI, labyrinth : ^Labyrinth) {
    w, h : i32
    SDL.GetWindowSize(ui.window, &w, &h)

    win := mu.get_container(ui.ctx, "Field")
    win.rect = mu.Rect {ui.slider.value, 0, w - ui.slider.value, h}
    if mu.begin_window(ui.ctx, "Field", mu.Rect {ui.slider.value, 0, w - ui.slider.value, h}, mu.Options{.NO_CLOSE, .NO_RESIZE, .NO_FRAME, .ALIGN_CENTER}) {
        container := mu.get_current_container(ui.ctx).body

        ui.field.origin = {
            container.x,
            container.y
        }
        ui.field.size = {
            container.w,
            container.h
        }

        if checkCoordsInBounds(
            &Coords {ui.ctx.mouse_pos.x, ui.ctx.mouse_pos.y},
            &Coords {ui.field.origin.x, ui.field.origin.y},
            &Coords {ui.field.origin.x + ui.field.size.x, ui.field.origin.y + ui.field.size.y}
            ) {
            mapped := Coords {
                ui.ctx.mouse_pos.x - ui.field.translation.x - ui.field.origin.x,
                ui.ctx.mouse_pos.y - ui.field.translation.y - ui.field.origin.y
            }
        
            scroll := ui.ctx.scroll_delta.y
            if scroll < 0 {
                ui.field.scale *= f32(1.0 + FIELD_SCALE_DELTA)
                ui.field.translation += {
                    i32(math.round(-FIELD_SCALE_DELTA * f32(mapped.x))),
                    i32(math.round(-FIELD_SCALE_DELTA * f32(mapped.y)))
                }
            }
            else if scroll > 0 {
                ui.field.scale *= f32(1.0 - FIELD_SCALE_DELTA)
                ui.field.translation += {
                    i32(math.round(FIELD_SCALE_DELTA * f32(mapped.x))),
                    i32(math.round(FIELD_SCALE_DELTA * f32(mapped.y)))
                }
            }
        }

        if .MIDDLE in ui.ctx.mouse_down_bits {
            ui.field.translation.x += ui.ctx.mouse_delta.x
            ui.field.translation.y += ui.ctx.mouse_delta.y
        }

        if .RIGHT in ui.ctx.mouse_down_bits {
            adjustFieldScale(ui, labyrinth)
        }

        mu.end_window(ui.ctx)
    }
}

adjustFieldScale :: proc(ui : ^UI, labyrinth : ^Labyrinth) {
    using ui

    if labyrinth.size.x < 1 || labyrinth.size.y < 1 {
        field.translation = {0, 0}
        field.scale = DEFAULT_FIELD_SCALE
        return
    }
    field.scale = f32(min(field.size.x, field.size.y)) / (max(f32(labyrinth.size.x), f32(labyrinth.size.y)) * 2)
    field.translation.x = i32(math.ceil(f32(field.size.x / 2) - (f32(labyrinth.size.x) - f32(0.5)) * field.scale))
    field.translation.y = i32(math.ceil(f32(field.size.y / 2) - (f32(labyrinth.size.y) - f32(0.5)) * field.scale))
}

startRender :: proc(ui : ^UI) {
    color := Colors[.Gray]
    using color
    SDL.SetRenderDrawColor(ui.renderer, r, g, b, a)
    SDL.RenderClear(ui.renderer)
}

finishRender :: proc(ui :^UI) {
    SDL.RenderPresent(ui.renderer)
}

addLog :: proc(ui : ^UI, msg : string) {
    if len(ui.menu.log.data) + len(msg) >= LOG_SIZE {
        clearLog(ui)
    }
    data := strings.concatenate({ui.menu.log.data, msg})
    delete(ui.menu.log.data)
    ui.menu.log.data = data
    ui.menu.log.updated = true
}

clearLog :: proc(ui : ^UI) {
    delete(ui.menu.log.data)
    ui.menu.log.data = ""
}