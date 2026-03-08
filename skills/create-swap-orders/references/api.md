# API

This skill defaults to the development relay base URL:

1. `https://agents-sink-dev.orbs.network`

## Create Order

1. Method: `POST`
2. Path: `/orders/new`
3. Default URL in this skill:
   `https://agents-sink-dev.orbs.network/orders/new`

### Request Body

The API expects:

1. `order`: the unsigned order payload from `typedData.message`
2. `signature`: split signature object with `v`, `r`, and `s`

The helper already prepares that shape in `prepared.json.submit.body`.

One important local constraint in this skill:

1. `start` is validated as a non-zero timestamp and defaults to the current unix timestamp.

## Query Orders

1. Method: `GET`
2. Path: `/orders`
3. Default URL in this skill:
   `https://agents-sink-dev.orbs.network/orders`

### Supported Query Parameters

1. `page`
2. `limit`
3. `swapper`
4. `recipient`
5. `hash`
6. `chainId`
7. `filler`
8. `exchange`
9. `inputToken`
10. `outputToken`
11. `view`

## Common Flows

Query all orders for a swapper on one chain:

`node skills/create-swap-orders/scripts/order_flow.js query --swapper <0x...> --chainId <id> --limit 10`

Query a specific order by hash:

`node skills/create-swap-orders/scripts/order_flow.js query --hash <0x...>`

## Responses

Create-order success returns:

1. `success: true`
2. `orderHash`
3. `signerAddress`
4. `signedOrder`

Create-order failure returns:

1. `success: false`
2. `message`
3. `orderHash`
4. `code`
5. `timestamp`
6. optional `signerAddress`

Order queries return paginated `orders`, plus pagination metadata such as:

1. `count`
2. `total`
3. `page`
4. `limit`
5. `totalPages`
6. `timestamp`
