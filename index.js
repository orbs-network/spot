const raw = require('./script/input/config.json');
const { dex: _ignoredDex, ...baseDefaults } = raw['*'] || {};

module.exports.config = (chainId, dexName) => {
  if (!chainId || !dexName?.trim()) return undefined;
  const chainConfig = raw[chainId];
  const dexConfig = chainConfig?.dex?.[dexName];
  if (!dexConfig) return undefined;
  const { dex: _ignored, ...chainDefaults } = chainConfig || {};
  return { ...baseDefaults, ...chainDefaults, ...dexConfig };
};

const abis = {
  wm: require('./out/WM.sol/WM.abi.json'),
  repermit: require('./out/RePermit.sol/RePermit.abi.json'),
  reactor: require('./out/OrderReactor.sol/OrderReactor.abi.json'),
  executor: require('./out/Executor.sol/Executor.abi.json'),
  refinery: require('./out/Refinery.sol/Refinery.abi.json'),
  adapter: require('./out/DefaultDexAdapter.sol/DefaultDexAdapter.abi.json'),
};

module.exports.abis = abis;
