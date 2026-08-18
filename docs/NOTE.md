# Catatan Non-Coding — Sebelum Deploy ke Testnet/Mainnet

Checklist hal-hal yang **bukan coding**, tapi wajib/perlu dilakukan manual (akun, klik-klik di browser, funding) sebelum atau saat integrasi FE ke smart contract dan deploy ke testnet.

## Wajib sebelum bisa deploy ke Base Sepolia

- [ ] **RPC URL provider** — buat akun ke node provider (Alchemy/Infura/QuickNode, atau RPC publik Base Sepolia), isi `BASE_SEPOLIA_RPC_URL` di `smart-contract/.env`. Tanpa ini `forge script --rpc-url` tidak bisa jalan.
- [ ] **Testnet ETH** — ambil dari faucet (Coinbase faucet, atau bridge dari Sepolia ETH) buat: gas deploy contract, fund VRF subscription, testing beli tiket dari beberapa wallet.
- [ ] **Chainlink VRF v2.5 subscription** — buka [vrf.chain.link](https://vrf.chain.link), connect wallet, create subscription, **fund pakai native ETH** (bukan LINK — contract pakai `nativePayment: true`). Hasilnya jadi `SUBSCRIPTION_ID` env var pas deploy.
- [ ] **Deployer wallet terpisah** — `cast wallet import lottery-deployer --interactive`, jangan private key plaintext di `.env`.

## Sering kelewat — Chainlink Automation registration

> ⚠️ **Sudah tidak berlaku (Agustus 2026):** Chainlink Automation v2.1 testnet sunset 24 Juni 2026, dan Gelato (alternatif berikutnya) juga sudah deprecated di platform lamanya. Draw otomatis di Base Sepolia sekarang dipicu lewat GitHub Actions cron — lihat `docs/AUTOMATION.md`. Poin di bawah dibiarkan sebagai riwayat.

- [ ] **Daftarkan upkeep di [automation.chain.link](https://automation.chain.link)**, arahkan ke alamat contract Lottery yang sudah dideploy, fund upkeep-nya (LINK atau native tergantung network support).
  - Tanpa ini, draw **tidak akan pernah otomatis** — `performUpkeep` contract memang sengaja tanpa access control (biar node Automation bisa call), tapi kalau tidak ada node terdaftar, tidak ada yang manggil sama sekali. Sama persis kondisi di Anvil sekarang (harus manual `cast send`).
  - Belum ada dokumentasi langkah ini di manapun di repo sebelum catatan ini.

## Opsional tapi disarankan

- [ ] **Basescan API key** — untuk `--verify` pas deploy, biar source code ter-publish & readable di block explorer.
- [ ] **Double-check alamat price feed** — `smart-contract/NOTE.md` (bagian Step 8) sudah flag: alamat ETH/USD price feed Base Sepolia dikasih langsung oleh project owner tanpa diverifikasi independen ke Basescan. Cek dulu itu beneran aggregator Chainlink asli sebelum fund apapun.
- [ ] **WalletConnect Cloud projectId** ([cloud.reown.com](https://cloud.reown.com)) — kalau nanti mau dukung wallet mobile (bukan cuma ekstensi browser). Di-skip dulu di `docs/PLAN.md` (pakai injected + Coinbase Wallet dulu).

## Ongoing, bukan sekali jalan

- [ ] **Jaga saldo VRF subscription & Automation upkeep tetap ada headroom.** Disebut eksplisit di `smart-contract/NOTE.md` sebagai "accepted operational risk" — kalau subscription VRF kehabisan saldo pas fulfillment, draw bisa **stuck** di `CALCULATING` tanpa cara recover sendiri. Harus dipantau selama lottery jalan, bukan sekali-set-lupa.

## Kalau nanti deploy frontend juga

- [ ] Set env vars (`NEXT_PUBLIC_*`) di dashboard hosting (Vercel dsb), bukan cuma di `.env.local` lokal.
