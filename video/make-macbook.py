# Turns the 16-inch MacBook Pro model into public/v3/macbook.glb for the version 3 commercial.
# Run: Blender -b <model>.blend --python make-macbook.py -- public/v3/macbook.glb
import bpy, bmesh, mathutils, sys
out = sys.argv[-1]
objs = bpy.data.objects
bpy.data.objects.remove(objs['yIwQWXMhgFCUjXk'])
SCREEN = 'VQmfhbMzfNAuKAD'
DARK = {'XlcvJOqSiZcqDDS', 'XmEJWcRmlkotJdx', 'OXjUsVQnIlkDrZa', 'UJKMWhpvMdqjnoM', 'ZtDnMGoWGySWyjB', 'vttfLwUKvlhvIxZ', 'EkfKXxkPaSHjDtP'}
mats = {n: bpy.data.materials.new(n) for n in ('Screen', 'Dark', 'Body')}
meshes = [o for o in objs if o.type == 'MESH']
# Bake world transforms into the meshes, then unparent.
for o in meshes:
    o.data = o.data.copy()
    o.data.transform(o.matrix_world)
    o.parent = None
    o.matrix_world = mathutils.Matrix.Identity(4)
    kind = 'Screen' if o.name == SCREEN else 'Dark' if o.name in DARK else 'Body'
    o.data.materials.clear(); o.data.materials.append(mats[kind])
    o['kind'] = kind
for o in [o for o in objs if o.type != 'MESH']: bpy.data.objects.remove(o)
# Screen UVs: u across, v from the bottom of the display to the top.
scr = objs[SCREEN]; me = scr.data
xs = [v.co.x for v in me.vertices]; zs = [v.co.z for v in me.vertices]
x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
while me.uv_layers: me.uv_layers.remove(me.uv_layers[0])
uv = me.uv_layers.new(name='UVMap')
for loop in me.loops:
    co = me.vertices[loop.vertex_index].co
    uv.data[loop.index].uv = ((co.x - x0) / (x1 - x0), (co.z - z0) / (z1 - z0))
# One object per material.
for kind in ('Screen', 'Dark', 'Body'):
    group = [o for o in objs if o.get('kind') == kind]
    bpy.ops.object.select_all(action='DESELECT')
    for o in group: o.select_set(True)
    bpy.context.view_layer.objects.active = group[0]
    if len(group) > 1: bpy.ops.object.join()
    bpy.context.view_layer.objects.active.name = kind
for o in objs:
    if o.name != 'Screen':
        for l in list(o.data.uv_layers): o.data.uv_layers.remove(l)
print('OBJS', [(o.name, len(o.data.polygons)) for o in objs])
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_materials='PLACEHOLDER', export_normals=True, export_apply=True, export_yup=True)
