**Rencana DApp Lottery — Smart Contract**

Aku mau membangun sistem lottery menggunakan **Foundry**, di-deploy di **Base** (Ethereum Layer 2). Untuk random number generation, aku akan pakai **Chainlink VRF**.

**Requirement teknis:**
- Smart contract wajib menggunakan **custom error** (bukan `require` dengan string) untuk efisiensi gas fee.

**Sistem tiket — 3 tier, harga dalam USD:**
- Tier 1: $1
- Tier 2: $5
- Tier 3: $10

Karena harga tiket dalam USD tapi pembayaran tetap pakai ETH, contract akan menggunakan **Chainlink Price Feed (ETH/USD)** untuk convert harga secara real-time.

**Alur pembelian tiket (Approach B):**
1. Di frontend, user tinggal pilih dropdown tier ($1 / $5 / $10) — tidak perlu input manual.
2. FE memanggil view function di contract (gratis, gak makan gas) untuk dapat estimasi berapa ETH yang setara dengan harga USD tier tersebut, lalu tampilkan estimasi itu ke user.
3. User klik bayar, wallet kirim ETH sejumlah estimasi (+ sedikit buffer untuk jaga-jaga perubahan harga).
4. Saat transaksi dieksekusi on-chain, contract **hitung ulang harga real-time** dari price feed (bukan pakai angka dari quote FE) untuk validasi — supaya source of truth tetap di on-chain, bukan dari frontend.
5. Kalau ETH yang dikirim user lebih dari yang dibutuhkan, sisanya di-refund otomatis.

Semua dana dari ketiga tier ini terkumpul jadi **1 pool/bank** yang sama.

**Proses draw:**
1. Setelah waktu/kondisi tertentu terpenuhi, sistem generate random number lewat **Chainlink VRF** — sekaligus 3 angka random dalam 1 request, satu untuk masing-masing tier.
2. Dari situ dipilih **3 pemenang** (satu pemenang per tier), masing-masing dari pool peserta di tier-nya sendiri.

**Pembagian hadiah:**
- Pemenang tier $1 dapat **15%** dari total pool.
- Pemenang tier $5 dapat **35%** dari total pool.
- Pemenang tier $10 dapat **50%** dari total pool.

**Edge case — tier kosong:**
Kalau saat draw ada tier yang tidak ada pesertanya sama sekali, tier itu di-skip, dan persentase hadiahnya **di-redistribusi secara proporsional** ke tier-tier lain yang punya peserta (bukan dibagi rata, tapi tetap mengikuti bobot persentase aslinya).

Contoh perhitungan kalau cuma 2 tier yang aktif:
- Tier $1 + Tier $5 aktif (Tier $10 kosong) → Tier $1 dapat **30%**, Tier $5 dapat **70%**
- Tier $1 + Tier $10 aktif (Tier $5 kosong) → Tier $1 dapat **~23%**, Tier $10 dapat **~77%**
- Tier $5 + Tier $10 aktif (Tier $1 kosong) → Tier $5 dapat **~41%**, Tier $10 dapat **~59%**

Kalau cuma **1 tier** yang aktif, tier itu otomatis dapat **100%** dari pool.

**Presisi dana:**
Perhitungan harus memastikan seluruh isi bank/pool **habis terbagi** ke pemenang tanpa ada sisa (dust) yang nyangkut di kontrak akibat pembulatan. Sisa pembulatan (dust) otomatis masuk ke pemenang dari **tier dengan persentase terbesar yang aktif** saat draw itu (bukan selalu tier $10 — tergantung tier mana yang aktif dan hasil redistribusi).

**Sistem entry (peluang menang):**
1 tiket = 1 entry. Tidak ada bobot peluang ganda — kalau 1 wallet beli beberapa tiket, dia dapat beberapa entry terpisah di tier itu, masing-masing entry punya peluang yang sama (dipilih via `randomNumber % totalEntries` tier tersebut).

**Otomatisasi:**
Proses trigger draw (kapan lottery ditutup, random number di-generate, dan pemenang diumumkan) dibuat otomatis menggunakan **Chainlink Automation**, jadi tidak perlu manual trigger dari owner/admin.

- Trigger draw **murni berbasis waktu** (interval tetap) — tidak ada syarat minimum jumlah peserta.
- Kalau saat waktu draw tiba ternyata **semua tier kosong** (belum ada peserta sama sekali), contract **skip request VRF sepenuhnya** (hemat gas, karena tidak ada pemenang yang bisa dipilih) dan langsung reset ke periode berikutnya.

**Chainlink VRF:**
Pakai **VRF v2.5** dengan **subscription model** (bukan direct funding) — karena draw berulang otomatis lebih cocok pakai subscription yang di-fund sekali (LINK atau native ETH), dibanding bayar per-request dari saldo contract.

---
