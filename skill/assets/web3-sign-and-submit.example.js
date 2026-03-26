// Example only. This flow uses eth_signTypedData_v4 via an injected provider,
// but any framework that signs the same prepared.typedData payload is valid.

import Web3 from "web3";

const DEPOSIT_DATA = "0xd0e30db0";

export async function approveSignAndSubmitOrder({
  prepared,
  account,
  provider = window.ethereum,
  wrappedNative,
  nativeInputAmount,
  sendApproval = false,
}) {
  const web3 = new Web3(provider);
  const normalizedAccount = account.toLowerCase();
  const expectedSigner = prepared.signing.signer.toLowerCase();

  // The EIP-712 signer must be the same address that created the order.
  if (normalizedAccount !== expectedSigner) {
    throw new Error(
      `signer mismatch: expected ${prepared.signing.signer}, got ${account}`
    );
  }

  // Native input is not supported by the order itself.
  // If the input starts as the chain's native asset, wrap it to WNATIVE first.
  if (
    nativeInputAmount != null &&
    nativeInputAmount !== "0" &&
    nativeInputAmount !== "0x0"
  ) {
    if (!wrappedNative) {
      throw new Error("wrappedNative is required when nativeInputAmount is set");
    }

    await web3.eth.sendTransaction({
      from: account,
      to: wrappedNative,
      data: DEPOSIT_DATA,
      value: nativeInputAmount,
    });
  }

  // Approval is optional.
  // Only send this transaction when the current ERC-20 allowance is lower than
  // prepared.approval.amount, or when you know approval is still needed.
  if (sendApproval) {
    await web3.eth.sendTransaction({
      from: account,
      to: prepared.approval.tx.to,
      data: prepared.approval.tx.data,
      value: prepared.approval.tx.value,
    });
  }

  // This example uses eth_signTypedData_v4, but any equivalent EIP-712 signer works.
  const signature = await provider.request({
    method: "eth_signTypedData_v4",
    params: [account, JSON.stringify(prepared.typedData)],
  });

  // Submit the order payload plus the returned signature to the relay endpoint.
  const response = await fetch(prepared.submit.url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      ...prepared.submit.body,
      signature,
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
