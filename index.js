const raw = require('./script/input/config.json');

module.exports.config = (chainId) => {
  const base = raw['*'];
  if (!chainId) return { ...base };
  const override = raw[`${chainId}`];
  return override ? { ...base, ...override } : { ...base };
};

module.exports.abi = {
  wm: require('./out/WM.sol/WM.abi.json'),
  repermit: require('./out/RePermit.sol/RePermit.abi.json'),
  reactor: require('./out/OrderReactor.sol/OrderReactor.abi.json'),
  executor: require('./out/Executor.sol/Executor.abi.json'),
  refinery: require('./out/Refinery.sol/Refinery.abi.json'),
};
