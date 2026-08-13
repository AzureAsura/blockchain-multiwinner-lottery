# Timeline Development Smart Contract Lottery

## Context

Spec sudah final di `lottery/PRD.md` (hasil diskusi: 1 tiket = 1 entry, dust ke tier bobot terbesar yang aktif, draw murni time-based, skip VRF kalau semua tier kosong, VRF v2.5 subscription). Scaffolding Foundry + `chainlink-brownie-contracts@1.3.0` sudah terpasang dan terverifikasi di `lottery/smart-contract/` — `src/`, `test/`, `script/` masih kosong.

Tahap ini: implementasi contract-nya, dikerjakan **bertahap step-by-step**, tiap step ditutup dengan verifikasi yang benar-benar dijalankan (bukan diklaim). Urutannya sengaja menaruh **matematika hadiah (Step 5)** sebelum integrasi VRF, karena itu bagian paling berisiko salah dan paling mudah dites terisolasi.

### Keputusan yang sudah dikunci user
| Topik | Keputusan |
|---|---|
| Payout | **Hybrid**: push dengan gas stipend tetap 30k, gagal → jatuh ke `claimable` |
| VRF funding | **Native ETH** (`nativePayment: true`) |
| Oracle guard | Cek **stale** (umur data) **dan** harga `<= 0` |
| Interval draw | Cepat untuk testing, **7 hari** untuk rilis → jadi constructor param, nilainya diatur `HelperConfig` per-chain |

### Konvensi kode (mengikuti `foundry-fund-me` milik user + CLAUDE.md)
- Custom error bergaya `Lottery__NamaError()`, **tanpa** `require` string.
- Prefix `s_` untuk storage, `i_` untuk immutable, `SCREAMING_CASE` untuk constant.
- NatSpec di semua fungsi `public`/`external`, visibility eksplisit, event di tiap fungsi yang mengubah state.
- Checks-Effects-Interactions di semua fungsi yang menyentuh ETH.

---

## Dua keputusan arsitektur yang perlu diketahui sebelum baca timeline

**1. Entry disimpan per-ronde, bukan di-`delete` tiap draw.**
```solidity
uint256 private s_round;
mapping(uint256 round => mapping(uint8 tier => address[])) private s_entries;
```
Alasannya penting: kalau entry disimpan di array biasa lalu di-`delete` tiap draw, biaya reset ikut membesar seiring jumlah peserta — **loop tak terbatas atas data yang dikendalikan user**. Kalau pesertanya banyak, reset bisa melampaui `callbackGasLimit` VRF dan bikin draw gagal permanen. Dengan mapping per-ronde, reset cukup `s_round++` — biayanya tetap, berapa pun jumlah peserta.

**2. Pool dilacak eksplisit lewat `s_prizePool`, bukan `address(this).balance`.**
Karena payout hybrid menyisakan hadiah yang belum diklaim di dalam contract, `address(this).balance` bukan lagi cerminan pool ronde berjalan. `s_prizePool` hanya berisi dana ronde aktif.

---

## Timeline

### Step 1 — `src/PriceConverter.sol`
Library konversi harga (pola sama seperti `foundry-fund-me/src/PriceConverter.sol`, tapi ditambah guard oracle).
- `getEthUsdPrice(AggregatorV3Interface feed, uint256 staleAfter)` → baca `latestRoundData()`, revert kalau `answer <= 0` (`Lottery__InvalidPrice`) atau `block.timestamp - updatedAt > staleAfter` (`Lottery__StalePrice`), lalu normalisasi 8 desimal → 18 desimal.
- `usdToWei(uint256 usdAmount18, uint256 ethUsdPrice18)` → jumlah wei yang setara.

**Verifikasi:** unit test pakai `MockV3Aggregator` (sudah tersedia di `@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol`, tidak perlu bikin mock sendiri) — harga normal, harga 0, harga negatif, data basi (majukan waktu pakai `vm.warp`), plus fuzz test konversi dengan `bound()`.

### Step 2 — Kerangka `src/Lottery.sol`
Belum ada logic transaksional. Isinya: `enum Tier {ONE, FIVE, TEN}`, `enum LotteryState {OPEN, CALCULATING}`, semua constant (`TIER_*_PRICE_USD` = `1e18`/`5e18`/`10e18`, bobot `15`/`35`/`50`), immutable (`i_priceFeed`, `i_interval`, `i_keyHash`, `i_subscriptionId`, `i_callbackGasLimit`, `i_priceFeedStaleAfter`), storage, kumpulan custom error, event, constructor (inherit `VRFConsumerBaseV2Plus`, yang sekaligus membawa `ConfirmedOwner` — **tidak perlu OpenZeppelin**).

Plus view function yang dibutuhkan FE — semuanya `view`, gratis dipanggil:
- `getTicketPriceInWei(Tier)` — untuk quote dropdown tier
- `getPoolBalanceETH()` / `getPoolBalanceUSD()` — tampilan "duit terkumpul"
- `getNextDrawTime()` → `s_lastDrawTimestamp + i_interval` — untuk countdown
- `getClaimablePrize(address)` — untuk banner "kamu menang"
- `getEntryCount(Tier)`, `getLotteryState()`

**Verifikasi:** `forge build` + test konstruktor (nilai immutable tersimpan benar, state awal `OPEN`, `getNextDrawTime()` masuk akal).

### Step 3 — `buyTicket(Tier tier) external payable`
Alur Approach B dari PRD: hitung ulang harga **on-chain** (abaikan quote FE), tolak kalau `msg.value` kurang, refund kelebihannya.
```
checks:  state == OPEN, harga dihitung ulang dari price feed, msg.value >= required
effects: s_entries[s_round][tier].push(msg.sender); s_prizePool += required; emit
interactions: refund (msg.value - required) ke msg.sender
```
Urutan CEI dipatuhi, jadi kalaupun penerima refund adalah contract yang re-entry ke `buyTicket`, state sudah konsisten dan dia sekadar beli tiket lagi secara sah — **tidak perlu** `nonReentrant`.

**Verifikasi:** unit test (bayar pas, bayar lebih → cek refund benar-benar diterima, bayar kurang → revert, beli saat state `CALCULATING` → revert, 1 wallet beli 3x → dapat 3 entry terpisah sesuai aturan PRD) + fuzz `msg.value` dengan `bound()`.

### Step 4 — `checkUpkeep` + `performUpkeep` (Chainlink Automation)
- `checkUpkeep` → `upkeepNeeded = (block.timestamp - s_lastDrawTimestamp >= i_interval) && state == OPEN`. Sesuai PRD: **tanpa** syarat minimum peserta.
- `performUpkeep` → validasi ulang kondisinya sendiri (jangan percaya `performData`, siapa pun bisa memanggil ini). Kalau total entry ketiga tier `== 0`: cukup `s_lastDrawTimestamp = block.timestamp`, emit `DrawSkipped`, selesai — **tanpa request VRF**. Kalau ada peserta: set state `CALCULATING`, `requestRandomWords` dengan `numWords: 3` dan `extraArgs` `nativePayment: true`.

Catatan kenapa timer tetap direset walau kosong: kalau tidak direset, pembeli tiket pertama setelah lama vakum akan langsung kena draw seketika (karena interval sudah lewat jauh) — tidak adil. Reset menghindari itu.

**Verifikasi:** test `checkUpkeep` false sebelum interval / true sesudah / false saat `CALCULATING`; `performUpkeep` revert saat belum waktunya; **skenario semua tier kosong → pastikan tidak ada request VRF sama sekali** (cek lewat `vm.recordLogs` atau `requestId` tidak berubah).

### Step 5 — Matematika hadiah (fungsi `internal pure`) ⭐ paling kritis
Dipisah sebagai fungsi murni supaya bisa difuzz habis-habisan tanpa perlu VRF:
```
1. Kumpulkan bobot tier yang punya peserta → totalActiveWeight
2. Tentukan tier aktif dengan bobot terbesar (15/35/50 semuanya beda, jadi tidak ada seri)
3. Untuk tiap tier aktif SELAIN yang terbesar: prize = pool * weight / totalActiveWeight
4. Tier terbesar: prize = pool - (jumlah yang sudah dialokasikan)
```
Langkah 4 itulah yang memenuhi syarat "habis terbagi tanpa dust" di PRD — sisa pembulatan otomatis nyantol ke tier bobot terbesar, persis seperti yang kamu putuskan.

**Verifikasi:** unit test untuk **ketujuh** kombinasi tier aktif (3 tier; 3 pasang; 3 tunggal) termasuk mencocokkan angka contoh di PRD (30/70, ~23/~77, ~41/~59, dan 1 tier = 100%). Lalu **fuzz test invarian utama: `jumlah semua hadiah == pool`, persis, untuk pool acak apa pun** — ini pembuktian klaim "tanpa dust".

### Step 6 — `fulfillRandomWords` + payout hybrid
```
effects dulu (semua sebelum ada transfer ETH):
  pool = s_prizePool; pilih 3 pemenang via randomWords[i] % entries[tier].length
  hitung hadiah (Step 5); simpan pemenang; s_prizePool = 0;
  s_round++; s_lastDrawTimestamp = block.timestamp; s_lotteryState = OPEN; emit
interactions:
  (bool ok,) = winner.call{value: prize, gas: 30_000}("");
  if (!ok) s_claimablePrize[winner] += prize;   // otomatis jadi bisa diklaim
```
Semua state direset **sebelum** transfer, jadi callback ini tidak mungkin dibuat macet: pemenang bermasalah paling banter membakar 30k gas lalu dananya pindah ke jalur klaim.

**Verifikasi:** test end-to-end pakai `VRFCoordinatorV2_5Mock` (`createSubscription` → `fundSubscriptionWithNative` → `addConsumer` → `fulfillRandomWordsWithOverride` untuk mengatur randomness secara deterministik). Kasus wajib: pemenang EOA menerima ETH langsung; **pemenang berupa contract yang menolak ETH → dana masuk `claimable`, draw tetap sukses**; tier kosong ter-skip dan bobotnya terdistribusi; `s_prizePool` jadi 0; lottery kembali `OPEN`.

### Step 7 — `claimPrize()`
CEI + nolkan saldo sebelum transfer; revert `Lottery__NothingToClaim()` kalau 0.

**Verifikasi:** klaim sukses, klaim dua kali → revert, **test reentrancy eksplisit** dengan contract penyerang yang memanggil balik `claimPrize()` saat menerima ETH → tidak boleh bisa menarik dobel.

### Step 8 — Script deployment
- `script/HelperConfig.s.sol` (pola sama dengan `foundry-fund-me/script/HelperConfig.s.sol`): per-chain config berisi `priceFeed`, `vrfCoordinator`, `keyHash`, `subscriptionId`, `callbackGasLimit`, `interval`, `staleAfter`. Interval: **lokal/Anvil 30 detik, Base Sepolia 5 menit, Base mainnet 7 hari**. Untuk chain lokal, deploy `MockV3Aggregator` + `VRFCoordinatorV2_5Mock` otomatis.
- `script/Interactions.s.sol`: `CreateSubscription`, `FundSubscription`, `AddConsumer`.
- `script/DeployLottery.s.sol`: rangkai semuanya, `vm.startBroadcast()`/`stopBroadcast()`, **tanpa private key hardcoded**.

⚠️ **Alamat kontrak Chainlink (price feed ETH/USD Base, VRF coordinator, keyHash) akan aku isi dengan mengambil dari dokumentasi resmi Chainlink saat step ini, bukan dari ingatan** — salah alamat di sini berarti contract deploy ke oracle yang salah. Kalau aku tidak bisa memverifikasinya, akan aku tandai `TODO` dan minta kamu isi, bukan aku tebak.

**Verifikasi:** `forge script DeployLottery` jalan sukses di Anvil lokal.

### Step 9 — Integration + invariant test
- Integration: satu ronde penuh (beberapa user beli lintas tier → `vm.warp` → `performUpkeep` → fulfill → cek saldo pemenang → ronde berikutnya jalan normal).
- Invariant (`test/invariant/`): properti solvensi — **`address(this).balance >= s_prizePool + total hadiah yang belum diklaim`**. Handler dengan aksi acak (beli tiket, majukan waktu, draw, klaim), ghost variable dijaga seminimal mungkin.

### Step 10 — Security pass & laporan akhir
Jalankan dan laporkan **angka aslinya**:
- `forge build`, `forge test -vvv`, `forge coverage`, `forge fmt --check`
- `forge snapshot` — laporkan gas nyata `buyTicket` dan `fulfillRandomWords`, sekaligus **membuktikan/mengoreksi estimasi gas hybrid yang aku sebutkan di chat** (angka itu masih estimasi opcode, belum terukur).
- `slither .` kalau tersedia — kalau tidak terinstall, akan aku bilang terus terang, bukan dilewati diam-diam.
- Telusuri ulang checklist keamanan CLAUDE.md satu per satu terhadap kode final.

---

## Catatan lingkup
Tidak ada fungsi pause, upgradeability, atau parameter admin yang bisa diubah-ubah — PRD tidak memintanya, dan tiap tambahan itu menambah attack surface (CLAUDE.md §2). Satu-satunya kekuasaan owner adalah yang otomatis terbawa dari `VRFConsumerBaseV2Plus` (`setCoordinator`). Kalau nanti kamu mau tombol darurat, itu keputusan terpisah yang perlu dibahas sendiri.
