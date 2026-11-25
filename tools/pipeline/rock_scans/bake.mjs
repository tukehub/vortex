import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { Document, NodeIO } from '@gltf-transform/core';
import { MeshoptEncoder, MeshoptSimplifier } from 'meshoptimizer';

const [manifest, directory, destination] = process.argv.slice(2);
const { sources } = JSON.parse(await readFile(manifest, 'utf8'));
const io = new NodeIO();
const library = new Document();
const buffer = library.createBuffer();
const scene = library.createScene('VloreRockScans');
library.getRoot().setDefaultScene(scene);
await Promise.all([MeshoptEncoder.ready, MeshoptSimplifier.ready]);

async function sourceGeometry(id) {
  const folder = join(directory, id);
  const json = JSON.parse(await readFile(join(folder, 'source.gltf'), 'utf8'));
  const [mesh] = json.meshes;
  const [node] = json.nodes;
  if (json.meshes.length !== 1 || json.nodes.length !== 1 || mesh.primitives.length !== 1 ||
      node.matrix || node.translation || node.rotation || node.scale) {
    throw new Error(`${id}: expected a single primitive in world-aligned coordinates`);
  }
  for (const key of ['materials', 'images', 'textures', 'samplers']) delete json[key];
  delete mesh.primitives[0].material;
  const resources = Object.fromEntries(await Promise.all(json.buffers.map(async ({ uri }) =>
    [uri, await readFile(join(folder, uri))])));
  const parsed = await io.readJSON({ json, resources });
  const p = parsed.getRoot().listMeshes()[0].listPrimitives()[0];
  return {
    positions: p.getAttribute('POSITION').getArray(),
    normals: p.getAttribute('NORMAL').getArray(),
    indices: Uint32Array.from(p.getIndices().getArray()),
  };
}

function normalize(positions) {
  const min = [Infinity, Infinity, Infinity];
  const max = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.length; i += 3) {
    for (let a = 0; a < 3; a++) {
      min[a] = Math.min(min[a], positions[i + a]);
      max[a] = Math.max(max[a], positions[i + a]);
    }
  }
  const span = Math.max(max[0] - min[0], max[2] - min[2]);
  const origin = [(max[0] + min[0]) * .5, min[1], (max[2] + min[2]) * .5];
  for (let i = 0; i < positions.length; i++) positions[i] = (positions[i] - origin[i % 3]) / span;
  return (max[1] - min[1]) / span;
}

// Compute a baked proximity term from inward folds in the scan and from the
// normalized bottom plane. Work at full scan resolution once so LODs retain it.
function bakeOcclusion(positions, normals, indices, height) {
  const inward = new Float32Array(positions.length / 3);
  const total = new Uint16Array(inward.length);
  for (let t = 0; t < indices.length; t += 3) {
    for (let k = 0; k < 3; k++) {
      const a = indices[t + k];
      const b = indices[t + (k + 1) % 3];
      const x = positions[b*3] - positions[a*3];
      const y = positions[b*3+1] - positions[a*3+1];
      const z = positions[b*3+2] - positions[a*3+2];
      const step = Math.hypot(x,y,z);
      if (step < 1e-6) continue;
      inward[a] += Math.max(0, (x*normals[a*3] + y*normals[a*3+1] + z*normals[a*3+2]) / step);
      total[a]++;
    }
  }
  return Float32Array.from(inward, (dip, i) => {
    const above = Math.max(0, Math.min(1, positions[i*3+1] / Math.max(.07, height * .58)));
    return Math.max(.44, .70 + .30*above - 1.6*dip/Math.max(1,total[i]));
  });
}

function writeMesh(name, original, ao, selected) {
  const [remap, count] = MeshoptEncoder.reorderMesh(selected, true, false);
  const positions = new Float32Array(count * 3);
  const normals = new Float32Array(count * 3);
  const colors = new Uint8Array(count * 4);
  for (let i = 0; i < remap.length; i++) {
    const j = remap[i];
    if (j >= count) continue;
    positions.set(original.positions.subarray(i*3, i*3+3), j*3);
    normals.set(original.normals.subarray(i*3, i*3+3), j*3);
    colors.set([Math.round(255*ao[i]), 255, 255, 255], j*4);
  }
  const accessor = (type, array) => library.createAccessor().setBuffer(buffer).setType(type).setArray(array);
  const primitive = library.createPrimitive()
    .setAttribute('POSITION', accessor('VEC3', positions))
    .setAttribute('NORMAL', accessor('VEC3', normals))
    .setAttribute('COLOR_0', accessor('VEC4', colors).setNormalized(true))
    .setIndices(accessor('SCALAR', Uint16Array.from(selected)));
  const mesh = library.createMesh(name).addPrimitive(primitive);
  scene.addChild(library.createNode(name).setMesh(mesh));
}

for (const [id, asset] of sources.entries()) {
  const original = await sourceGeometry(asset.id);
  const height = normalize(original.positions);
  const ao = bakeOcclusion(original.positions, original.normals, original.indices, height);
  const actual = [];
  for (const [lod, target] of (asset.triangle_targets ?? [380, 132, 40]).entries()) {
    const [indices] = MeshoptSimplifier.simplifyWithAttributes(
      original.indices, original.positions, 3, original.normals, 3, [.07,.07,.07], null,
      target*3, [0.11, 0.20, 0.38][lod], ['Permissive', 'Prune'],
    );
    const count = indices.length / 3;
    if (count > target * 1.12 || count < Math.max(12, target*.72) || count >= (actual.at(-1) ?? Infinity)) {
      throw new Error(`${asset.id} LOD${lod}: got ${count} triangles, expected approximately ${target}`);
    }
    actual.push(count);
    writeMesh(`Rock${id}_L${lod}`, original, ao, indices);
  }
  console.log(`${asset.id}: ${actual.join(' / ')} triangles`);
}
await io.write(destination, library);
