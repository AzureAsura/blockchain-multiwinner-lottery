# Trigger Draw Otomatis via GitHub Actions Cron

## Context

`Lottery` sudah live & verified di Base Sepolia (`0xa95c906dbd0b5262b005c43ead972a0ce7acc9c5`, block `45664854`, interval `1 weeks`), VRF subscription sudah di-fund dan kontraknya terdaftar sebagai consumer. Satu-satunya bagian yang belum jalan: **tidak ada yang memanggil `performUpkeep`**, jadi draw tidak pernah terjadi sendiri.

> Ini deployment kedua. Deployment pertama (`0x917be9722a55f18031cf1476bdBbE0fdE3bF6bC7`, interval 5 menit) sudah menyelesaikan satu round penuh — GitHub Actions workflow terbukti berhasil trigger `performUpkeep` sungguhan (dikonfirmasi lewat `s_lastDrawTimestamp` on-chain cocok persis dengan waktu selesai job) — sebelum di-redeploy dengan interval 1 minggu untuk pemakaian yang lebih realistis.

Rencana awal di `docs/TESTNET.md` langkah 7 adalah mendaftarkan Chainlink Automation upkeep. Itu **tidak lagi mungkin**:

| Opsi | Status (Agustus 2026) |
|---|---|
| Chainlink Automation | ❌ Sunset — v2.1 testnet berakhir 24 Juni 2026 |
| Gelato | ❌ Platform lama deprecated; dashboard baru sudah tidak menyediakan alur create-task ini |
| Chainlink CRE | ⚠️ Butuh `AutomationReceiver` baru + workflow TS, **dan** deploy workflow masih "Early Access" (nunggu approval) + indikasi butuh gas ETH mainnet |
| **GitHub Actions cron** | ✅ Self-service, gratis, jalan sekarang juga |

Tujuan: draw berjalan otomatis tanpa `cast send` manual, tanpa menunggu approval pihak ketiga, dan **tanpa mengubah satu baris pun `Lottery.sol`**.

## Kenapa tidak perlu ubah kontrak

`performUpkeep(bytes calldata)` di `smart-contract/src/Lottery.sol:130` sengaja **tanpa access control** — didesain begitu supaya node Automation bisa memanggilnya, tapi sifatnya generik: alamat mana pun boleh memanggil. Fungsi itu memvalidasi ulang state + interval sendiri (`Lottery__NotOpen`, `Lottery__UpkeepNotNeeded`), jadi keamanannya tidak bergantung pada siapa pemanggilnya. Rationale ini sudah tercatat di `smart-contract/NOTE.md` (bagian Step 4).

Artinya GitHub Actions cukup berperan sebagai "pemanggil terjadwal" — persis peran yang dulu dipegang node Chainlink.

## Keputusan yang sudah disepakati

| Aspek | Pilihan |
|---|---|
| Mekanisme | GitHub Actions `schedule` cron, tiap 5 menit |
| Wallet pemanggil | `lottery-deployer` (lihat catatan risiko di bawah) |
| Guard sebelum kirim tx | Ya — `checkUpkeep` dulu, baru `performUpkeep` kalau `true` |
| Perubahan kontrak | Tidak ada |

> **Catatan risiko yang diterima:** `lottery-deployer` juga pemilik VRF subscription. Kalau secret-nya bocor, penyerang bisa membatalkan subscription dan menarik dananya (bukan sekadar menghabiskan gas). Mitigasi yang berlaku: ini wallet testnet-only dengan saldo kecil, dan repo-nya publik sehingga secret tidak pernah diteruskan ke workflow dari fork PR. Kalau suatu saat key dicurigai bocor: batalkan subscription di vrf.chain.link, buat yang baru, redeploy.

---

## File yang akan dibuat (belum dikerjakan — ini baru rencana)

```
.github/workflows/lottery-upkeep.yml     # satu-satunya file baru
```

## Isi workflow

```yaml
name: Lottery Upkeep

on:
  schedule:
    - cron: '*/5 * * * *'
  workflow_dispatch:        # tombol "Run workflow" manual, untuk tes

permissions:
  contents: read            # workflow tidak perlu menulis apa pun ke repo

concurrency:
  group: lottery-upkeep     # cegah dua run tumpang tindih saat GH telat
  cancel-in-progress: false

jobs:
  upkeep:
    runs-on: ubuntu-latest
    steps:
      - uses: foundry-rs/foundry-toolchain@v1

      - name: Check and perform upkeep
        env:
          RPC_URL: ${{ secrets.BASE_SEPOLIA_RPC_URL }}
          PRIVATE_KEY: ${{ secrets.UPKEEP_PRIVATE_KEY }}
          LOTTERY: '0xa95c906dbd0b5262b005c43ead972a0ce7acc9c5'
        run: |
          set -euo pipefail
          needed=$(cast call "$LOTTERY" "checkUpkeep(bytes)(bool,bytes)" 0x --rpc-url "$RPC_URL" | head -1)
          echo "upkeepNeeded=$needed"
          if [ "$needed" = "true" ]; then
            cast send "$LOTTERY" "performUpkeep(bytes)" 0x \
              --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY"
          else
            echo "Nothing to do."
          fi
```

Detail yang sudah diverifikasi, bukan diasumsikan:

- **Format output `cast call`** — `checkUpkeep(bytes)(bool,bytes)` mengembalikan dua baris (`true`, lalu `0x`); `head -1` mengambil bool-nya. Sudah dites langsung ke kontrak live (hasil saat ini: `upkeepNeeded=true`).
- **Tidak ada `actions/checkout`** — workflow tidak butuh file repo sama sekali, cuma butuh binary `cast`. Menghilangkan checkout bikin run lebih cepat dan mengurangi permukaan.
- **Guard `checkUpkeep` itu penting**, bukan optimasi kosmetik: tanpa itu, tiap run yang datang terlalu cepat akan revert `Lottery__UpkeepNotNeeded` dan menandai job merah — bikin log penuh kegagalan palsu.
- **Repo publik** (`AzureAsura/blockchain-multiwinner-lottery`) → menit Actions gratis tak terbatas, jadi cadence 5 menit (288 run/hari) tidak makan kuota.

## Langkah manual (kamu, di browser + terminal)

1. Ambil private key deployer di terminal — **jangan paste ke chat**:
   ```bash
   cast wallet private-key --account lottery-deployer
   ```
2. Di GitHub: **Settings → Secrets and variables → Actions → New repository secret**, buat dua secret:
   - `UPKEEP_PRIVATE_KEY` — hasil langkah 1 (diawali `0x`)
   - `BASE_SEPOLIA_RPC_URL` — URL Alchemy dari `smart-contract/.env`
     > Aman ditaruh di sini: GitHub Secrets terenkripsi dan hanya dibaca server-side runner — beda total dengan `NEXT_PUBLIC_*` di frontend yang ter-bundle ke browser (alasan kenapa frontend pakai `https://sepolia.base.org` publik, lihat `docs/TESTNET.md`).
3. Push branch berisi workflow ini, lalu buka tab **Actions** → jalankan `Lottery Upkeep` lewat **Run workflow** untuk tes pertama tanpa menunggu jadwal.

## Dokumen yang perlu disesuaikan (belum dikerjakan)

Dua file masih menginstruksikan pendaftaran Chainlink Automation yang sudah tidak mungkin — biarkan riwayatnya, tapi tambahkan penanda status supaya tidak menyesatkan nanti:

- `docs/TESTNET.md` — langkah 7 dan baris verifikasi #5/#7 → tandai bahwa Automation sudah sunset dan digantikan pendekatan di sini.
- `docs/NOTE.md` — bagian "Sering kelewat — Chainlink Automation registration" → beri catatan yang sama.

---

## Verifikasi end-to-end

| # | Cek | Cara |
|---|---|---|
| 1 | Workflow tersintaks benar | Tab Actions menampilkan `Lottery Upkeep`, `Run workflow` bisa diklik |
| 2 | Guard bekerja | Jalankan manual saat interval belum lewat → log `upkeepNeeded=false`, job tetap hijau, tidak ada tx terkirim |
| 3 | Panggilan nyata | Jalankan manual saat `upkeepNeeded=true` → ada tx hash di log; cek di Basescan statusnya sukses |
| 4 | Draw kosong | Tanpa peserta → event `DrawSkipped`, `getNextDrawTime()` maju ~5 menit, state tetap `OPEN` |
| 5 | Draw berisi | Beli 1 tiket dari frontend, tunggu satu siklus → state jadi `CALCULATING`, lalu VRF fulfill → `getRound()` naik jadi 1, `WinnerSection` menampilkan baris pemenang |
| 6 | Benar-benar otomatis | Diamkan ≥15 menit tanpa intervensi → jadwal jalan sendiri, `getNextDrawTime()` terus maju |

Perintah cek read-only (dijalankan lewat sesi Claude, bukan manual):
```bash
cast call <lottery> "getLotteryState()(uint8)" --rpc-url $BASE_SEPOLIA_RPC_URL
cast call <lottery> "getRound()(uint256)"      --rpc-url $BASE_SEPOLIA_RPC_URL
cast call <lottery> "getNextDrawTime()(uint256)" --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Batasan yang harus disadari

Ini pengganti yang jujur — bukan setara penuh keeper terdesentralisasi:

- **Cron GitHub tidak presisi.** Minimum 5 menit, dan sering telat (kadang belasan menit saat GitHub ramai), bahkan bisa dilewati. Draw jadi mundur, tidak pernah lebih cepat. Frontend sudah menangani ini dengan baik: `useCountdown` punya status `awaiting-draw` ("Awaiting draw…") persis untuk kondisi interval sudah lewat tapi belum ada yang memanggil.
- **Workflow terjadwal di repo publik otomatis dinonaktifkan setelah 60 hari tanpa aktivitas repo** (push/merge; komentar & star tidak dihitung). Kalau proyek didiamkan, undian berhenti diam-diam — cukup push apa pun untuk menghidupkan lagi.
- **Terpusat.** Kalau GitHub Actions down, tidak ada yang memicu draw. Ini trade-off sadar dibanding jaringan keeper.
- **Risiko VRF stuck tetap ada** (sudah didokumentasikan di `smart-contract/NOTE.md` Step 10 sebagai accepted risk): kalau saldo subscription habis saat fulfillment, round mengunci di `CALCULATING`. Efeknya di sini, `checkUpkeep` akan selamanya `false` dan cron jadi no-op senyap — jadi saldo subscription tetap perlu dipantau.

## Yang TIDAK dikerjakan

- Mengubah `Lottery.sol` atau redeploy — tidak diperlukan.
- Migrasi ke Chainlink CRE — diblokir Early Access; bisa ditinjau ulang kalau nanti dibuka umum.
- Deploy frontend ke Vercel — terpisah dan tidak bergantung pada ini (Vercel Cron plan Hobby dibatasi 1×/hari, tidak cocok untuk interval 5 menit; Vercel cukup untuk hosting frontend saja).
- Monitoring/alerting kalau workflow gagal berkali-kali.
