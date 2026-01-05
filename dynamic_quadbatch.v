module main

import sokol.sapp
import sokol.gfx
import rand

#flag -I @VMODROOT/.
#include "simple_shader.h"

fn C.simple_shader_desc(gfx.Backend) &gfx.ShaderDesc

struct Vertex_t {
	// Position
	x f32
	y f32
	z f32
	// Color
	r f32
	g f32
	b f32
	a f32
}

fn main() {
	mut app := &App{
		width: 800
		height: 400
		
	}
	app.run()
}

struct App {
	pass_action gfx.Pass
mut:
	width           int
	height          int
	shader_pipeline gfx.Pipeline
	bind            gfx.Bindings
	texture     gfx.Image
	frame_count int
	vertex_array []Vertex_t
	index_array []u32 // u32 used for large index values
	index_count u32
	max_quads int = 10000 // Max number of quads that can be rendered
	quad_count int
}

fn (mut a App) run() {
	title := 'V Dynamic Quad Shader Example'
	desc := sapp.Desc{
		width: a.width
		height: a.height
		user_data: a
		init_userdata_cb: init
		frame_userdata_cb: frame
		window_title: title.str
		event_userdata_cb: input
		html5_canvas_name: title.str
		cleanup_userdata_cb: cleanup
	}
	sapp.run(&desc)
}

fn input(ev &sapp.Event, mut app App) {
	if app.quad_count == app.max_quads { return }
	randx := rand.f32_in_range(-1, 1) or {0}
	randy := rand.f32_in_range(-1, 1) or {0}

	randr := rand.f32_in_range(0, 1) or {0.5}
	randg := rand.f32_in_range(0, 1) or {0.5}
	randb := rand.f32_in_range(0, 1) or {0.5}
	randa := rand.f32_in_range(0, 1) or {0.5}

	// Adding a new quad at runtime

	if ev.key_code == .space {
		app.add_quad(randx, randy, 0.25,randr, randg, randb, randa)
	}
}

fn (mut app App) add_quad(x f32, y f32, size f32, r f32, g f32, b f32, a f32) {

	//vertices[] = {
	//    // Positions     // Colors
	//    0.0,  0.5, 0.5,     1.0, 0.0, 0.0, 1.0,
	//    0.5, -0.5, 0.5,     0.0, 1.0, 0.0, 1.0,
	//   -0.5, -0.5, 0.5,     0.0, 0.0, 1.0, 1.0
	// }

	vertices := [
			Vertex_t{x-size, y+size, size, r, g, b, a},
			Vertex_t{x+size, y+size, size, r, g, b, a},
			Vertex_t{x+size, y-size, size, r, g, b, a},
			Vertex_t{x-size, y-size, size, r, g, b, a},
	]

	// indices := [ // Quad Indices Formula: i, i+1, i+2, i, i+2, i+3
	// 	u16(0) 1, 2,  0, 2, 3
	// 		4, 5, 6,  4, 6, 7
	// 		8, 9, 10, 8, 10, 11
	// ]
	i := app.index_count
	app.index_array << [i, i+1, i+2, i, i+2, i+3]
	app.index_count += 4
	app.vertex_array << vertices
	app.quad_count += 1
	println("Quad Count: ${app.quad_count}")
}

fn init(user_data voidptr) {
	mut app := unsafe {&App(user_data)}
	mut desc := sapp.create_desc()

	gfx.setup(&desc)

	// Add quads to vertex/index array
	//app.add_quad(0,0, 0.25, 1, 1, 1, 1)

	// vertex buffer

	mut vertex_buffer_desc := gfx.BufferDesc{
		label: c'quad-vertices'
	}
	unsafe { vmemset(&vertex_buffer_desc, 0, int(sizeof(vertex_buffer_desc))) }

	vertex_buffer_desc.size = usize(app.max_quads*4 * int(sizeof(Vertex_t)))
	println(vertex_buffer_desc.size)

	// --- Buffer usage of .dynamic and .stream doesn't allow preallocation
	// vertex_buffer_desc.data = gfx.Range{
	// 	ptr: app.vertex_array.data
	// 	size: vertex_buffer_desc.size
	// }

	vertex_buffer_desc.usage = .stream
	app.bind.vertex_buffers[0] = gfx.make_buffer(&vertex_buffer_desc)

	// index buffer

	mut index_buffer_desc := gfx.BufferDesc{
		label: c'quad-indices'
	}
	unsafe { vmemset(&index_buffer_desc, 0, int(sizeof(index_buffer_desc))) }
	index_buffer_desc.size = usize(app.max_quads*6 * int(sizeof(u32)))
	// index_buffer_desc.data = gfx.Range{
	// 	ptr: app.index_array.data
	// 	size: usize(app.index_array.len * int(sizeof(u16)))
	// }
	index_buffer_desc.@type = .indexbuffer
	index_buffer_desc.usage = .stream
	ibuf := gfx.make_buffer(&index_buffer_desc)

	// shader

	shader := gfx.make_shader(C.simple_shader_desc(gfx.query_backend()))

	// shader pipeline

	mut pipeline_desc := gfx.PipelineDesc{}
	unsafe { vmemset(&pipeline_desc, 0, int(sizeof(pipeline_desc))) }

	// Populate the essential struct fields
	pipeline_desc.shader = shader

	pipeline_desc.layout.attrs[C.ATTR_vs_position].format = .float3 // f32
	pipeline_desc.layout.attrs[C.ATTR_vs_color0].format = .float4 // f32
	pipeline_desc.label = c'quad-pipeline'
	pipeline_desc.index_type = .uint32

	app.bind.index_buffer = ibuf

	app.shader_pipeline = gfx.make_pipeline(&pipeline_desc)

}

fn cleanup(user_data voidptr) {
	gfx.shutdown()
}

fn frame(user_data voidptr) {
	mut app := unsafe { &App(user_data) }

	// NOTE: This is meant to stop the drawing procedures if there's no vertex/index data, even though it does stop drawing, it
	// doesn't draw after the vertex arrays are repopulated after being cleared.

	// if app.vertex_array.len == 0 { return }

	// NOTE: This was to test clearing the vertex/index array to see how Sokol handles updating
	// the buffer with empty array data. This results in a Sokol runtime error. So there MUST be at least
	// one vertex entry in the vertex array at all times. :'( EDIT: The issue was calling `update_buffer` when there's
	// no data in either the index or vertex buffer. (I'm a moron. Lol.) Forgot to ommit via if statement the update_buffer
	// call if there's no data in the buffer. xD 

	app.frame_count += 1
	// if app.frame_count > 60*5 {
	// 	app.vertex_array.clear()
	// 	app.index_array.clear()
	// }
	//gfx.beg
	mut pass_action := gfx.PassAction{}
	pass_action.colors[0] = gfx.ColorAttachmentAction{
		load_action: .clear
		clear_value: gfx.Color{b: 0.9}
	}
	gfx.begin_pass(sapp.create_default_pass(pass_action))
	gfx.apply_viewport(0, 0, app.width, app.height, true)

	// update vertex buffer with vertex array data
	vertex_buff_range := gfx.Range{
		ptr: app.vertex_array.data
		size: usize(app.vertex_array.len * int(sizeof(Vertex_t)))
	}
	if app.index_array.len > 1 {
		gfx.update_buffer(app.bind.vertex_buffers[0], &vertex_buff_range)
	}

	// update index buffer with index array data
	index_buff_range := gfx.Range{
		ptr: app.index_array.data
		size: usize(app.index_array.len * int(sizeof(u32)))
	}
	if app.index_array.len > 1 {
		gfx.update_buffer(app.bind.index_buffer, &index_buff_range)
	}

	gfx.apply_pipeline(app.shader_pipeline)
	gfx.apply_bindings(&app.bind)

	if app.index_array.len > 1 {
		gfx.draw(0, app.index_array.len, 1)
	}

	gfx.end_pass()
	gfx.commit()


}
