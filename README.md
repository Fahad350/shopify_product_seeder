# Shopify Product Seeder

A small Ruby on Rails app that connects to a Shopify development store with the
**client-credentials grant** and imports three products from
[DummyJSON](https://dummyjson.com/products) using the **Shopify Admin GraphQL API**.
Each product is created with its details, **exactly two variants** and an **image**.
Seeding is **idempotent**: running it again skips products that already exist.

- **Settings page**: shop domain, client ID, client secret, connection status
- **Dashboard**: Seed Store button, processing state, created / updated / skipped / failed
  counts, and per-product results including GraphQL error messages
- **Products pages** (read-only): the seeded products read live from Shopify, and a detail
  page per product showing its two variants with price and SKU

---

## Requirements

| | Version |
|---|---|
| Ruby | 3.3.8 (see `.ruby-version`) |
| Rails | 8.1 |
| PostgreSQL | 14 or newer |
| Shopify | A development store and a custom app with `read_products` and `write_products` scopes |

No other services are needed: no Redis, background workers or JavaScript build step.

## Setup

```bash
git clone <repo-url> shopify_product_seeder
cd shopify_product_seeder
bundle install

# 1. Local environment (database connection, API version)
cp .env.example .env          # then edit DB_* values for your PostgreSQL

# 2. Encryption keys for the stored client secret
#    The repo's config/credentials.yml.enc needs the author's master key, so create your own:
rm config/credentials.yml.enc
bin/rails db:encryption:init  # prints three keys
EDITOR="nano" bin/rails credentials:edit
#    paste the printed `active_record_encryption:` block, save and close

# 3. Database
bin/rails db:prepare

# 4. Run
bin/rails server
```

Open <http://localhost:3000>, go to **Settings**, enter your store's credentials and click
**Save Settings**. The status should change to **Connected**.

### Shopify app setup

1. In the Shopify Partner Dashboard, create a **development store**.
2. Create an app for that store and give it the Admin API scopes **`read_products`** and
   **`write_products`**.
3. Install the app on the development store.
4. Copy the app's **Client ID** and **Client secret** into the Settings page.

The app uses the client-credentials grant (`POST /admin/oauth/access_token` with
`grant_type=client_credentials`). This grant works only for an app installed on a store
in the same organization as the app.

## Usage

1. Open **Dashboard** and click **Seed Store**.
   - The first run creates 3 products: **Created 3**.
2. Click **Seed Store** again.
   - Nothing is duplicated: **Skipped 3**.
3. Each result row shows the product's image and links to the product in the Shopify admin.
   Images are read live from Shopify. A just-created image takes a few seconds to process, so
   its thumbnail shows a spinner and the "Last run" card refreshes itself (every 3 seconds, up
   to 4 times) until the image is ready. Products deleted in Shopify are removed from the table, like on the Products page.
4. Open **Products** to see the seeded products, then click one to see its **two variants**
   (Standard and Premium) with price, SKU and image.

## How it works

```
SettingsController ──► ShopSetting (encrypted secret)
ProductSeedsController ──► Shopify::ProductImporter
                              ├─ DummyJson::ProductFetcher   GET dummyjson.com/products?limit=3
                              └─ Shopify::GraphqlClient      POST /admin/api/2026-10/graphql.json
                                   └─ Shopify::TokenService  client-credentials token, Rails.cache
ProductsController ──► Shopify::ProductCatalog (read-only) ──► Shopify::GraphqlClient
```

| File | Responsibility |
|---|---|
| `app/models/shop_setting.rb` | Single settings row; `client_secret` encrypted with Active Record Encryption |
| `app/services/shopify/token_service.rb` | Requests the token and caches it in `Rails.cache` until 5 min before `expires_in` |
| `app/services/shopify/graphql_client.rb` | Sends GraphQL requests; on **HTTP 401** refreshes the token and **retries once**; turns HTTP, timeout and top-level GraphQL errors into readable messages with secrets removed |
| `app/services/dummy_json/product_fetcher.rb` | Fetches the 3 source products |
| `app/services/shopify/product_importer.rb` | Idempotent import, per-product results, concurrency lock |
| `app/models/seed_run.rb` | Stores each run's status, counts and results for the dashboard |
| `app/services/shopify/product_catalog.rb` | Read-only: lists products tagged `seeded` and loads one product with its variants, live from Shopify |
| `app/controllers/products_controller.rb` | Products list and product detail pages; only products seeded by this app can be opened |

### Product creation

Each product is written with a single **`productSet`** mutation (`synchronous: true`),
which is Shopify's recommended way to create a product with its options, variants and media:

- option **Edition** with values **Standard** and **Premium**, giving exactly two variants
- variant prices: Standard = DummyJSON price, Premium = price × 1.25
- compare-at (original) price from `discountPercentage`: price ÷ (1 − discount), so Shopify
  shows the variant as on sale
- SKUs: `<DummyJSON SKU>-STD` and `<DummyJSON SKU>-PRM`
- barcode: DummyJSON `meta.barcode` on the Standard variant, stored without a barcode type
  (DummyJSON's codes are not valid EANs and fail Shopify's checksum)
- weight: DummyJSON `weight` on both variants, stored in kilograms
- image: the DummyJSON `thumbnail`, passed in `files`
- vendor from `brand`, product type from `category`; tags `dummyjson` and `seeded` plus the
  DummyJSON `tags`
- Shopify **Category** (Standard Product Taxonomy) from `category` through a small verified map
  (`beauty` → Health & Beauty); unmapped categories leave it empty rather than guess, because
  Shopify's taxonomy search is fuzzy
- not imported: `stock`, because Shopify inventory needs the `read_locations` and
  `write_inventory` scopes, and this app uses only `read_products` and `write_products`

### Duplicate prevention (idempotency)

- On first run the app creates a product metafield definition, `seeder.dummyjson_id`, of type
  **`id`** with the **unique values** capability.
- Each product is written with
  `productSet(identifier: { customId: { namespace: "seeder", key: "dummyjson_id", value: "<id>" } })`.
  This upserts by DummyJSON ID, so **Shopify itself rejects a second product with the same ID**.
- Before writing, the app looks the product up with `productByIdentifier`:

| Found in Shopify? | Result |
|---|---|
| No | **created** |
| Yes, with 2 variants and an image | **skipped**, no write |
| Yes, but incomplete (e.g. an earlier run failed partway) | **updated**, repaired in place |
| Error | **failed**, with the `userErrors` or HTTP message; the remaining products continue |

**Concurrency:** the whole run takes a PostgreSQL advisory lock (`pg_try_advisory_lock`).
A second click while a seed is running shows "A seed is already running" instead of
starting in parallel. The unique metafield is a second safeguard on Shopify's side.

### Token handling

- The token is cached in `Rails.cache`, keyed by shop domain and client ID, and reused until
  5 minutes before it expires. No token request is made per GraphQL call.
- **HTTP 401** on a GraphQL request: the cached token is discarded, a new one is requested,
  and the request is **retried once**. A second 401 stops with a clear error.
- An invalid client ID or secret shows "Shopify rejected the credentials". On the Settings
  page, saving shows "Settings saved, but the connection failed" with the reason.

## Security

- The client secret is **encrypted at rest** with Active Record Encryption and never shown on
  the page again. Leaving the field blank keeps the stored secret.
- `secret` and `token` parameters are **filtered from logs** (`config/initializers/filter_parameter_logging.rb`).
- Error messages are **sanitized**: any access token or client secret is replaced with `[FILTERED]`.
- No secrets are in the repository. `.env` and `config/master.key` are git-ignored.
- `bin/brakeman` reports 0 warnings and `bin/bundler-audit` reports 0 known vulnerabilities.

## Tests

```bash
bin/rails db:test:prepare
bin/rails test
```

69 tests run in about one second. **No network is used**: WebMock blocks all real HTTP, and
`test/support/fake_shopify.rb` is a small in-memory fake of the GraphQL endpoint. The tests
use their own encryption keys, so they **do not need `config/master.key`**.

| Area | What is tested |
|---|---|
| Token service | client-credentials request; caching (one request for many calls); expiry; refresh; invalid credentials; timeouts |
| GraphQL client | **401 → refresh → exactly one retry**; second 401 stops; top-level errors; 403/404/429/5xx; timeouts; secrets removed from errors |
| Importer | 3 created with 2 variants and an image; **second run skips all and writes nothing**; repair of partial imports; `userErrors` recorded and run continues; failed product recovered on next run; wrong metafield type; DummyJSON outage; **concurrent run blocked** |
| Settings | secret encrypted in DB, never rendered, filtered from logs; Connected/Failed status; validation |
| Dashboard | counts and results shown; `userErrors` shown in the UI; live Shopify thumbnails, with a fallback when Shopify is unreachable; products deleted in Shopify removed from the table (empty state if all were deleted); spinner while a new image is processing |
| Products pages | list of seeded products; detail page with both variants, prices and SKUs; unknown or non-seeded product; Shopify errors shown instead of crashing |

Code quality: `bin/rubocop` (0 offenses) and `bin/brakeman` (0 warnings).

**Continuous integration:** GitHub Actions (`.github/workflows/ci.yml`) runs Brakeman,
bundler-audit, the JavaScript dependency audit, RuboCop and the full test suite on every push
to `main` and on pull requests.

## Design decisions

- **No Shopify gem.** A thin `Net::HTTP` client (about 80 lines) keeps dependencies minimal and
  makes the token and retry behaviour easy to see.
- **Synchronous seeding.** Three products take a few seconds, so the work runs in the request
  with a disabled button and "Seeding…" state, and no job queue is needed. For larger imports
  this would move to a background job (Active Job / Solid Queue).
- **Upsert by custom ID** instead of searching by title or handle. The ID never changes and
  Shopify enforces its uniqueness.
- **Single store.** `ShopSetting` is one row, matching the brief (no multi-tenant support).
- **Plain CSS and Rails partials for the UI.** No UI framework or CSS build step; views are
  split into small partials (sidebar, stat card, result row, connection card, and so on).
- **Products pages read live from Shopify.** They store nothing locally, so they always match
  the store, and they are read-only because editing belongs in the Shopify admin.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `SHOPIFY_API_VERSION` | `2026-10` | Admin API version (current stable) |
| `DB_HOST` / `DB_PORT` | `localhost` / `5432` | PostgreSQL connection |
| `DB_USERNAME` / `DB_PASSWORD` | (none) | PostgreSQL credentials |
