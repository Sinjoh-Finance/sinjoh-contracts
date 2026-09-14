import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const here = import.meta.dirname;
const destination = resolve(here, '../../deployments/stock-infrastructure');
const cast = process.env.FOUNDRY_CAST || 'cast';
const contracts = {
  UniswapV3Factory: '@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json',
  UniswapV3Pool: '@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json',
  NonfungiblePositionManager: '@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json',
};
const keccak = value => execFileSync(cast, ['keccak', value], { encoding: 'utf8' }).trim();
const manifest = {
  purpose: 'Canonical source-pinned artifacts for local infrastructure rehearsal; no deployment addresses.',
  packageLockSha256: createHash('sha256').update(readFileSync(resolve(here, 'package-lock.json'))).digest('hex'),
  packages: { '@uniswap/v3-core': '1.0.1', '@uniswap/v3-periphery': '1.4.4' },
  artifacts: {},
};
mkdirSync(destination, { recursive: true });
for (const [name, path] of Object.entries(contracts)) {
  const artifact = JSON.parse(readFileSync(resolve(here, 'node_modules', path)));
  if (Object.keys(artifact.linkReferences).length) throw new Error(`${name}: unresolved libraries`);
  const creationCodeHash = keccak(artifact.bytecode);
  if (name === 'UniswapV3Pool' && creationCodeHash !== '0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54') {
    throw new Error('Pool creation code does not match the canonical manager PoolAddress library.');
  }
  manifest.artifacts[name] = { source: path, creationCodeHash, runtimeBytesBeforeImmutables: (artifact.deployedBytecode.length - 2) / 2 };
  writeFileSync(resolve(destination, `${name}.json`), JSON.stringify({ abi: artifact.abi, bytecode: artifact.bytecode }, null, 2) + '\n');
}
writeFileSync(resolve(destination, 'artifacts.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify(manifest, null, 2));
