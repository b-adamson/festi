# festi

A Vulkan 3D rendering/game engine, written in C++ from scratch, for making stop-motion-style hyperlapses.

Scenes are scripted in Python (via embedded pybind11 bindings); place models, key
their position/rotation/scale/visibility/materials frame by frame, and festi renders the
result in real time with an interactive camera. The core engine (transforms, lighting,
shadows, instancing) runs as compiled C++/GLSL on the GPU; Python only runs once at
scene-setup time.

Longer writeup, with GIFs of the output: **https://b-adamson.github.io/festi.html**

Currently the CMake build is Windows-only.

Written entirely by hand, no AI assistance as this predates vibecoding becoming mainstream.
Inspired by, and built while following along with, [Brendan Galea's Vulkan tutorial series](https://www.youtube.com/@BrendanGalea), which was an excellent resource for learning the API.

## Features

- Vulkan rendering pipeline (vertex/fragment shaders, perspective & orthographic projection)
- Ambient, directional, and point specular lighting with Blinn-Phong specular shading
- Real-time shadows via a shadow pass (scene re-rendered from the light's point of view orthographically)
- Normal mapping, and per-face keyframeable material properties (contrast, saturation, UV offset)
- Procedural instancing e.g. "building" instancing that scaffolds columns/struts/layers (this is similar to the Blender instancing system)
  from a single base model, with per-frame randomness and a "jenga" factor for knocking
  pieces out
- OBJ/MTL model loading (tinyobjloader) and PNG textures (stb)
- Python scene scripting through a `festi` module built with pybind11, with custom-made type casters between NumPy arrays and GLM vector/matrix types

## Example

`src/scripts/buildings.py` scripts a 300-frame scene: it builds a scaffolded structure out
of instanced struts and floor panels, and animates the camera, lighting, instance density,
and per-face material data frame by frame via `fs.scene.insertKeyframe(...)`.

## Layout

```
src/
  app.cpp / app.hpp        engine entry point / main loop
  device, window, swap_chain, renderer   Vulkan setup and frame rendering
  buffer, descriptors, model, materials  GPU resource management
  camera                   interactive camera
  bindings.cpp/hpp         pybind11 bindings exposing the engine to Python
  systems/                 render systems (main geometry pass, point lights)
  shaders/                 GLSL shaders (main, point light, shadow)
  scripts/                 example Python scenes
models/, materials/        OBJ/MTL models and material assets used by the example scripts
```

## Building (Windows)

Requires:
- [Vulkan SDK](https://www.lunarg.com/vulkan-sdk)
- [GLFW](https://www.glfw.org) (64-bit)
- [GLM](https://github.com/g-truc/glm)
- [stb](https://github.com/nothings/stb)
- [tinyobjloader](https://github.com/tinyobjloader/tinyobjloader)
- [pybind11](https://github.com/pybind/pybind11)
- Python 3.12 (dev headers/libs)

Edit the `Makefile`:
- `INCLUDE_DIRS` / `LIB_DIRS` — point at the libraries above (GLFW + Vulkan libs)
- `VENV_PYTHON_DIR` — where the `festi` Python extension module (`festi.pyd`) should be installed

Then:

```
make            # builds shaders, festi.exe, and the festi Python module
```

Run a scene with `festi.exe`, or `import festi` from Python after building `python_module`.

## License

[MIT](LICENSE)
