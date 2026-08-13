# Frontend Plan — Lottery DApp

Referensi lengkap: apa yang FE perlu **tampilkan** (baca dari contract) dan apa yang FE bisa **hit** (kirim transaksi ke contract). Semua berdasarkan `smart-contract/src/Lottery.sol` yang sudah selesai & teruji (63 test, lihat `smart-contract/NOTE.md`).

Ini dokumen perencanaan fitur, bukan implementasi — belum ada kode FE yang ditulis.

---

## 1. Konsep dasar yang perlu dipahami sebelum desain UI

- **3 tier tiket**: `ONE` ($1), `FIVE` ($5), `TEN` ($10) — di kontrak ini `enum Tier { ONE, FIVE, TEN }`, jadi kalau manggil fungsi yang butuh parameter tier, kirim `0` / `1` / `2`.
- **Harga selalu dalam ETH (wei)**, dikonversi on-chain dari USD real-time. FE gak pernah hardcode harga — selalu query ke contract dulu.
- **2 status lottery**: `OPEN` (bisa beli tiket) dan `CALCULATING` (lagi proses draw, beli tiket ditolak). Di kontrak `enum LotteryState { OPEN, CALCULATING }` → `0` / `1`.
- **Sistem hadiah**: kalau transfer otomatis ke pemenang gagal (misal pemenangnya smart contract wallet aneh), dana **gak hilang** — nyangkut di "claimable balance" yang bisa ditarik manual. FE wajib punya UI buat ini, ini bukan fitur opsional.
- **Draw itu otomatis** (Chainlink Automation + VRF) — FE **gak pernah** manggil fungsi draw-nya sendiri. FE cuma nampilkan countdown & hasil.

---

## 2. Semua yang bisa FE "baca" (view function — gratis, gak makan gas)

| Fungsi | Return | Dipakai buat |
|---|---|---|
| `getTicketPriceInWei(Tier tier)` | `uint256` (wei) | Quote harga pas user pilih tier di dropdown, sebelum bayar |
| `getPoolBalanceETH()` | `uint256` (wei) | Tampilan "total pool terkumpul" dalam ETH |
| `getPoolBalanceUSD()` | `uint256` (USD, 18 desimal) | Tampilan "total pool terkumpul" dalam USD |
| `getNextDrawTime()` | `uint256` (Unix timestamp) | Countdown "draw berikutnya dalam ~X jam" |
| `getClaimablePrize(address user)` | `uint256` (wei) | Cek apakah user punya hadiah nyangkut yang belum diklaim → tampilkan banner "Kamu menang!" |
| `getEntryCount(Tier tier)` | `uint256` | Tampilan "sudah ada N peserta di tier ini" (opsional, buat transparansi) |
| `getLotteryState()` | `0` (OPEN) / `1` (CALCULATING) | Nentuin apakah tombol beli tiket aktif atau di-disable + tampilkan status "Draw sedang berlangsung" |

Semua ini **read-only**, dipanggil via `eth_call` (viem/wagmi `useReadContract` atau sejenisnya) — gratis buat user, gak perlu wallet connect sekalipun buat sekadar liat data (connect cuma perlu pas mau transaksi).

---

## 3. Semua yang bisa FE "hit" (transaksi — butuh wallet, makan gas)

| Fungsi | Parameter | Butuh `msg.value`? | Efek |
|---|---|---|---|
| `buyTicket(Tier tier)` | tier (0/1/2) | **Ya** — kirim `getTicketPriceInWei(tier)` + buffer kecil (sisa otomatis di-refund) | Daftar jadi peserta tier itu |
| `claimPrize()` | — | Tidak | Tarik `getClaimablePrize(msg.sender)` ke wallet user |

**Cuma 2 fungsi ini** yang FE perlu tombolnya. Gak ada fungsi admin/owner yang relevan buat FE (gak ada pause, gak ada withdraw manual, gak ada ubah parameter — sesuai desain, lihat `NOTE.md` soal keputusan "gak perlu emergency pause").

### Alur `buyTicket` (Approach B, dari PRD)
1. User pilih tier di dropdown.
2. FE panggil `getTicketPriceInWei(tier)` → tampilkan estimasi ETH.
3. User klik bayar → wallet kirim `buyTicket(tier)` dengan value = estimasi (+ buffer kecil, misal 1-2%, buat jaga-jaga harga bergerak antara quote dan konfirmasi).
4. Contract hitung ulang harga real-time saat itu juga — kalau kurang, transaksi revert (`Lottery__InsufficientPayment`); kalau lebih, sisanya otomatis balik ke wallet user di transaksi yang sama.

---

## 4. Event yang perlu di-*listen* (buat update real-time tanpa polling terus-menerus)

| Event | Data | Dipakai buat |
|---|---|---|
| `TicketPurchased(address buyer, Tier tier, uint256 amountPaid)` | pembeli, tier, jumlah dibayar | Update tampilan pool & entry count langsung tanpa refresh |
| `DrawRequested(uint256 requestId)` | id request VRF | Ubah UI ke status "draw sedang diproses" |
| `DrawSkipped()` | — | Info "gak ada peserta ronde ini, draw dilewati" (opsional ditampilkan) |
| `Winner(Tier tier, address winner, uint256 prize)` | tier, alamat pemenang, jumlah hadiah | **Tampilan hasil undian** — ini yang paling penting buat halaman "pemenang terbaru" |
| `PrizeClaimed(address winner, uint256 amount)` | pemenang, jumlah | Update UI setelah user klaim sukses |

FE bisa pakai `useWatchContractEvent` (wagmi) atau setup listener manual buat ini. Untuk histori pemenang lama (bukan cuma yang live), perlu query event log lama (`eth_getLogs` / lewat indexer kalau nanti mau scale — untuk awal, langsung query RPC juga cukup).

---

## 5. Custom error → pesan yang enak dibaca user

Kalau transaksi revert, wallet biasanya cuma nunjukin nama error mentah. FE sebaiknya map ini ke pesan manusiawi:

| Error kontrak | Kapan muncul | Pesan yang disaranin ke user |
|---|---|---|
| `Lottery__NotOpen()` | Beli tiket pas draw lagi berlangsung | "Draw sedang berlangsung, coba lagi sebentar" |
| `Lottery__InsufficientPayment(required, sent)` | ETH yang dikirim kurang dari harga real-time | "Harga berubah, kirim ulang dengan jumlah yang benar" (bisa auto-retry pakai `required` dari error) |
| `Lottery__RefundFailed()` | Wallet user (kalau smart contract wallet) nolak nerima refund | "Wallet kamu gak bisa nerima refund ETH, coba pakai wallet lain" |
| `Lottery__NothingToClaim()` | Klaim padahal saldo claimable 0 | Harusnya tombol claim gak muncul sama sekali kalau ini kejadian — cek `getClaimablePrize` dulu |
| `Lottery__ClaimFailed()` | Wallet user nolak nerima saat klaim | "Transfer gagal, wallet kamu mungkin gak bisa nerima ETH langsung" |

---

## 6. Breakdown halaman yang disaranin

### Halaman utama (Home)
- **Dropdown pilih tier** ($1 / $5 / $10) + estimasi harga ETH real-time (`getTicketPriceInWei`)
- **Tombol "Beli Tiket"** (disabled kalau `getLotteryState() != OPEN`, atau kalau wallet belum connect)
- **Card info pool**: total terkumpul (ETH & USD), jumlah entry per tier
- **Countdown draw berikutnya**: dari `getNextDrawTime()`, dihitung client-side, sync ulang tiap beberapa menit
- **Banner klaim hadiah** (muncul kondisional): kalau `getClaimablePrize(user) > 0` setelah wallet connect → "Kamu punya hadiah $X yang belum diklaim!" + tombol klaim

### Halaman/section riwayat pemenang
- List dari event `Winner` (terbaru di atas): tier, alamat pemenang (bisa di-shorten + link ke explorer), jumlah hadiah, kapan

### Status wallet & network
- Connect wallet (RainbowKit / ConnectKit / wagmi connectors — bebas pilih)
- **Wajib validasi network** — kalau user connect ke chain yang salah (bukan chain tempat contract di-deploy), tampilkan prompt "switch network", jangan biarkan user coba transaksi di network salah (bakal revert/gagal aneh)

---

## 7. Yang PENTING diperhatikan biar gak salah asumsi

- **Gak ada fungsi buat "lihat siapa aja yang beli tiket ronde ini"** secara langsung dari kontrak (cuma jumlahnya lewat `getEntryCount`, bukan daftar alamatnya) — kalau mau nampilin daftar peserta, itu harus dari event `TicketPurchased` yang di-index, bukan dari view function.
- **Gak ada fungsi buat lihat ronde-ronde lama** selain lewat event log — kontrak cuma nyimpen state ronde yang aktif sekarang (`s_round` naik terus, data lama masih ada di storage tapi gak ada getter buat "ronde ke-N kemarin gimana", harus direkonstruksi dari `Winner` event history).
- **`getPoolBalanceUSD()` itu snapshot harga saat dipanggil** — bisa beda tiap block karena harga ETH berubah-ubah. Jangan di-cache lama-lama di FE.
- **Tier enum harus persis 0/1/2** saat manggil contract — kalau FE pakai dropdown dengan value string ("ONE"/"FIVE"/"TEN"), harus di-mapping ke angka sebelum dikirim.
- **Alamat contract beda per network** (lokal Anvil vs Base Sepolia vs nanti mainnet) — FE perlu config per-chain-id, jangan hardcode 1 alamat.

---

## 8. Yang dibutuhkan dari sisi setup sebelum ngoding FE

- **Alamat contract + ABI** — didapat dari `smart-contract/out/Lottery.sol/Lottery.json` (ABI) setelah `forge build`, dan alamat dari hasil `forge script DeployLottery` (lokal Anvil atau Base Sepolia).
- **RPC URL** per network yang mau didukung.
- Library Web3 di FE (belum terinstall di `frontend/` — masih scaffold Next.js polos): pilihan umum **wagmi + viem** (sesuai stack reference di `CLAUDE.md`), plus salah satu wallet connector (RainbowKit paling gampang setup-nya).
