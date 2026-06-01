print("""[sub_resource type="Gradient" id="Gradient_light"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 1, 1, 1, 0, 0, 0, 1)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_light"]
gradient = SubResource("Gradient_light")
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(0.8, 0.1)
""")
