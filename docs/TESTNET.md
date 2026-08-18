# Deploy Lottery ke Base Sepolia Testnet

## Context

`smart-contract/src/Lottery.sol` sudah selesai, teruji (64 test, 100% coverage di `src/`), dan sudah full-wired ke `frontend/` (semua 10 langkah `docs/PLAN.md` selesai, sudah dicoba jalan di Anvil lokal — beli tiket sukses). Sekarang saatnya deploy ke jaringan nyata pertama: **Base Sepolia**, supaya draw bisa beneran otomatis (Chainlink Automation + VRF asli, bukan `cast` manual kayak di Anvil), dan bisa didemokan lewat URL publik nantinya.

**Status yang sudah dicek (read-only, tidak ada yang diubah):**
- `smart-contract/.env`: `BASE_SEPOLIA_RPC_URL` sudah keisi URL Alchemy yang valid. `BASESCAN_API_KEY` masih kosong.
- `smart-contract/foundry.toml`: **belum ada section `[etherscan]`** — `--verify` tidak akan jalan tanpa ini.
- `cast wallet list`: kosong — belum ada deployer wallet di Foundry keystore.
- `HelperConfig.s.sol` sudah punya config Base Sepolia lengkap (vrfCoordinator, priceFeed — sudah kamu konfirmasi benar, interval 5 menit, keyHash, callbackGasLimit 500k, staleAfter 1 jam). `subscriptionId` masih placeholder `0`, wajib diisi via env var `SUBSCRIPTION_ID` pas deploy.
- `DeployLottery.s.sol` sudah otomatis: fund subscription 0.05 ETH native, deploy `Lottery`, daftarkan sebagai consumer — tinggal kasih `SUBSCRIPTION_ID` yang valid.

## Keputusan yang sudah disepakati

| Aspek | Pilihan |
|---|---|
| RPC provider | Sudah ada — Alchemy, di `smart-contract/.env` |
| Verifikasi contract | Ya, pakai `--verify` (Basescan) |
| Chainlink Automation | Ya, didaftarkan di plan ini juga — draw otomatis penuh |

## ⚠️ Isu keamanan yang wajib diperhatikan: jangan pakai ulang RPC key Alchemy di frontend

`NEXT_PUBLIC_*` di Next.js **di-bundle ke JavaScript sisi client** — siapa pun yang buka situsnya bisa lihat nilainya lewat DevTools/network tab. Kalau URL Alchemy yang sama (dengan API key-nya) dari `smart-contract/.env` ditaruh di `frontend/.env.local` sebagai `NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL`, API key itu jadi **publik** — siapa saja bisa comot dan pakai kuota Alchemy-mu sampai habis/limit.

**Solusi:** frontend pakai RPC **terpisah**, bukan yang sama dengan deploy script:
- **Default di plan ini:** RPC publik Base Sepolia (`https://sepolia.base.org`) — gratis, tanpa API key untuk dibocorkan, cukup buat skala demo/testnet.
- Kalau nanti butuh lebih reliable, bisa bikin App Alchemy **baru yang terpisah** khusus buat frontend (supaya kalau disalahgunakan, tinggal revoke key itu tanpa ganggu deploy script).

Alchemy key yang sudah ada di `smart-contract/.env` **tetap di situ saja**, dipakai forge script (server-side/CLI, tidak pernah masuk bundle browser) — aman.

## Pembagian kerja: siapa ngapain

Deploy ke jaringan nyata butuh wallet yang **menandatangani transaksi**, dan saya tidak pernah boleh pegang atau minta private key-mu — bahkan untuk testnet sekalipun (itu tetap kredensial finansial). Jadi:

**Saya kerjakan** (read-only / non-signing / lokal):
- Cek `forge build`/`test`/`fmt` bersih sebelum sentuh jaringan asli.
- Tambah section `[etherscan]` ke `foundry.toml` (config biasa, bukan secret).
- Siapkan command persis yang tinggal kamu copy-paste.
- Setelah kamu deploy dan kasih tau alamat contract-nya, saya `cast call` verifikasi read-only ke Base Sepolia, dan wiring `frontend/.env.local`.

**Kamu kerjakan sendiri di terminal/wallet-mu** (langkah yang butuh tanda tangan/private key):
1. Bikin wallet deployer baru (bukan wallet utama), import ke Foundry keystore.
2. Isi testnet ETH ke wallet itu lewat faucet.
3. Buat + fund VRF subscription di vrf.chain.link (connect wallet-mu sendiri di browser).
4. Jalankan command `forge script ... --broadcast` (nanti diminta masukin password keystore).
5. Daftarkan + fund Chainlink Automation upkeep di automation.chain.link.
6. Isi `BASESCAN_API_KEY` di `smart-contract/.env` (dari akun basescan.org kamu — boleh kasih ke saya buat ditulis, ini cuma rate-limit key buat servis verifikasi publik, bukan kredensial finansial).

---

## Langkah-langkah

### 1 — Prep lokal (saya kerjakan)
```bash
cd smart-contract
forge build && forge test -vvv && forge fmt --check
```
Tambah ke `foundry.toml`:
```toml
[etherscan]
base_sepolia = { key = "${BASESCAN_API_KEY}", chain = 84532 }
```

### 2 — Bikin & import deployer wallet (kamu, di terminal)
```bash
cast wallet new                       # kalau belum punya key testnet-only
cast wallet import lottery-deployer --interactive
```
Masukin private key waktu diminta — **jangan pernah paste private key ke chat/ke saya**, bahkan untuk testnet. Setelah ini, semua command `forge script`/`cast send` cukup pakai `--account lottery-deployer` (Foundry yang tanya password keystore-nya langsung ke kamu).

### 3 — Faucet testnet ETH (kamu)
```bash
cast wallet address --account lottery-deployer   # dapetin alamat publiknya
```
Isi lewat faucet (Coinbase Faucet, atau bridge dari Sepolia ETH ke Base via bridge resmi). Siapin minimal **~0.2 ETH testnet** — buat funding subscription (0.05 ETH otomatis dari script), gas create sub + deploy + add consumer + verify, plus buffer testing beli tiket nanti.

### 4 — Buat & fund VRF v2.5 subscription (kamu, browser)
Di [vrf.chain.link](https://vrf.chain.link):
- Connect wallet **yang sama** dengan deployer di langkah 2.
- Create subscription, **fund pakai native ETH** (bukan LINK — contract kita pakai `nativePayment: true`).
- Catat **Subscription ID** yang ditampilkan UI (ini ID asli, aman dipakai — beda dengan mock Anvil yang punya masalah subId-dari-simulasi-tidak-valid; UI di sini menampilkan ID final langsung, tidak lewat simulasi forge).

> Kenapa lewat UI, bukan `forge script Interactions.s.sol:CreateSubscription` kayak di Anvil? Karena belum ada yang mengonfirmasi apakah coordinator VRF asli (bukan mock) punya masalah simulasi-vs-broadcast subId yang sama kayak `VRFCoordinatorV2_5Mock` (sudah didokumentasikan `NOTE.md` makan waktu debug lama untuk kasus mock). UI resmi Chainlink menghindari risiko itu sepenuhnya.

### 5 — Deploy (kamu jalankan, command sudah saya siapkan)
```bash
cd smart-contract
SUBSCRIPTION_ID=<id dari langkah 4> forge script script/DeployLottery.s.sol:DeployLottery \
  --rpc-url $BASE_SEPOLIA_RPC_URL --account lottery-deployer --broadcast --verify
```
Script ini otomatis: fund subscription +0.05 ETH, deploy `Lottery`, daftarkan sebagai consumer VRF. `--verify` jalan otomatis pakai `BASESCAN_API_KEY` dari `.env` (lewat config `[etherscan]` langkah 1).

**Kasih saya:** alamat contract `Lottery` yang di-return script-nya (dan/atau `broadcast/DeployLottery.s.sol/84532/run-latest.json`).

### 6 — Verifikasi deploy (saya kerjakan, read-only)
```bash
cast call <lottery> "getLotteryState()(uint8)" --rpc-url $BASE_SEPOLIA_RPC_URL
cast call <lottery> "getTicketPriceInWei(uint8)(uint256)" 0 --rpc-url $BASE_SEPOLIA_RPC_URL
cast call <lottery> "getNextDrawTime()(uint256)" --rpc-url $BASE_SEPOLIA_RPC_URL
```
Plus baca `blockNumber` dari receipt di `run-latest.json` buat `NEXT_PUBLIC_LOTTERY_DEPLOY_BLOCK_84532`. Kamu tinggal cek sendiri tab "Contract" di Basescan buat pastiin source code ke-verify hijau.

### 7 — Daftar Chainlink Automation (kamu, browser)

> ⚠️ **Sudah tidak berlaku (Agustus 2026):** Chainlink Automation v2.1 testnet sunset 24 Juni 2026. Gelato (alternatif yang dicoba berikutnya) juga sudah deprecated di platform lamanya. Draw otomatis sekarang dipicu lewat GitHub Actions cron — lihat `docs/AUTOMATION.md`. Langkah di bawah ini dibiarkan sebagai riwayat, jangan diikuti.

Di [automation.chain.link](https://automation.chain.link):
- Connect wallet, register upkeep tipe **Custom Logic** (contract kita sudah implement `AutomationCompatibleInterface`, UI bakal auto-detect `checkUpkeep`/`performUpkeep`).
- Target: alamat `Lottery` dari langkah 5.
- Gas limit: kasih buffer generous (misal 1.000.000) — `performUpkeep` manggil `requestRandomWords` yang butuh gas lumayan.
- Fund upkeep (native ETH kalau didukung registry Base Sepolia, atau LINK — UI bakal kasih tau opsi yang tersedia).
- Kasih nama, register.

### 8 — Wiring frontend (saya kerjakan)
Update `frontend/.env.local`:
```
NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
NEXT_PUBLIC_LOTTERY_ADDRESS_84532=<alamat dari langkah 5>
NEXT_PUBLIC_LOTTERY_DEPLOY_BLOCK_84532=<block dari langkah 6>
```
Restart dev server, kamu tinggal switch network wallet ke Base Sepolia dan coba lagi alur yang sama kayak di Anvil (connect, lihat pool/harga real, beli tiket) — bedanya sekarang draw bakal jalan **beneran otomatis** tanpa `cast` manual.

---

## Verifikasi end-to-end

| # | Cek | Cara |
|---|---|---|
| 1 | Contract bersih | `forge build && forge test -vvv && forge fmt --check` sebelum deploy |
| 2 | Deploy sukses | Return value script + `run-latest.json` ada alamat `Lottery` |
| 3 | Config on-chain benar | `cast call` langkah 6 cocok sama `HelperConfig.s.sol` (state OPEN, harga wajar, next draw ~5 menit ke depan) |
| 4 | Verified di explorer | Tab "Contract" Basescan Sepolia hijau/verified |
| 5 | ~~Automation aktif~~ | Digantikan GitHub Actions cron — lihat `docs/AUTOMATION.md` |
| 6 | Frontend real | Browser connect ke Base Sepolia, data sama dengan hasil `cast call` |
| 7 | Draw otomatis | Tunggu 5 menit (interval Base Sepolia) setelah ada 1 tiket dibeli, cek `WinnerSection` — harusnya muncul sendiri lewat workflow cron (`docs/AUTOMATION.md`), tanpa `cast` manual |

## Yang TIDAK dikerjakan di sini

- Deploy ke Base **mainnet** — ini baru testnet.
- Ganti RPC frontend ke Alchemy khusus — pakai RPC publik dulu, upgrade belakangan kalau perlu.
- Rotate/ganti API key Alchemy yang sudah ada di `smart-contract/.env` — itu tetap aman dipakai server-side, tidak perlu diganti.
