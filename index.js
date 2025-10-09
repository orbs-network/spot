const raw = require('./script/input/config.json');

const { dex: _globalDex, ...baseDefaults } = raw['*'] ?? {};

function config(chainId, dexName) {
  if (!chainId || !dexName?.trim()) return;

  const chainConfig = raw[chainId];
  if (!chainConfig) return;

  const { dex, ...chainDefaults } = chainConfig;
  const dexOverrides = dex?.[dexName];
  if (!dexOverrides) return;

  return { ...baseDefaults, ...chainDefaults, ...dexOverrides };
}

const loadAbi = (name) => require(`./out/${name}.sol/${name}.abi.json`);

const abis = {
  wm: loadAbi('WM'),
  repermit: loadAbi('RePermit'),
  reactor: loadAbi('OrderReactor'),
  executor: loadAbi('Executor'),
  refinery: loadAbi('Refinery'),
  adapter: loadAbi('DefaultDexAdapter'),
};

module.exports = { config, abis };
