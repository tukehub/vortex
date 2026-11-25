// Geometry and material transforms for build_environment.py.
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { NodeIO, Primitive, PropertyType } from '@gltf-transform/core';
import { cloneDocument, dedup, prune, reorder, simplify, weld } from '@gltf-transform/functions';
import { MeshoptEncoder, MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const [source, output, settingsPath] = process.argv.slice(2);
const settings = JSON.parse(await readFile(settingsPath, 'utf8'));
const io = new NodeIO();
const input = await io.readAsJSON(source);
const { json } = input;
if (json.extensionsUsed?.length || json.scenes?.length !== 1 || json.animations?.length || json.skins?.length) {
  throw new Error('Expected one static core glTF scene without skins, animations or extensions.');
}
const document = await io.readJSON(input);

function primitives(doc) {
  return doc.getRoot().listMeshes().flatMap(mesh => mesh.listPrimitives());
}

function stats(doc) {
  const surfaces = doc.getRoot().listNodes().flatMap(node => node.getMesh()?.listPrimitives() ?? []);
  return {
    triangles: surfaces.reduce((sum, p) => sum + (p.getIndices() ?? p.getAttribute('POSITION')).getCount() / 3, 0),
    vertices: surfaces.reduce((sum, p) => sum + p.getAttribute('POSITION').getCount(), 0),
    primitives: surfaces.length,
    materials: doc.getRoot().listMaterials().length,
  };
}

const infoFields = ['getTexCoord', 'getMagFilter', 'getMinFilter', 'getWrapS', 'getWrapT'];
const assetTextures = new Map();
const textureFiles = {};
async function prepareTexture(texture, role) {
  const { data, width, height, format } = await textureData(texture);
  const hash = createHash('sha256').update(data).digest('hex');
  const assetKey = `${role}_${hash}`;
  if (!assetTextures.has(assetKey)) {
    const filename = `${role}_${hash.slice(0, 16)}.${format === 'jpeg' ? 'jpg' : 'png'}`;
    assetTextures.set(assetKey, document.createTexture().setName(role).setURI(filename)
      .setImage(data).setMimeType(`image/${format}`));
    textureFiles[filename] = { role, width, height };
  }
  return assetTextures.get(assetKey);
}

async function textureData(texture) {
  const data = texture.getImage();
  const { width, height, format } = await sharp(data).metadata();
  if (Math.max(width, height) > settings.resolution || !['png', 'jpeg'].includes(format)) {
    throw new Error(`${texture.getURI()} must be a PNG or JPEG at or below ${settings.resolution}px.`);
  }
  return { data, width, height, format };
}

async function packArm(material, mr, ao) {
  const mrInfo = material.getMetallicRoughnessTextureInfo();
  const aoInfo = material.getOcclusionTextureInfo();
  if (aoInfo && infoFields.some(field => mrInfo[field]() !== aoInfo[field]())) {
    throw new Error(`${material.getName()}: AO and metallic-roughness must use identical UV and sampler settings.`);
  }
  // Poly Haven's current glTFs sometimes connect the ARM image only to metallic-roughness.
  // Its provider-supplied filename identifies the packed red AO channel in that case.
  if (mr === ao || (!ao && /_arm_[12]k\.(png|jpe?g)$/i.test(mr.getURI()))) return mr;
  if (!ao) throw new Error(`${material.getName()}: missing source AO.`);

  const { data, width, height } = await textureData(mr);
  const aoData = (await textureData(ao)).data;
  const [rg, red] = await Promise.all([
    sharp(data).toColourspace('srgb').removeAlpha().raw().toBuffer(),
    sharp(aoData).toColourspace('srgb').extractChannel(0)
      .resize(width, height, { fit: 'fill' }).raw().toBuffer(),
  ]);
  for (let pixel = 0; pixel < red.length; pixel++) rg[pixel * 3] = red[pixel];
  const packed = await sharp(rg, { raw: { width, height, channels: 3 } }).png().toBuffer();
  return document.createTexture().setImage(packed).setMimeType('image/png');
}

await document.transform(prune());
for (const p of primitives(document)) {
  if (p.getMode() !== Primitive.Mode.TRIANGLES || !p.getAttribute('NORMAL') || !p.getMaterial() ||
      p.listTargets().length) {
    throw new Error('Expected textured static triangles with vertex normals.');
  }
}
const original = stats(document);
const normalisedMaterials = document.getRoot().listMaterials();
for (const material of normalisedMaterials) {
  const albedo = material.getBaseColorTexture();
  const normal = material.getNormalTexture();
  const mr = material.getMetallicRoughnessTexture();
  if (!albedo || !normal || !mr) {
    throw new Error(`${material.getName()}: source albedo, normal and roughness are required.`);
  }
  const ao = material.getOcclusionTexture();
  const arm = await prepareTexture(await packArm(material, mr, ao), 'arm');
  material.setBaseColorTexture(await prepareTexture(albedo, 'albedo'));
  material.setNormalTexture(await prepareTexture(normal, 'normal'));
  material.setMetallicRoughnessTexture(arm).setOcclusionTexture(arm);
  if (!ao) {
    const from = material.getMetallicRoughnessTextureInfo();
    material.getOcclusionTextureInfo().copy(from);
  }
  const emissive = material.getEmissiveTexture();
  if (emissive) material.setEmissiveTexture(await prepareTexture(emissive, 'emissive'));
}
await document.transform(prune(), dedup({ propertyTypes: [PropertyType.ACCESSOR, PropertyType.MESH, PropertyType.MATERIAL] }),
  weld({ overwrite: true }));
if (!original.triangles) throw new Error('Source has no triangles.');

const levels = [];
for (const [index, target] of settings.triangles.entries()) {
  const lod = cloneDocument(document);
  await lod.transform(
    simplify({ simplifier: MeshoptSimplifier, ratio: Math.min(1, target / original.triangles),
      error: settings.errors[index], lockBorder: settings.lock_border }),
    reorder({ encoder: MeshoptEncoder, target: 'performance' }),
    prune(),
  );
  const current = stats(lod);
  // Simplification is approximate, especially with several materials and small primitives.
  if (current.triangles > target || current.triangles >= (levels.at(-1)?.triangles ?? Infinity) ||
      current.primitives !== original.primitives) {
    throw new Error(`LOD${index}: got ${current.triangles}/${target} triangles and ${current.primitives}/${original.primitives} primitives. Review budgets or error limits.`);
  }
  for (const [bufferIndex, buffer] of lod.getRoot().listBuffers().entries()) {
    buffer.setURI(`lod${index}_${bufferIndex}.bin`);
  }
  await io.write(join(output, `lod${index}.gltf`), lod);
  levels.push({ ...current, budget: target, error_limit: settings.errors[index] });
}
await writeFile(join(output, 'geometry.json'), JSON.stringify({ original, levels, textureFiles }));
