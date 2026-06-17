import sys
import os

target_files = [
    "scenes/FurnacePlaced.tscn",
    "scenes/ChemBenchPlaced.tscn",
    "scenes/StorageChest.tscn",
    "scenes/BatteryStation.tscn"
]

light_subresources = """[ext_resource type="Script" path="res://scripts/PoweredLight.gd" id="99_light_script"]

[sub_resource type="Gradient" id="Gradient_light"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 1, 1, 1, 0, 0, 0, 1)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_light"]
gradient = SubResource("Gradient_light")
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(0.8, 0.1)

"""

light_node = """
[node name="PointLight2D" type="PointLight2D" parent="."]
texture = SubResource("GradientTexture2D_light")
script = ExtResource("99_light_script")
"""

for filepath in target_files:
    if not os.path.exists(filepath):
        continue
    with open(filepath, 'r') as f:
        content = f.read()

    # Inject subresources after the first [ext_resource] or [sub_resource] block
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('[node'):
            insert_idx = i
            break
            
    # Before the first [node name=..., inject the sub_resources
    lines.insert(insert_idx, light_subresources)
    
    content = '\n'.join(lines)
    content += light_node
    
    with open(filepath, 'w') as f:
        f.write(content)
        
print("Patched scenes!")
