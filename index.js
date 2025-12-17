const raw = require('./script/input/config.json');


const loadAbi = (name) => require(`./out/${name}.sol/${name}.json`).abi;

const abis = () => ({
  wm: loadAbi('WM'),
  repermit: loadAbi('RePermit'),
  reactor: loadAbi('OrderReactor'),
  executor: loadAbi('Executor'),
  refinery: loadAbi('Refinery'),
  adapter: loadAbi('DefaultDexAdapter'),
});

function config(chainId, dexName) {
  if (!chainId || !dexName?.trim()) return;

  const { dex: _globalDex, ...baseDefaults } = raw['*'] ?? {};
  const chainConfig = raw[chainId];
  if (!chainConfig) return;

  const { dex, ...chainDefaults } = chainConfig;
  const dexOverrides = dex?.[dexName];
  if (!dexOverrides) return;

  return { ...baseDefaults, ...chainDefaults, ...dexOverrides };
}

module.exports = { config, abis };
