# Literal.

A 24 s film built with HyperFrames and three.js. `progress.md` has the working notes, `SPEC.md` the spec.

## three.js

`index.html` maps `three` to `vendor/three/three.module.js` (with `three.core.js` beside it, revision 185) and `three/addons/` to `vendor/three/examples/jsm/`. Only the two addons that the film imports are vendored: `environments/RoomEnvironment.js` and `utils/BufferGeometryUtils.js`.

The files used to sit in `vendor/three/build/`. The root `.gitignore` ignores every directory named `build/`, so they were never committed and a fresh clone could not load three.js. Do not move them back into a `build/` directory.

## Preview

`npm run dev` and `npm run check` run HyperFrames 0.8.226 through `npx`. Both need network access to fetch it.
