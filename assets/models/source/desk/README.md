# Desk — production source checklist

The old `assets/models/glb/desk.glb` is a discarded technical blockout. It is not a visual reference and must not be re-used.

## Approved visual direction

- cosy cartoon 3D with believable proportions and materials;
- pale warm wood with slightly darker edge/underside accents;
- rounded tabletop corners and softened edges;
- four sturdy legs, a front drawer unit, and a raised rear shelf;
- compact home-office scale, designed to hold the laptop and monitor camera.

## Blockbench workflow

1. Block the silhouette with separate editable parts: top, legs, drawer face, rear shelf and shelf supports.
2. Add visual detail: rounded/bevelled corners, drawer seams, handle, back braces and small feet.
3. Create and assign a wood texture/material; unwrap every visible face and reserve separate UV space for trim and hardware.
4. Export a binary `desk.glb` into `assets/models/glb/candidates/`.
5. Import the selected model into Unity, inspect at close and gameplay distance, then review it before replacing the room desk.

## Acceptance check

- recognisable silhouette from the approved desk concept;
- no untextured primitive appearance;
- readable drawer, shelf and leg construction at gameplay distance;
- origin at floor centre; Y-up; consistent scale with the room;
- The selected model imports in Unity without errors; use a supported format or an explicitly configured importer.
