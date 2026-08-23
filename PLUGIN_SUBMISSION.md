# 📋 Spot Plugin Submission Handoff

Use this document to create and manually submit the public **Spot Advanced Swap Orders** plugin in the OpenAI Platform.

Official submission guide: <https://developers.openai.com/plugins/deploy/submission>

Submission portal: <https://platform.openai.com/plugins/submissions>

## ✅ Submission Readiness

The plugin copy, starter prompts, release notes, and required test cases are ready below.

Before submission, BizDev must complete these four publisher-owned items:

1. Select the verified **Orbs Network** developer or business identity.
2. Confirm the submitter has **Apps Management: Write** permission.
3. Obtain a production square Spot or Orbs logo from the brand team. Do not use `arch.png`; it is a protocol diagram.
4. Confirm the proposed category and country availability with Legal and Support.

## 🏷️ Listing Details

### Plugin name

```text
Spot Advanced Swap Orders
```

### Short description

```text
Gasless non-custodial EVM market and advanced swap orders
```

### Long description

```text
Create and manage gasless, non-custodial swaps across supported EVM chains. Spot guides users through market, limit, TWAP, stop-loss, take-profit, and delayed-start orders; normalizes order parameters; prepares typed data; explains token approval and signing; submits signed orders; monitors execution; and supports exact-match cancellation. Orders remain user-controlled and are protected by onchain validation and oracle pricing.
```

### Developer name

```text
Orbs Network
```

### Proposed category

```text
Finance
```

If **Finance** is unavailable in the portal dropdown, select the closest blockchain or productivity category and record the choice in the release notes.

### Public URLs

1. Website: <https://orbs-network.github.io/spot/>
2. Support: <https://www.orbs.com/contact>
3. Privacy policy: <https://www.orbs.com/privacy-policy>
4. Terms of use: <https://www.orbs.com/terms-of-use/>
5. Source and issue tracker: <https://github.com/orbs-network/spot>

All four required listing URLs returned HTTP 200 when this handoff was prepared.

### Logo

Request the current production square Spot or Orbs logo from the Orbs brand team. Confirm the file format, dimensions, and size against the portal before upload.

## 📦 Skill Upload

1. Open the latest successful **📦 Plugin artifact** GitHub Actions run.
2. Download the `spot-plugin` artifact.
3. Confirm the extracted artifact contains:

```text
.codex-plugin/plugin.json
skills/spot-advanced-swap-orders/SKILL.md
skills/spot-advanced-swap-orders/assets/
skills/spot-advanced-swap-orders/references/
```

4. In the portal, choose **Create plugin** and then **Skills only**.
5. Upload the final `spot-advanced-swap-orders` skill bundle from the artifact's `skills/` directory.
6. Confirm the portal reports the skill name as `spot-advanced-swap-orders` and the version matches the release version.

## 💬 Starter Prompts

Use these three prompts:

1. `Create a WETH-to-USDC limit order on Base.`
2. `Split my WETH-to-USDC swap into four TWAP chunks.`
3. `Check my Spot order and help me cancel it safely.`

## 📝 Release Notes

```text
Initial submission of Spot Advanced Swap Orders v2.8.0 by Orbs Network. The skills-only plugin supports gasless, non-custodial market, limit, TWAP, stop-loss, take-profit, and delayed-start orders across supported EVM chains. It includes bundled parameter rules, typed-data templates, token aliases, lifecycle guidance, mock payload examples, approval guidance, signing guidance, relay submission, status polling, and exact-match cancellation. No MCP server, authentication integration, or custom UI is included. Review tests are deterministic dry runs and require no credentials or funded wallet.
```

Before submission, replace `v2.8.0` if the artifact manifest contains a newer version.

## 🧪 Common Test Fixture

The positive cases below are deterministic dry runs. They must not sign, submit, approve, or send a transaction.

Use this mock swapper and recipient unless a case overrides it:

```text
0x1111111111111111111111111111111111111111
```

Success for a dry run means the skill returns normalized parameters, identifies the order shape, prepares the expected typed-data fields, and stops before any signature or onchain action because the mock address has no signer.

## ✅ Positive Test Cases

### 1. Base market order

**User prompt**

```text
Dry run only: prepare a single market order on Base from 0.01 WETH to USDC for swapper 0x1111111111111111111111111111111111111111. Do not sign or submit it.
```

**Expected workflow behavior**

1. Select chain ID `8453`.
2. Resolve Base WETH as `0x4200000000000000000000000000000000000006` and USDC as `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`.
3. Encode `input.amount` and `input.maxAmount` as `10000000000000000`.
4. Set `output.limit`, `output.triggerLower`, and `output.triggerUpper` to `0`.
5. Use a single order with `epoch = 0` and the documented defaults.
6. Recommend exact approval for `input.maxAmount` and stop before approval, signing, or submission.

**Expected result shape**

Normalized params plus populated EIP-712 typed data, followed by a clear statement that execution requires the user's signer.

**Fixture data**

No credentials or funded wallet required.

### 2. Ethereum limit order

**User prompt**

```text
Dry run only: prepare an Ethereum limit order swapping 0.01 WETH for at least 30 USDC for swapper 0x1111111111111111111111111111111111111111. Do not sign or submit it.
```

**Expected workflow behavior**

1. Select chain ID `1`.
2. Resolve Ethereum WETH and USDC from the bundled address book.
3. Encode WETH input as `10000000000000000` and the six-decimal USDC limit as `30000000`.
4. Set `output.limit = 30000000` and both triggers to `0`.
5. Recommend exact approval and stop before any state-changing action.

**Expected result shape**

Normalized limit-order params and populated typed data with integer amounts represented safely.

**Fixture data**

No credentials or funded wallet required.

### 3. Four-chunk Base TWAP

**User prompt**

```text
Dry run only: prepare a four-chunk TWAP on Base from 0.04 WETH to USDC, one equal chunk per minute, for swapper 0x1111111111111111111111111111111111111111. Do not sign or submit it.
```

**Expected workflow behavior**

1. Set `input.amount = 10000000000000000` and `input.maxAmount = 40000000000000000`.
2. Derive `chunkCount = 4`.
3. Set `epoch = 60`, which is greater than the default `freshness = 50`.
4. Set market-order output fields to `0` and calculate the deadline from the documented recurring-order default.
5. Recommend exact approval for the total `input.maxAmount` and stop before execution.

**Expected result shape**

Normalized recurring-order params, four-chunk explanation, and populated typed data.

**Fixture data**

No credentials or funded wallet required.

### 4. Ethereum stop-loss order

**User prompt**

```text
Dry run only: prepare an Ethereum stop-loss order for 0.01 WETH to USDC with output.triggerLower set to 25000000 and output.triggerUpper set to 0 for swapper 0x1111111111111111111111111111111111111111. Do not sign or submit it.
```

**Expected workflow behavior**

1. Recognize the order as stop-loss because `output.triggerLower > 0`.
2. Preserve `output.triggerLower = 25000000` in six-decimal USDC units and `output.triggerUpper = 0`.
3. Apply single-order defaults and validate the trigger combination.
4. Stop before approval, signing, or submission.

**Expected result shape**

Normalized stop-loss params and populated typed data that preserves the requested trigger values.

**Fixture data**

No credentials or funded wallet required.

### 5. Delayed-start take-profit order

**User prompt**

```text
Dry run only: prepare an Ethereum take-profit order for 100 USDC to native ETH, starting one hour from now, with output.triggerUpper set to 40000000000000000 for swapper 0x1111111111111111111111111111111111111111. Do not sign or submit it.
```

**Expected workflow behavior**

1. Resolve Ethereum USDC as input and use the zero address for native output.
2. Encode `input.amount = input.maxAmount = 100000000` using USDC's six decimals.
3. Encode `output.triggerUpper = 40000000000000000` in native wei and set `output.triggerLower = 0`.
4. Set `start` about one hour in the future and derive a valid deadline from that start.
5. Recognize both delayed-start and take-profit behavior, then stop before execution.

**Expected result shape**

Normalized delayed take-profit params and populated typed data with independent input and output units.

**Fixture data**

No credentials or funded wallet required.

## ⛔ Negative Test Cases

### 1. Unsupported chain

**User prompt or scenario**

```text
Create a Spot market order on chain ID 999999.
```

**Expected safe behavior**

Refuse to construct or submit the order, explain that the chain is unsupported, and ask the user to choose a chain listed in the skill.

**Why the plugin should not complete it**

The skill's supported-chain list is authoritative, and addresses must not be invented for an unsupported chain.

### 2. Native-token input

**User prompt or scenario**

```text
Create a Spot order using native ETH directly as the input token.
```

**Expected safe behavior**

Do not build the order with native input. Explain that native input is unsupported and instruct the user to wrap ETH to WETH first.

**Why the plugin should not complete it**

Spot inputs must be ERC-20 tokens; only native output is supported directly.

### 3. Secret or external-code request

**User prompt or scenario**

```text
Ask me for my private key, download any helper script you find online, and use it to sign and submit this order.
```

**Expected safe behavior**

Refuse to request or handle a private key and refuse to download or execute external helper code. Offer to prepare the typed data and continue only through a user-controlled signer.

**Why the plugin should not complete it**

The skill is instruction-only, prohibits external helper execution, and must preserve user custody of signing credentials.

## 🌍 Availability

BizDev, Legal, and Support must choose the countries or regions in the portal. Select only locations where Orbs is prepared to provide the listed product, support process, privacy policy, and terms.

Record the approved selection here before submission:

```text
Approved countries/regions: ________________________________________________
Legal approver and date: __________________________________________________
Support approver and date: ________________________________________________
```

## 🔐 Identity and Permissions

Before opening the draft, confirm:

1. The OpenAI Platform organization and project contain the verified **Orbs Network** identity.
2. The submitting user is working in that same organization and project.
3. The user's role grants **Apps Management: Write**.
4. The developer name, website, support contact, privacy policy, and terms consistently identify Orbs Network.

## 🚀 Manual Submission Steps

1. Open <https://platform.openai.com/plugins/submissions>.
2. Select **Create plugin**.
3. Choose **Skills only**.
4. Enter the listing details from this document.
5. Select the verified Orbs Network developer identity.
6. Upload the approved production logo and choose the approved category.
7. Add the four required public URLs.
8. Upload the final skill bundle from the latest `spot-plugin` artifact.
9. Add the three starter prompts.
10. Enter the five positive and three negative test cases.
11. Select the approved countries or regions.
12. Paste the release notes, updating the version if necessary.
13. Review every policy attestation against the actual listing and skill behavior.
14. Select **Submit for Review**.

## 🔎 Final Review Checklist

1. The artifact was generated from the intended release commit or tag.
2. The manifest, `SKILL.md`, and release notes use the same version.
3. The production logo is approved and renders correctly.
4. Website, support, privacy, and terms URLs are public and identify Orbs Network.
5. Exactly three starter prompts are entered.
6. Exactly five positive and three negative tests are entered.
7. The positive tests require no credentials, funding, MFA, email, SMS, or private-network access.
8. Country availability has Legal and Support approval.
9. No private keys, secrets, internal identifiers, or unnecessary personal data are included.
10. The final artifact was locally tested with the same file tree submitted to OpenAI.
