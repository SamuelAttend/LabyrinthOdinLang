package main

import "core:os"
import "core:fmt"
import "core:strconv"
import SDL "vendor:sdl2"
import mu "vendor:microui"

HEADER_SIZE :: 8

handleInputEvent :: proc(program : ^Program) {
    using program

    event : SDL.Event
    if SDL.PollEvent(&event) {
        #partial switch event.type {
        case .QUIT: quit = true
        case .MOUSEMOTION: mu.input_mouse_move(ui.ctx, event.motion.x, event.motion.y)
        case .MOUSEWHEEL: mu.input_scroll(ui.ctx, event.wheel.x * 30, event.wheel.y * -30)
        case .TEXTINPUT: mu.input_text(ui.ctx, string(cstring(&event.text.text[0])))
        case .MOUSEBUTTONDOWN, .MOUSEBUTTONUP:
            fn := mu.input_mouse_down if event.type == .MOUSEBUTTONDOWN else mu.input_mouse_up
            switch event.button.button {
            case SDL.BUTTON_LEFT: fn(ui.ctx, event.button.x, event.button.y, .LEFT)
            case SDL.BUTTON_MIDDLE: fn(ui.ctx, event.button.x, event.button.y, .MIDDLE)
            case SDL.BUTTON_RIGHT: fn(ui.ctx, event.button.x, event.button.y, .RIGHT)
            }
        case .KEYDOWN, .KEYUP:
            fn := mu.input_key_down if event.type == .KEYDOWN else mu.input_key_up
            #partial switch event.key.keysym.sym {
            case .LSHIFT:    fn(ui.ctx, .SHIFT)
            case .RSHIFT:    fn(ui.ctx, .SHIFT)
            case .LCTRL:     fn(ui.ctx, .CTRL)
            case .RCTRL:     fn(ui.ctx, .CTRL)
            case .LALT:      fn(ui.ctx, .ALT)
            case .RALT:      fn(ui.ctx, .ALT)
            case .RETURN:    fn(ui.ctx, .RETURN)
            case .KP_ENTER:  fn(ui.ctx, .RETURN)
            case .BACKSPACE: fn(ui.ctx, .BACKSPACE)
            }
        }
    }
}

loadLabyrinth :: proc(filename : string, labyrinth : ^Labyrinth) -> bool {
    data, ok := os.read_entire_file(filename)
    if !ok {
        fmt.eprintln("Error reading file")
        return false
    }
    defer delete(data)

    height := i32((u32(data[3]) << 24) | (u32(data[2]) << 16) | (u32(data[1]) << 8) | u32(data[0]))
    width := i32((u32(data[7]) << 24) | (u32(data[6]) << 16) | (u32(data[5]) << 8) | u32(data[4]))

    resizeLabyrinth(labyrinth, height, width)
    for i in 0..<height {
        for j in 0..<width {
            labyrinth.directions[i][j] = transmute(DirectionSet)(data[HEADER_SIZE + i * width + j])
        }
    }
    return true
}

saveLabyrinth :: proc(filename : string, labyrinth : ^Labyrinth) -> bool {
    handle, err := os.open(filename, os.O_RDWR | os.O_CREATE | os.O_TRUNC)
    if err != 0 {
        fmt.eprintln("Error saving file: ", err)
        return false
    }
    defer os.close(handle)

    heightBytes := transmute([4] u8)(labyrinth.size.y)
    widthBytes := transmute([4] u8)(labyrinth.size.x)

    os.write(handle, heightBytes[:])
    os.write(handle, widthBytes[:])
    for i in 0..<labyrinth.size.y {
        os.write(handle, transmute([] u8)(labyrinth.directions[i][:]))
    }
    return true
}

readBufferValue :: proc(buffer : [] u8, length : int) -> i32 {
    return i32(strconv.atoi(string(buffer[:length])))
}