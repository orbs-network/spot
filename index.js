const raw = require('./config.json');

const loadAbi = (name) => require(`./out/${name}.sol/${name}.abi.json`);

const abis = () => ({
  wm: loadAbi('WM'),
  repermit: loadAbi('RePermit'),
  reactor: loadAbi('OrderReactor'),
  executor: loadAbi('Executor'),
  refinery: loadAbi('Refinery'),
  settler: loadAbi('Settler'),
  adapter: loadAbi('DefaultDexAdapter'),
});

function config(chainId, dexName) {
  if (!chainId) return;

  const { dex: _globalDex, ...baseDefaults } = raw['*'] ?? {};
  const chainConfig = raw[chainId];
  if (!chainConfig) return;

  const { dex, ...chainDefaults } = chainConfig;

  if (!dexName?.trim()) {
    return { ...baseDefaults, ...chainDefaults };
  }

  const dexOverrides = dex?.[dexName];
  if (!dexOverrides) return;

  return { ...baseDefaults, ...chainDefaults, ...dexOverrides };
}

module.exports = { config, abis, raw };
