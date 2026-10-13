# Turns the two hero MacBook models into GLBs for the v4 trailer, each with a "Screen" mesh
# mapped to the full display (u left to right, v top to bottom), so a screen still fills it.
# Usage: Blender -b --python make-hero-macs.py -- <m5.glb> <laptop.fbx> <out-dir>
import bpy, bmesh, sys, os
from mathutils import Vector

m5, fbx, out = sys.argv[sys.argv.index("--") + 1:]

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def planar_uv(obj, axes=("x", "z")):
    """Maps the mesh's own extent to 0..1, flipping v so the texture's top is the screen's top."""
    me = obj.data
    pts = [obj.matrix_world @ v.co for v in me.vertices]
    a = {"x": 0, "y": 1, "z": 2}
    i, j = a[axes[0]], a[axes[1]]
    lo_i, hi_i = min(p[i] for p in pts), max(p[i] for p in pts)
    lo_j, hi_j = min(p[j] for p in pts), max(p[j] for p in pts)
    if not me.uv_layers: me.uv_layers.new()
    uv = me.uv_layers.active.data
    for loop in me.loops:
        p = obj.matrix_world @ me.vertices[loop.vertex_index].co
        uv[loop.index].uv = ((p[i] - lo_i) / (hi_i - lo_i), (p[j] - lo_j) / (hi_j - lo_j))
    print("screen", obj.name, "aspect", (hi_i - lo_i) / (hi_j - lo_j))

def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_image_format="AUTO")

# The 14-inch MacBook Pro with M5: its screen is one mesh with a wallpaper material.
reset()
bpy.ops.import_scene.gltf(filepath=m5)
screen = bpy.data.objects["tfTbkkzhxqpKRgC"]
planar_uv(screen)
mat = bpy.data.materials.new("Screen")
screen.data.materials.clear(); screen.data.materials.append(mat)
screen.name = "Screen"
export(os.path.join(out, "m5.glb"))

# The other laptop: two copies in one file sharing a texture atlas; keep the open one and cut the
# display (the photo in the atlas) out into its own mesh.
reset()
bpy.ops.import_scene.fbx(filepath=fbx)
for name in ("Mac_A.001", "Mac_B.001"):
    bpy.data.objects.remove(bpy.data.objects[name])
lid = bpy.data.objects["Mac_A.002"]
bpy.context.view_layer.objects.active = lid
bpy.ops.object.select_all(action="DESELECT"); lid.select_set(True)
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
U0, U1, V0, V1 = 0.375, 0.785, 0.685, 0.945
uv = lid.data.uv_layers.active.data
picked = 0
for poly in lid.data.polygons:
    poly.select = all(U0 <= uv[i].uv.x <= U1 and V0 <= uv[i].uv.y <= V1 for i in poly.loop_indices)
    picked += poly.select
print("display faces", picked, "of", len(lid.data.polygons))
# Face select mode, so the faces picked above are exactly what gets cut out.
bpy.context.tool_settings.mesh_select_mode = (False, False, True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.separate(type="SELECTED")
bpy.ops.object.mode_set(mode="OBJECT")
disp = [o for o in bpy.context.selected_objects if o != lid][0]
disp.name = "Screen"
print("cut", len(disp.data.polygons))
# This display is drawn in the lid's tilted plane; map it with its own UV rectangle.
uv = disp.data.uv_layers.active.data
us = [d.uv.x for d in uv]; vs = [d.uv.y for d in uv]
lo_u, hi_u, lo_v, hi_v = min(us), max(us), min(vs), max(vs)
for d in uv: d.uv = ((d.uv.x - lo_u) / (hi_u - lo_u), (d.uv.y - lo_v) / (hi_v - lo_v))
print("display uv rect", lo_u, hi_u, lo_v, hi_v)
mat = bpy.data.materials.new("Screen")
disp.data.materials.clear(); disp.data.materials.append(mat)
export(os.path.join(out, "laptop.glb"))
