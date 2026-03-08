import Web3 from "web3";

function splitSignature(signature) {
  const normalized = signature.startsWith("0x") ? signature.slice(2) : signature;

  if (normalized.length !== 130) {
    throw new Error("signature must be 65 bytes");
  }

  return {
    r: `0x${normalized.slice(0, 64)}`,
    s: `0x${normalized.slice(64, 128)}`,
    v: `0x${normalized.slice(128, 130)}`,
  };
}

export async function approveSignAndSubmitOrder({
  prepared,
  account,
  provider = window.ethereum,
}) {
  const web3 = new Web3(provider);
  const normalizedAccount = account.toLowerCase();
  const expectedSigner = prepared.signing.signer.toLowerCase();

  if (normalizedAccount !== expectedSigner) {
    throw new Error(
      `signer mismatch: expected ${prepared.signing.signer}, got ${account}`
    );
  }

  // Skip this transaction if the token is already approved for the required spender.
  await web3.eth.sendTransaction({
    from: account,
    to: prepared.approval.tx.to,
    data: prepared.approval.tx.data,
    value: prepared.approval.tx.value,
  });

  const signature = await web3.currentProvider.request({
    method: prepared.signing.jsonRpcMethod,
    params: prepared.signing.params,
  });

  const response = await fetch(prepared.submit.url, {
    method: prepared.submit.method,
    headers: prepared.submit.headers,
    body: JSON.stringify({
      ...prepared.submit.body,
      signature: splitSignature(signature),
    }),
  });

  const text = await response.text();
  let body;

  try {
    body = JSON.parse(text);
  } catch {
    body = text;
  }

  return {
    ok: response.ok,
    status: response.status,
    signature,
    body,
  };
}
