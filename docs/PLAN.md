# Rencana: Wiring Lottery Contract → Frontend Next.js

## Konteks

`smart-contract/src/Lottery.sol` sudah selesai dan teruji (63 test, 100% coverage di `src/`), tapi `frontend/` masih scaffold visual murni: **tidak ada satu pun dependency web3 terpasang**, dan setiap angka yang tampil adalah mock hardcoded — `$500000` dan `150.25 ETH` di `HeroSection.tsx:27,36`, countdown statis `00:23:30:56` di `WinnerSection.tsx:99`, alamat wallet palsu `"1AAa...AaA1"` di `Navbar.tsx:5`, dan 10 baris riwayat pemenang fiktif di `WinnerSection.tsx:6-77`.

Tujuan: menghubungkan UI yang sudah ada ke contract sungguhan lewat wagmi + viem, sehingga semua data dibaca on-chain dan user bisa benar-benar `buyTicket` serta `claimPrize`.

Tiga hal yang bukan sekadar "ganti angka":

1. **UI single-price vs contract 3-tier.** Tombol `HeroSection.tsx:43` berbunyi `PARTICIPATE FOR 0.01 ETH` (satu harga, tanpa `onClick`), padahal `buyTicket(Tier)` butuh pilihan tier. Chip `$1/$5/$10` di baris 56 yang sekarang dekoratif dipromosikan jadi selector aktif.
2. **Tabel riwayat memakai skema "6 winning numbers" yang tidak ada di contract.** Contract memilih 1 alamat pemenang per tier, bukan mencocokkan angka. Kolom diganti agar jujur ke data on-chain.
3. **`claimPrize()` belum punya UI sama sekali.** Ini jalur pemulihan dana saat push payout gagal — bukan fitur opsional.

## Keputusan yang sudah disepakati

| Aspek | Pilihan |
|---|---|
| Jaringan | Anvil (31337) + Base Sepolia (84532), dengan chain switcher |
| Wallet UI | RainbowKit, di-theme gelap agar cocok desain |
| ABI sync | `@wagmi/cli` + plugin `foundry`, generate dari `../smart-contract` |
| Scope | Penuh: read + `buyTicket` + `claimPrize` |
| Riwayat pemenang | Kolom asli sesuai contract, data dari event `Winner` via `getLogs` |
| Nomor round | Tambah getter `getRound()` ke `Lottery.sol` lalu redeploy |
| WalletConnect | Belum ada projectId — injected + Coinbase dulu |
| Base Sepolia | Config siap, alamat dari env yang boleh kosong; deploy menyusul |

## Status lingkungan (terverifikasi)

- Foundry 1.7.1, Node v22.16.0, npm 10.9.2.
- **Anvil sedang tidak berjalan** → alamat deploy lama (`0xDc64a1…F6C9`) sudah basi, wajib deploy ulang.
- Belum ada deployment Base Sepolia (folder `broadcast/…/84532` tidak ada).
- ABI ada di `smart-contract/out/Lottery.sol/Lottery.json`, tapi `out/` gitignored.

---

## Struktur file yang akan dibuat

```
frontend/
  wagmi.config.ts                       # @wagmi/cli, plugin foundry
  .env.example                          # template (butuh negasi di .gitignore)
  lib/
    generated.ts                        # HASIL GENERATE wagmi cli — di-commit
    wagmi.ts                            # createConfig: chains, connectors, transports, ssr
    contracts.ts                        # peta alamat + deploy block per chain
    tiers.ts                            # Tier enum ↔ label & harga USD
    format.ts                           # formatEther, USD 18-desimal, truncate, countdown
    errors.ts                           # decode custom error → pesan Indonesia
  hooks/
    useLotteryAddress.ts
    useLotteryData.ts
    useTicketPrice.ts
    useBuyTicket.ts
    useClaimPrize.ts
    useWinnerHistory.ts
    useCountdown.ts
  components/
    providers/Providers.tsx             # 'use client'
    wallet/ConnectWalletButton.tsx      # 'use client'
    lottery/TierSelector.tsx
    lottery/BuyTicketButton.tsx
    lottery/ClaimPrizeBanner.tsx
    lottery/TxStatusToast.tsx
```

Semua UI baru **wajib memakai class `.card` dan `.btn-color`** yang sudah ada di `app/globals.css:34-49`, bukan bikin gaya sendiri.

---

## Langkah implementasi

### 1 — Tambah `getRound()` ke contract

`smart-contract/src/Lottery.sol`: sisipkan setelah `getLotteryState()` (baris 190-192), mengikuti gaya NatSpec `/// @notice` satu baris yang dipakai getter lain:

```solidity
/// @notice Returns the current round number.
function getRound() external view returns (uint256) {
    return s_round;
}
```

Test di `test/LotteryTest.t.sol`: tambah `test_initialState_roundIsZero()` di grup `test_initialState_*` (dekat baris 126-134), dan tambahkan assertion round bertambah pada test draw Step-6 yang sudah ada (sekitar baris 284-320) — bukan bikin test draw baru dari nol.

**Verifikasi** (docs/CLAUDE.md mewajibkan benar-benar dijalankan, bukan diklaim):
```bash
cd smart-contract
forge build && forge test -vvv && forge fmt --check
forge coverage --report summary     # src/ harus tetap 100%
forge snapshot                       # laporkan delta, harusnya ~0 untuk fungsi lain
```

### 2 — Pasang dependency & naikkan target TS

```bash
cd frontend
npm i wagmi viem @tanstack/react-query @rainbow-me/rainbowkit
npm i -D @wagmi/cli
```

`frontend/tsconfig.json:3` — ubah `"target": "ES2017"` → `"ES2020"`. Wajib: viem memakai BigInt literal (`123n`), yang error di bawah ES2020.

`frontend/.gitignore` punya blanket `.env*` — tambahkan baris `!.env.example` agar template bisa di-commit.

### 3 — Generate ABI type-safe

`frontend/wagmi.config.ts`:

```ts
import { defineConfig } from '@wagmi/cli'
import { foundry } from '@wagmi/cli/plugins'

export default defineConfig({
  out: 'lib/generated.ts',
  plugins: [
    foundry({
      project: '../smart-contract',
      include: ['Lottery.sol/Lottery.json'],   // hanya Lottery, bukan mock/test/lib
      forge: { build: false },                  // build manual, agar generate tidak lambat
    }),
  ],
})
```

Tambah script `"wagmi": "wagmi generate"` di `package.json`. Jalankan `forge build` dulu, baru `npm run wagmi`.

**`lib/generated.ts` di-commit ke git**, karena `smart-contract/out/` gitignored — clone baru atau CI tanpa Foundry tidak akan bisa generate ulang.

### 4 — Config chain & alamat

`frontend/lib/wagmi.ts`:

```ts
export const config = createConfig({
  chains: [anvil, baseSepolia],
  connectors: [injected(), coinbaseWallet({ appName: 'Nirmala Lottery' })],
  transports: {
    [anvil.id]: http(process.env.NEXT_PUBLIC_ANVIL_RPC_URL),
    [baseSepolia.id]: http(process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL),
  },
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
})
```

RainbowKit dipakai hanya sebagai lapisan UI di atas config ini — **jangan pakai `getDefaultConfig()`**, karena itu memaksa WalletConnect `projectId` yang belum ada.

`frontend/lib/contracts.ts` — peta alamat per chain.

> **Jebakan penting:** `NEXT_PUBLIC_*` di-inline saat build, jadi **tidak bisa** diakses dinamis seperti `process.env['NEXT_PUBLIC_LOTTERY_ADDRESS_' + chainId]`. Setiap variabel harus ditulis literal, lalu baru dipetakan ke chainId.

```ts
const ADDRESSES = {
  [anvil.id]:       process.env.NEXT_PUBLIC_LOTTERY_ADDRESS_31337,
  [baseSepolia.id]: process.env.NEXT_PUBLIC_LOTTERY_ADDRESS_84532,
} as const
```

Kembalikan `undefined` (bukan throw) kalau kosong — Base Sepolia memang belum di-deploy.

`.env.example`:
```
NEXT_PUBLIC_ANVIL_RPC_URL=http://127.0.0.1:8545
NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL=
NEXT_PUBLIC_LOTTERY_ADDRESS_31337=
NEXT_PUBLIC_LOTTERY_ADDRESS_84532=
NEXT_PUBLIC_LOTTERY_DEPLOY_BLOCK_31337=
NEXT_PUBLIC_LOTTERY_DEPLOY_BLOCK_84532=
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=
```

### 5 — Provider tree

`app/layout.tsx` adalah Server Component, dan `<Navbar/>` (baris 28) juga server tapi memuat UI wallet. Keduanya harus berada di dalam provider.

Buat `components/providers/Providers.tsx` (`'use client'`) berisi `WagmiProvider` → `QueryClientProvider` → `RainbowKitProvider`, lalu di `app/layout.tsx:27-30` bungkus **`<Navbar/>` dan `{children}` sekaligus**.

- Import `@rainbow-me/rainbowkit/styles.css` di dalam `Providers.tsx`.
- Theme: `darkTheme({ accentColor: '#3b82f6', borderRadius: 'large' })` agar senada `.btn-color`.
- `QueryClient` dibuat via `useState(() => new QueryClient())`, bukan module-level, supaya tidak bocor antar request saat SSR.
- Hidrasi: layout jadi `async`, baca `(await headers()).get('cookie')`, teruskan ke `Providers`, lalu `cookieToInitialState(config, cookie)` → `initialState` pada `WagmiProvider`. Ini yang mencegah tombol connect "berkedip" dari disconnected ke connected.

`components/Navbar.tsx` — tambah `'use client'` di baris 1, ganti div palsu baris 59-66 dengan `<ConnectWalletButton/>` yang dibangun dari `ConnectButton.Custom` RainbowKit agar bentuknya tetap sama persis dengan desain sekarang (termasuk state salah-jaringan).

### 6 — Hooks

- `useLotteryData` — satu `useReadContracts` yang membatch `getPoolBalanceETH`, `getPoolBalanceUSD`, `getRound`, `getNextDrawTime`, `getLotteryState`, dan `getEntryCount` ×3.
  > **Multicall di Anvil:** batching butuh Multicall3. Cek dulu dengan `cast code 0xcA11bde05977b3631167028862bE2a173976CA11 --rpc-url http://127.0.0.1:8545` terhadap anvil yang berjalan. Kalau kosong, set `batch: { multicall: false }` pada transport anvil. Base Sepolia sudah punya Multicall3.
- **Strategi refresh:** `refetchInterval` 10 detik + invalidasi eksplisit lewat `queryClient.invalidateQueries` setelah transaksi sendiri terkonfirmasi, plus `useWatchContractEvent` untuk `TicketPurchased`/`Winner`. Jangan pakai `watch: true` (deprecated di wagmi v2).
- `useTicketPrice(tier)` — `getTicketPriceInWei`; ini bisa revert `Lottery__StalePrice`, jadi UI harus punya state error khusus, bukan sekadar loading selamanya.
- `useCountdown(nextDrawTime, state)` — tick 1 detik. Harus menangani batas undian:
  - `state === CALCULATING` → "Sedang mengundi…"
  - `now >= nextDrawTime` tapi masih OPEN → "Menunggu undian…" (Automation belum jalan / di anvil harus manual)
  - selain itu → hitung mundur normal

### 7 — Alur `buyTicket`

1. Quote `getTicketPriceInWei(tier)`.
2. Kirim dengan **buffer 2%** (`price * 102n / 100n`). Alasan: harga bisa bergeser antara quote dan eksekusi; kurang bayar → revert `Lottery__InsufficientPayment`, sedangkan lebih bayar **dikembalikan otomatis oleh contract** di transaksi yang sama (`Lottery.sol:103-107`). Feed ETH/USD Chainlink umumnya update pada deviasi 0.5%, jadi 2% memberi ruang aman tanpa membuat angka di wallet terlihat aneh.
3. `useSimulateContract` sebelum write — supaya `Lottery__NotOpen` / `Lottery__StalePrice` / kurang bayar muncul sebagai pesan di UI, bukan sebagai wallet popup yang gagal.
4. `useWriteContract` → `useWaitForTransactionReceipt` untuk state pending/confirming/success.
5. Tombol dinonaktifkan (dengan alasan yang terlihat) saat: belum connect, chain tidak didukung, chain didukung tapi alamat kosong, `state === CALCULATING`, atau simulasi gagal.

### 8 — Decode error jadi pesan Indonesia

`lib/errors.ts` — pakai `err.walk(e => e instanceof ContractFunctionRevertedError)` dari viem, baca `errorName`:

| Error | Pesan |
|---|---|
| `Lottery__NotOpen` | "Undian sedang berlangsung, pembelian tiket ditutup sementara." |
| `Lottery__InsufficientPayment(required, sent)` | Tampilkan selisihnya dalam ETH dari argumen error |
| `Lottery__StalePrice` | "Harga ETH/USD dari oracle sudah kedaluwarsa. Coba lagi sebentar lagi." |
| `Lottery__NothingToClaim` | "Tidak ada hadiah yang bisa diklaim." |
| `Lottery__RefundFailed` / `Lottery__ClaimFailed` | "Transfer ETH gagal — wallet-mu menolak menerima dana." |

Tangani juga `UserRejectedRequestError` secara terpisah supaya batal-oleh-user tidak tampil sebagai error merah.

### 9 — Riwayat pemenang dari event

`hooks/useWinnerHistory.ts` — `getLogs` untuk event `Winner`, di-anchor pada `NEXT_PUBLIC_LOTTERY_DEPLOY_BLOCK_*`.

- Anvil: `fromBlock = deployBlock`, satu panggilan cukup.
- Base Sepolia: RPC publik membatasi range `eth_getLogs` (~10k blok) — chunk mundur dari `latest` dalam jendela 9.000 blok sampai terkumpul N round atau menyentuh deployBlock.
- **Pengelompokan:** 3 event `Winner` dari satu draw selalu dipancarkan dalam transaksi yang sama (`Lottery.sol:257-259`), jadi grup berdasarkan `transactionHash` = 1 round.
- **Nomor round:** hitung mundur dari `getRound()` yang sekarang — draw terbaru = `round - 1`, sebelumnya `round - 2`, dst. Ini akurat tanpa harus scan penuh dari blok deploy.
  > Sudah diverifikasi di source: `s_round` **hanya** bertambah di `fulfillRandomWords` (`Lottery.sol:253`). Jalur skip di `performUpkeep` (`Lottery.sol:135-139`) memancarkan `DrawSkipped` dan langsung `return` tanpa menyentuh `s_round`. Artinya jumlah undian yang benar-benar menghasilkan pemenang selalu sama persis dengan nilai `getRound()` — hitung-mundur di atas tidak akan meleset gara-gara round kosong.

`components/WinnerSection.tsx` — ganti `historyData` (baris 6-77) dan struktur kolom jadi: **Round · Tier ($1/$5/$10) · Alamat pemenang (truncated) · Hadiah (ETH + USD) · link explorer**. Tambahkan state kosong ("belum ada undian") dan skeleton loading — sekarang tabel selalu me-render 10 baris tanpa cabang apa pun.

### 10 — Ganti data mock yang tersisa

- `HeroSection.tsx:27` `$500000` → `getPoolBalanceUSD()` (18 desimal, bagi `1e18`).
- `HeroSection.tsx:36` `150.25 ETH` → `formatEther(getPoolBalanceETH())`.
- `HeroSection.tsx:39` `DRAW #16` → `getRound()`.
- `HeroSection.tsx:56-63` chip `$1/$5/$10` → `<TierSelector/>` aktif (state tier terpilih), menampilkan harga ETH live per tier dan `getEntryCount` per tier.
- `HeroSection.tsx:42-44` tombol → `<BuyTicketButton/>` dengan label dinamis dari harga tier terpilih.
- `HeroSection.tsx:47-48` spacer kosong `h-56` → tempat `<ClaimPrizeBanner/>`, yang hanya muncul kalau `getClaimablePrize(address) > 0`.
- `WinnerSection.tsx:99` countdown → `useCountdown`.

---

## Runbook dev lokal

Anvil tidak punya Chainlink Automation, jadi undian harus dipicu manual.

```bash
# terminal 1
anvil

# terminal 2 — setup (dua langkah, wajib; lihat smart-contract/NOTE.md soal subId & blockhash)
cast rpc evm_mine --rpc-url http://127.0.0.1:8545
cd smart-contract
forge script script/Interactions.s.sol:CreateSubscription \
  --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> --broadcast
# baca subId ASLI dari broadcast/Interactions.s.sol/31337/run-latest.json
# (logs[0].topics[1] pada receipt createSubscription), plus alamat kedua mock

VRF_COORDINATOR=<addr> PRICE_FEED=<addr> SUBSCRIPTION_ID=<subId asli> \
  forge script script/DeployLottery.s.sol:DeployLottery \
  --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> --broadcast
```

Salin alamat Lottery + block number-nya ke `frontend/.env.local`.

Memicu undian manual:
```bash
cast rpc evm_increaseTime 31 --rpc-url http://127.0.0.1:8545
cast rpc evm_mine --rpc-url http://127.0.0.1:8545
cast send <lottery> "performUpkeep(bytes)" 0x --private-key <key> --rpc-url http://127.0.0.1:8545
# ambil requestId dari event DrawRequested, lalu:
cast send <coordinator> "fulfillRandomWords(uint256,address)" <requestId> <lottery> \
  --private-key <key> --rpc-url http://127.0.0.1:8545
```

> Kalau melompat waktu jauh (> `priceFeedStaleAfter` = 3 jam di anvil), mock price feed jadi stale dan `buyTicket` akan revert `Lottery__StalePrice`. Segarkan dengan `cast send <priceFeed> "updateAnswer(int256)" 200000000000`.

---

## Verifikasi end-to-end

| # | Langkah | Cara memastikan |
|---|---|---|
| 1 | Contract | `forge test -vvv` hijau, `forge coverage` `src/` tetap 100%, `forge fmt --check` bersih |
| 2 | Codegen | `lib/generated.ts` ada dan memuat `lotteryAbi`; `npx tsc --noEmit` bersih |
| 3 | Build FE | `npm run build` sukses, `npm run lint` bersih |
| 4 | Connect | Buka `localhost:3000`, connect MetaMask ke Anvil — Navbar menampilkan alamat asli, bukan `1AAa...AaA1` |
| 5 | Read | Pool, round, harga tiap tier, countdown cocok dengan hasil `cast call` langsung ke contract |
| 6 | Buy | Beli tiket tier $5 → tx sukses, `getEntryCount(1)` naik, pool bertambah, kelebihan bayar kembali ke wallet |
| 7 | Guard | Set state ke CALCULATING (lewat `performUpkeep`) → tombol beli mati dengan pesan yang benar |
| 8 | Draw | Picu undian manual → `WinnerSection` menampilkan baris round baru dengan alamat pemenang asli |
| 9 | Claim | Uji dengan wallet penerima yang gagal → banner klaim muncul, `claimPrize` berhasil menarik dana |
| 10 | Chain switch | Pindah ke Base Sepolia → UI menampilkan "belum tersedia di jaringan ini", tidak crash |

## Yang TIDAK dikerjakan

- Deploy ke Base Sepolia (menunggu VRF subscription) — hanya config-nya yang disiapkan.
- Indexer; riwayat dibaca langsung dari RPC.
- Tombol nav "DEX" dan "Crypto Price Tracker" di `Navbar.tsx:33-45` dibiarkan apa adanya — di luar scope.
