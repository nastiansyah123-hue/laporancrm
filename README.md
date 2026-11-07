# CRM Adsy Team

Aplikasi CRM terpisah untuk Kulon Progo dan Purworejo, menggunakan React + Vite dan Supabase. Tampilan mengikuti warna dan logo Akuisisi Adsy Team. Tidak ada modul biaya iklan.

## Jalankan dan deploy

1. Unggah seluruh isi folder proyek ke repository GitHub baru.
2. Untuk **instalasi CRM baru**, pada project Supabase yang sama dengan Akuisisi, jalankan **hanya `supabase/schema.sql` dari proyek CRM ini, sekali** (sudah mencakup pembaruan paket). Ini membuat tabel `crm_*`; tidak menimpa `profiles`, `reports`, atau tabel Akuisisi. Jangan menjalankan ulang schema Akuisisi untuk memasang CRM. SQL memakai transaksi agar kegagalan membatalkan seluruh pemasangan.
3. Buat akun Auth admin pertama secara manual melalui Supabase Authentication. Boleh memakai UUID Auth admin yang sudah ada, karena identitas Auth dibagi dalam project yang sama.
4. Jalankan SQL berikut, ganti UUID dan nama. Bila akun sudah punya profil CRM pending, perintah ini memperbarui profil CRM tersebut menjadi admin.

```sql
insert into public.crm_profiles(id,name,email,role,status)
select id,'Admin CRM',email,'admin','active'
from auth.users where id='UUID-AUTH-ADMIN'
on conflict(id) do update set name=excluded.name,role='admin',status='active',region_id=null,manager_id=null;
```

5. Import repository ke Vercel (framework Vite; build `npm run build`; output `dist`). Tambahkan:

```text
VITE_SUPABASE_URL=https://PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=PUBLIC_ANON_KEY
```

Keduanya boleh sama dengan aplikasi Akuisisi. **Service role key tidak diperlukan** dan jangan dimasukkan ke frontend. Aplikasi ini tidak membutuhkan OpenAI key.
6. Pada Supabase Authentication > URL Configuration, tambahkan URL Vercel CRM ke daftar Redirect URLs. Pertahankan URL Akuisisi yang sudah ada. Jangan mengganti Site URL global tanpa mempertimbangkan email aplikasi lain. CRM memasok `emailRedirectTo` URL aplikasinya saat daftar. Pengaturan konfirmasi email mengikuti Supabase.
7. Redeploy setelah memasang env. Tanpa env, aplikasi otomatis masuk **mode demo dengan data simulasi**; mode itu bukan login produksi.

Lokal: salin `.env.example` ke `.env`, `npm ci`, `npm run dev`. Node 20+ disarankan. Perintah `npm test`, `npm run test:db`, dan `npm run build` untuk verifikasi.

## Update dari CRM versi satu harga

Jika SQL CRM versi pertama sudah dipasang, **jangan ulang `schema.sql`**. Jalankan **hanya `supabase/migrations/002_shared_product_packages.sql` sekali**, lalu deploy kode terbaru. Fixture di `supabase/tests/fixtures` hanya untuk tes, bukan SQL pemasangan.

Migrasi mempertahankan semua laporan dan omzet lama. Harga sales/reseller lama diubah menjadi paket 1 unit agar dapat dikembangkan menjadi banyak paket. Produk lama yang namanya sama tidak digabung otomatis; varian duplikat diberi akhiran `· lama UUID` agar riwayat dan harga tidak hilang. Admin dapat memilih satu produk master untuk pemakaian baru, menonaktifkan varian lama, dan menyesuaikan namanya. Produk baru cukup dibuat **sekali untuk kedua wilayah**.

Laporan lama tanpa rincian paket ditampilkan sebagai **Rincian lama**, tanpa mengubah jumlah/omzet atau mengira-ngira komposisi paket. Laporan baru memakai order per paket.

## Urutan mengatur tim

- Admin dan SPV memiliki akses setara ke semua wilayah dan laporan.
- Daftarkan akun anggota melalui halaman Daftar CRM. Profil baru selalu `crm/pending`, meski metadata pengguna mencoba meminta peran admin.
- Admin mengaktifkan PIC terlebih dahulu, memilih wilayahnya. Kemudian aktifkan Sub Leader dengan PIC sebagai atasan. Terakhir aktifkan CRM dengan SL atau PIC sebagai atasan.
- PIC/Sub Leader tidak perlu akun kedua untuk menjual: halaman Penjualan Saya mencatat penjualan pribadi, Laporan Tim menampilkan penjualan anggota yang diizinkan. Rekap wilayah menjumlahkan baris pribadi satu kali.
- PIC melihat penjualan pribadi dirinya, SL bawahannya, dan anggota CRM di bawah hierarki tersebut. SL melihat dirinya dan anggota CRM yang ditugaskan kepadanya. CRM hanya melihat diri sendiri, termasuk target dan profilnya. Jabatan tidak memberikan akses ke wilayah lain.
- Laporan historis anggota nonaktif tetap terlihat oleh Admin/SPV dan atasan yang masih ditugaskan kepadanya, tetapi akun nonaktif tidak dapat mengakses laporan.
- Anggota bawahan aktif harus dipindahkan sebelum atasannya dinonaktifkan, diganti peran, atau dipindah wilayah. Tidak tersedia penghapusan akun/laporan permanen melalui aplikasi.
- Perubahan atasan memengaruhi akses ke riwayat anggota sesuai hierarki saat ini. Penjualan menyimpan wilayah saat input: setelah pindah wilayah, laporan lama tetap masuk wilayah asal. Pemilik dan Admin/SPV tetap bisa melihat riwayatnya. Atasan di wilayah baru hanya melihat laporan wilayah baru; atasan lama tidak lagi melihat anggota setelah dipindah. Ini aturan versi awal, bukan riwayat struktur organisasi per tanggal.

## Produk dan perhitungan

Admin/SPV mengatur **satu master produk CRM untuk semua wilayah**. Master ini tetap terpisah dari produk Akuisisi. Tidak ada produk/harga produksi yang otomatis disalin dari contoh. Wilayah penjualan berasal dari akun pemilik laporan, bukan dari produk.

Setiap produk memiliki banyak **paket sales** dan **paket reseller**. Masing-masing berisi nama, jumlah unit per paket, **harga TOTAL paket**, dan status aktif. Contoh: 1 botol Rp10.000, 2 botol Rp15.000. Bukan berarti harga 2 botol Rp15.000 dikalikan dua lagi.

- CRM mengisi jumlah order per paket. **Closing = total order**, **unit = Σ(order × unit paket)**, dan **omzet = Σ(order × harga total paket)**.
- **Repeat Order Sales**, **Cross Sales**, dan **New Customer** memakai paket sales. **Repeat Order Reseller** memakai paket reseller. Seluruh laporan baru memakai omzet otomatis tanpa input omzet manual. Cross Sales lama yang pernah diisi manual tetap mempertahankan angka historis.
- Satu transaksi dicatat **hanya di salah satu jenis**, jangan diulang di repeat order dan New Customer/cross sales.
- Satu baris laporan unik per pemilik + tanggal + produk + jenis. Jika sudah ada, gunakan Edit. Identitas baris tidak dapat diubah saat Edit; jumlah order dan catatan dapat diperbaiki pemilik pada laporan paket.
- Nama, harga, dan unit setiap paket disimpan ketika paket pertama kali masuk laporan. Perubahan master, penghapusan melalui API, atau nonaktifnya paket tidak mengganti snapshot yang sudah tersimpan. Paket baru yang ditambahkan ke laporan lama memakai harga master saat paket ditambahkan. Paket tersimpan tidak boleh dihilangkan dari laporan; isi order 0 bila perlu.
- Database memvalidasi paket dan menghitung ulang semua total. Harga/closing/omzet kiriman frontend tidak dipercaya. Paket nonaktif tidak dapat dipakai pada laporan baru. Paket yang sudah tersimpan masih dapat dikoreksi ordernya meski produk/paket dinonaktifkan.
- Paket yang sudah tersimpan di produk dapat dinonaktifkan dari UI; paket baru yang belum disimpan dapat dihapus. Maksimum 50 paket dalam master, 100 snapshot paket per laporan. Satuan produk dikunci pada UI setelah produk dibuat agar label laporan historis konsisten.
- Upsell = total unit / total closing, dihitung dari total periode, bukan rata-rata rasio harian.
- Target omzet, total pelanggan, dan pelanggan aktif diatur Admin/SPV **per anggota per bulan**. Pencapaian = omzet bulan tersebut / target. Jumlah pelanggan belum terhubung ke database pelanggan eksternal.
- Grafik dashboard menampilkan maksimal 366 hari, sedangkan kartu dan ekspor tetap mengikuti seluruh rentang yang dipilih. Filter tanggal inklusif. Ekspor mencakup semua hasil filter, bukan hanya halaman aktif.

## Hubungan dengan Excel

Sumber acuan: `Laporan CRM Kulon Progo November  2026.xlsx` (34 sheet). Format Purworejo dikonfirmasi sama oleh pemilik.

| Kelompok Excel | Fitur aplikasi |
| --- | --- |
| Sheet CRM per orang, repeat sales/reseller per produk | Penjualan Saya, jenis penjualan dan produk dinamis |
| Cross sales dan New Customer | Jenis penjualan terpisah |
| Resume, Total Closing, Total Closing by CS, Leadboard | Ringkasan dan Laporan Tim, filter serta ekspor CSV |
| Upsale | Kartu Upsell berdasarkan unit/closing |
| Target Omset, total customer, real aktif | Target & Pelanggan per anggota per bulan |

File contoh hanya dianalisis untuk struktur; **data pribadi dan historis Excel tidak diimpor atau dipublikasikan**. Nama, angka, dan harga pada demo adalah simulasi. IMPORTRANGE dari spreadsheet eksternal, pengecekan duplikat pesanan lintas sumber, PAY DES, bonus khusus produk, evaluasi mingguan khusus, detail pelanggan individual, dan cross sales lead terpisah belum diintegrasikan dalam versi ini. Laporan harian dan rekap inti sudah tersedia; formula workbook yang memiliki #REF! tidak disalin.

## Supabase dan isolasi

Tabel: `crm_regions`, `crm_profiles`, `crm_products`, `crm_reports`, `crm_targets`. Fungsi/trigger baru berawalan `crm_`. Region ditanam hanya Kulon Progo dan Purworejo. Tidak ada FK ke tabel Akuisisi.

Supabase **Auth tetap satu**: email yang sama tidak dibuat menjadi dua identitas terpisah. Jika sudah punya akun Auth aplikasi lain, masuk menggunakan akun itu lalu Ajukan akses CRM. Profil `crm_profiles` tetap memerlukan aktivasi. CRM signup memakai metadata `app: crm_adsy`, tanpa `account_role`; sehingga trigger Akuisisi saat ini yang membaca `account_role` tidak membuat profil CS/advertiser untuk pendaftar CRM. Trigger CRM mengabaikan signup aplikasi lain. Profil/restriksi terpisah bukan berarti layanan Auth dan kuota project terpisah.

RLS diterapkan pada semua tabel CRM. Hak tulis laporan hanya milik pemilik aktif. Penetapan peran/atasan melalui RPC `crm_manage_profile`, hanya Admin/SPV. Pengguna tidak bisa mengubah role/status sendiri. Admin tidak mengubah akses akunnya sendiri lewat UI untuk menghindari kehilangan akses; gunakan admin lain.

## Verifikasi

- Tes unit: scope PIC/SL/CRM, rekap tanpa hitung ganda, formula omzet, validasi jumlah, proteksi CSV.
- Tes PostgreSQL lokal PGlite untuk instalasi baru dan migrasi versi lama: paket, penolakan manipulasi total, snapshot harga, pelestarian laporan historis, master bersama, RLS seluruh peran termasuk beberapa admin, isolasi wilayah, pending signup, larangan promosi sendiri, harga snapshot, omzet server, validasi atasan/target, dan kompatibilitas trigger signup aplikasi lain.
- Build Vite produksi.
- Browser interaktif dan koneksi Supabase/Vercel milik pengguna belum diverifikasi di lingkungan pembuatan ini. Demo private yang diterbitkan tidak memakai kredensial produksi.
