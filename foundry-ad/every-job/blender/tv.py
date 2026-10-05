"""Portable CRT television in a black room, rendered as stills for Act I.

Passes (3840x2160, written to assets/img/tv/):
  tv-lit.png  the set lit only by its own white screen (spill on body, floor, antennas)
  tv-off.png  the set unpowered, only a faint cool rim light
  screen.json projected screen opening (px, 3840-wide space) so footage can be composited into the tube

usage: /Applications/Blender.app/Contents/MacOS/Blender -b -P blender/tv.py -- [--samples N] [--scale 1.0]
"""
import json
import math
import os
import sys

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "img", "tv")  # century/assets/img/tv
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SAMPLES = int(argv[argv.index("--samples") + 1]) if "--samples" in argv else 256
SCALE = float(argv[argv.index("--scale") + 1]) if "--scale" in argv else 1.0
DIST = float(argv[argv.index("--dist") + 1]) if "--dist" in argv else 2.0

W, H, D = 0.52, 0.40, 0.38          # body
FEET = 0.016
SW, SH, SR = 0.34, 0.255, 0.034     # screen opening + corner radius
SX, SZ = -0.062, FEET + 0.215       # screen centre (x, z)


def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c) + (1.0,)


def material(name, color, rough, metal=0.0, coat=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(color)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Coat Weight"].default_value = coat
    if emit:
        b.inputs["Emission Color"].default_value = emit
        b.inputs["Emission Strength"].default_value = strength
    return m


def rounded_rect(cx, cz, w, h, r, seg=24):
    pts = []
    corners = [(cx + w / 2 - r, cz + h / 2 - r, 0), (cx - w / 2 + r, cz + h / 2 - r, 90),
               (cx - w / 2 + r, cz - h / 2 + r, 180), (cx + w / 2 - r, cz - h / 2 + r, 270)]
    for ox, oz, a0 in corners:
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((ox + r * math.cos(a), oz + r * math.sin(a)))
    return pts


def frame_ring(name, outer, inner, depth, bevel, y, mat):
    """Flat rounded-rect ring (outer loop bridged to inner loop), solidified backwards and bevelled."""
    bm = bmesh.new()
    loops = []
    for loop in (outer, inner):
        vs = [bm.verts.new((x, y, z)) for x, z in loop]
        loops.append([bm.edges.new((vs[i], vs[(i + 1) % len(vs)])) for i in range(len(vs))])
    bmesh.ops.bridge_loops(bm, edges=loops[0] + loops[1])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    sol = ob.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = depth
    sol.offset = 0
    sol.use_even_offset = True
    bev = ob.modifiers.new("bevel", "BEVEL")
    bev.width = bevel
    bev.segments = 6
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(50)
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def rounded_box(name, size, loc, bevel, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    bpy.ops.object.transform_apply(scale=True)
    mod = ob.modifiers.new("bevel", "BEVEL")
    mod.width = bevel
    mod.segments = 10
    mod.limit_method = "NONE"
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def cylinder(name, r, depth, loc, rot, mat, verts=64, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    if bevel:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 4
        mod.limit_method = "ANGLE"
    ob.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return ob


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene

    body = material("body", "#262628", 0.4, coat=0.35)
    bezel = material("bezel", "#2b2b2c", 0.33, coat=0.5)
    chrome = material("chrome", "#d9d9d9", 0.12, metal=1.0)
    knob = material("knob", "#bdbdbd", 0.28, metal=1.0)
    slot = material("slot", "#050505", 0.8)
    floor = material("floor", "#0b0b0b", 0.32)
    glass = material("glass", "#020202", 0.04, coat=1.0, emit=(0.92, 0.96, 1.0, 1.0), strength=0.0)

    rounded_box("body", (W, D - 0.012, H), (0, (D + 0.012) / 2, FEET + H / 2), 0.04, body)
    outer = rounded_rect(0, FEET + H / 2, W - 0.022, H - 0.022, 0.03)
    hole = rounded_rect(SX, SZ, SW, SH, SR)
    frame_ring("bezel", outer, hole, 0.024, 0.004, 0.0, bezel)
    lip_out = rounded_rect(SX, SZ, SW + 0.018, SH + 0.018, SR + 0.009)
    frame_ring("lip", lip_out, hole, 0.006, 0.0025, -0.014, chrome)

    # domed CRT glass sitting just behind the opening
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=64, y_segments=48, size=0.5)
    for v in bm.verts:
        u, w = v.co.x * 2, v.co.y * 2
        v.co = Vector((SX + u * (SW + 0.02) / 2, 0.006 - 0.016 * (1 - u * u) * (1 - w * w), SZ + w * (SH + 0.02) / 2))
    me = bpy.data.meshes.new("glass")
    bm.to_mesh(me)
    g = bpy.data.objects.new("glass", me)
    bpy.context.collection.objects.link(g)
    g.data.materials.append(glass)
    for p in g.data.polygons:
        p.use_smooth = True

    # control strip: two knobs, a channel dial ring, speaker slots
    cx = 0.188
    for i, z in enumerate((SZ + 0.07, SZ - 0.005)):
        cylinder(f"knob{i}", 0.026, 0.03, (cx, -0.02, z), (math.radians(90), 0, 0), knob, bevel=0.004)
        cylinder(f"knobring{i}", 0.032, 0.006, (cx, -0.007, z), (math.radians(90), 0, 0), chrome, bevel=0.002)
    for i in range(7):
        rounded_box(f"slot{i}", (0.07, 0.01, 0.0055), (cx, -0.008, FEET + 0.06 + i * 0.0125), 0.0025, slot)

    # feet
    for x in (-W / 2 + 0.06, W / 2 - 0.06):
        for y in (0.05, D - 0.06):
            cylinder("foot", 0.018, FEET, (x, y, FEET / 2), (0, 0, 0), slot, verts=32)

    # rabbit-ear antenna
    base = cylinder("antbase", 0.028, 0.02, (0.05, D * 0.62, FEET + H + 0.008), (0, 0, 0), chrome, bevel=0.003)
    for side in (-1, 1):
        L = 0.36
        a = math.radians(26) * side
        tilt = math.radians(-10)
        dx, dz = math.sin(a) * L / 2, math.cos(a) * L / 2
        cylinder("ant", 0.0028, L, (0.05 + dx, D * 0.62 + math.sin(tilt) * L / 2, FEET + H + 0.012 + dz),
                 (tilt, a, 0), chrome, verts=16)
        tip = (0.05 + 2 * dx, D * 0.62 + math.sin(tilt) * L, FEET + H + 0.012 + 2 * dz)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.006, location=tip)
        bpy.context.active_object.data.materials.append(chrome)
        bpy.ops.object.shade_smooth()

    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    bpy.context.active_object.data.materials.append(floor)

    # faint cool rim from behind and above, and a warm-neutral kicker so the off pass is not pure black
    bpy.ops.object.light_add(type="AREA", location=(0.2, 1.6, 1.5))
    rim = bpy.context.active_object
    rim.data.size = 1.6
    rim.data.energy = 45
    rim.data.color = (0.82, 0.88, 1.0)
    rim.rotation_euler = (math.radians(-55), 0, math.radians(180))
    bpy.ops.object.light_add(type="AREA", location=(-1.3, -0.9, 1.0))
    kick = bpy.context.active_object
    kick.data.size = 1.2
    kick.data.energy = 9.0
    kick.rotation_euler = (math.radians(65), 0, math.radians(-55))

    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    sc.world = world

    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam_data.sensor_width = 36
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (SX, -DIST, SZ)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam

    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Base Contrast"
    sc.render.resolution_x = int(3840 * SCALE)
    sc.render.resolution_y = int(2160 * SCALE)
    sc.render.dither_intensity = 1.0
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_depth = "16"
    return sc, cam, glass


def project(sc, cam):
    bpy.context.view_layer.update()
    rx, ry = sc.render.resolution_x, sc.render.resolution_y
    out = {}
    for name, (x, z) in {"tl": (SX - SW / 2, SZ + SH / 2), "tr": (SX + SW / 2, SZ + SH / 2),
                         "bl": (SX - SW / 2, SZ - SH / 2), "br": (SX + SW / 2, SZ - SH / 2),
                         "rc": (SX + SW / 2 - SR, SZ + SH / 2)}.items():
        p = world_to_camera_view(sc, cam, Vector((x, -0.016, z)))
        out[name] = (p.x * rx / SCALE, (1 - p.y) * ry / SCALE)
    left, top = out["tl"]
    right, bottom = out["br"]
    return {"space": [3840, 2160], "x": left, "y": top, "w": right - left, "h": bottom - top,
            "radius": out["tr"][0] - out["rc"][0]}


def main():
    os.makedirs(OUT, exist_ok=True)
    sc, cam, glass = build()
    b = glass.node_tree.nodes["Principled BSDF"]
    with open(os.path.join(OUT, "screen.json"), "w") as f:
        json.dump(project(sc, cam), f, indent=1)
    for name, strength in (("tv-lit", 6.0), ("tv-off", 0.0)):
        b.inputs["Emission Strength"].default_value = strength
        sc.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)


main()
