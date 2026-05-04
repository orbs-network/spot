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

  const { dex: globalDex, salt: _globalSalt, ...baseDefaults } = raw['*'] ?? {};
  const chainConfig = raw[chainId];
  if (!chainConfig) return;

  const { dex, salt: _chainSalt, ...chainDefaults } = chainConfig;

  const mergedConfig = { ...baseDefaults, ...chainDefaults };
  const name = dexName?.trim();

  if (!name) return mergedConfig;

  const globalDexOverrides = globalDex?.[name];
  const chainDexOverrides = dex?.[name];
  if (!globalDexOverrides && !chainDexOverrides) return;

  return { ...mergedConfig, ...globalDexOverrides, ...chainDexOverrides };
}

module.exports = { config, abis, raw };
