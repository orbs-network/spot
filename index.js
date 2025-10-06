const raw = require('./script/input/config.json');

module.exports.config = (chainId) => {
  const base = raw['*'];
  if (!chainId) return { ...base };
  const override = raw[`${chainId}`];
  return override ? { ...base, ...override } : { ...base };
};

// Cache for ABIs to avoid rebuilding on every call
let abiCache = null;

module.exports.abi = () => {
  // Return cached result if already built
  if (abiCache) {
    return abiCache;
  }

  // Load core contract ABIs once
  const coreAbis = {
    wm: require('./out/WM.sol/WM.abi.json'),
    repermit: require('./out/RePermit.sol/RePermit.abi.json'),
    reactor: require('./out/OrderReactor.sol/OrderReactor.abi.json'),
    executor: require('./out/Executor.sol/Executor.abi.json'),
    refinery: require('./out/Refinery.sol/Refinery.abi.json'),
    adapter: require('./out/DefaultDexAdapter.sol/DefaultDexAdapter.abi.json'),
  };

  // Build structure: { chainid: { dex: { dexname: { contract: abi }}}}
  const result = {};

  // Iterate through all chain configurations
  for (const chainId in raw) {
    if (chainId === '*') continue; // Skip the base config

    const chainConfig = raw[chainId];
    if (!chainConfig.dex) continue; // Skip if no dex config

    result[chainId] = { dex: {} };

    // For each DEX on this chain, include all core ABIs
    for (const dexName in chainConfig.dex) {
      result[chainId].dex[dexName] = { ...coreAbis };
    }
  }

  // Cache the result
  abiCache = result;
  return result;
};
