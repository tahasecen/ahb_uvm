# AHB-Lite UVM VIP — Test Prosedürleri

Bu belge her testin **ne test ettiğini**, **nasıl koşulacağını** ve
**dalga formunda neye bakılacağını** anlatır. Amaç: "log temiz" demek yetmez;
dalgayı açıp protokolün doğru sürüldüğü gözle doğrulanır.

Tüm zaman damgaları yerel Questa 2025.2 koşum log'larından alınmıştır
(varsayılan seed). Rastgele veri (`wdata`) üreten testlerde değerler seed'e göre
değişir; sabit olan **adresler** ve **PASS/FAIL** değişmez.

## Koşum ortamı (bir kez)

EDA Playground'da:

- **Design** panosuna `hdl/design.sv`, **Testbench** panosuna `hdl/testbench.sv`
- Simulator: **Siemens Questa 2025.2**, UVM/OVM: **UVM 1.2**
- Compile options: `-sv +cover=bcs -coverage`
- **[x] Open EPWave after run**

Her test `+UVM_TESTNAME` ile ayrı ayrı koşulur. `tb_top` `dump.vcd` üretir;
dalga incelemesi **Run** sonrası açılan EPWave penceresinde yapılır.

## Genel referans (tüm testler için)

- Saat periyodu 10 ns → posedge'ler 5, 15, 25, 35, 45, ... ns.
- Reset 25 ns'de kalkar. İlk transfer'in adres fazı ~45 ns'dedir.
- Monitor, bir transfer'i **data fazı** kenarında yayınlar; **adres fazı** bir
  cycle (10 ns) öncesindedir. Yani log'daki `[MON] @ T ns` → adres fazı `T-10`.
- Byte adresi → word index: `addr[5:2]` (0x10 → index 4, 0x3C → index 15).

---

## TEST: ahb_smoke_test

**Amaç:** En temel senaryo — tek yazma + tek okuma. Altyapının uçtan uca
çalıştığını ve AHB pipeline'ının doğru olduğunu doğrular.

**Kapsam:** DUT + interface + driver + monitor + scoreboard temel yolu; pipeline.

**Nasıl koşulur:**
```
Run options: +UVM_TESTNAME=ahb_smoke_test +UVM_VERBOSITY=UVM_MEDIUM
```

**Beklenen konsol çıktısı:**
```
@ 55 ns: [MON] WRITE addr=0x00000010 wdata=0xa5a51234
@ 85 ns: [MON] READ  addr=0x00000010 rdata=0xa5a51234
[SB] PASS addr=0x00000010 data=0xa5a51234
SCOREBOARD SUMMARY: WRITE=1 READ=1 PASS=1 FAIL=0 SKIP=0
AHB_RESULT test=ahb_smoke_test UVM_ERROR=0 UVM_FATAL=0 PASS
```

**Beklenen scoreboard sonucu:**

| WRITE | READ | PASS | FAIL | SKIP |
|-------|------|------|------|------|
|   1   |   1  |   1  |  0   |  0   |

**Dalga formunda ne kontrol edilecek** (EPWave):

1. **@25 ns** — HRESETn 0→1. `addr_d` ve `wr_en_d` = 0 olmalı.
2. **@45 ns** (WRITE adres fazı) — HSEL=1, HADDR=0x00000010, HWRITE=1,
   HTRANS=NONSEQ. `addr_d` HENÜZ eski (0x0).
3. **@55 ns** (WRITE data fazı) — HWDATA=0xa5a51234, HTRANS=IDLE. `addr_d` ARTIK
   0x10 (bir önceki cycle'ın HADDR'i). `wr_en_d`=1 → `mem[4]` bu civarda 0xa5a51234
   olur (DUT Internal grubunda gör).
4. **@75 ns** (READ adres fazı) — HSEL=1, HADDR=0x10, HWRITE=0, HTRANS=NONSEQ.
5. **@85 ns** (READ data fazı) — HRDATA=0xa5a51234.

**Bu testte özel olarak bakılacak:**
- `addr_d`'nin `HADDR`'dan **tam bir cycle geride** olduğunu gözle doğrula.
- `DUT Internal` → `mem[4]` = 0xa5a51234 (adres 0x10 → index 4).

**Başarısızlık belirtileri:** HRDATA ≠ 0xa5a51234; addr_d, HADDR ile aynı
cycle'da değişiyor (pipeline yok); mem[4] boş ya da yanlış index dolu.

---

## TEST: ahb_write_read_test

**Amaç:** 3 farklı adrese (0x00, 0x20, 0x3C) rastgele veriyle yazma + geri okuma.

**Kapsam:** Parametrik sequence (`target_addr`), adres geçişleri, çoklu transfer.

**Nasıl koşulur:**
```
Run options: +UVM_TESTNAME=ahb_write_read_test +UVM_VERBOSITY=UVM_MEDIUM
```

**Beklenen konsol çıktısı** (wdata seed'e bağlı):
```
@ 55 ns: [MON] WRITE addr=0x00000000 wdata=0x4c2dfb0a
@ 85 ns: [MON] READ  addr=0x00000000 rdata=0x4c2dfb0a
@115 ns: [MON] WRITE addr=0x00000020 wdata=0x7ff8bc42
@145 ns: [MON] READ  addr=0x00000020 rdata=0x7ff8bc42
@175 ns: [MON] WRITE addr=0x0000003c wdata=0x71b9978e
@205 ns: [MON] READ  addr=0x0000003c rdata=0x71b9978e
```

**Beklenen scoreboard sonucu:**

| WRITE | READ | PASS | FAIL | SKIP |
|-------|------|------|------|------|
|   3   |   3  |   3  |  0   |  0   |

**Dalga formunda ne kontrol edilecek** (EPWave):

- Üç yazmanın DOĞRU mem index'ine gittiğini gör: 0x00→mem[0], 0x20→mem[8],
  0x3C→mem[15].
- Adres geçişlerinde HADDR temiz değişiyor mu (ara değer / glitch yok).
- Her write+read çiftinde okunan rdata, yazılan wdata'ya eşit.

**Bu testte özel olarak bakılacak:** Farklı adreslerin farklı mem hücrelerine
yazıldığını `DUT Internal`'da doğrula (index 0, 8, 15 dolu; diğerleri boş/eski).

**Başarısızlık belirtileri:** İki adres aynı mem hücresine yazıyor; rdata ≠ wdata.

---

## TEST: ahb_random_test

**Amaç:** Constraint'li rastgele trafik (10–50 transfer, write/read karışık).
Constraint'lerin çalıştığını ve rastgelelik altında DUT'un doğru kaldığını gösterir.

**Kapsam:** `randomize()`, constraint (c_align, c_range, c_size), scoreboard'un
yazılmamış adres (SKIP) mantığı.

**Nasıl koşulur:**
```
Run options: +UVM_TESTNAME=ahb_random_test +UVM_VERBOSITY=UVM_MEDIUM
```
Farklı seed'ler için EDA Playground'daki **Random seed** alanını değiştir
(aşağıdaki varyantlar seed 1 / 12345 / 99999 ile alınmıştır).

**Beklenen scoreboard sonucu** (varsayılan seed; FAIL her zaman 0):

| WRITE | READ | PASS | FAIL | SKIP |
|-------|------|------|------|------|
|  27   |  14  |  11  |  0   |  3   |

Seed varyasyonu (FAIL hep 0):
```
seed=1     -> WRITE=22 READ=19 PASS=12 FAIL=0 SKIP=7
seed=12345 -> WRITE=9  READ=14 PASS=2  FAIL=0 SKIP=12
seed=99999 -> WRITE=22 READ=18 PASS=5  FAIL=0 SKIP=13
```

**Dalga formunda ne kontrol edilecek** (EPWave):

Constraint'lerin dalgada çalıştığını doğrula:
- **HADDR her zaman word-aligned** — son iki bit (`HADDR[1:0]`) hep 00
  (adresler ...0, ...4, ...8, ...c ile biter).
- **HADDR hep 0x00–0x3C aralığında** — dışına çıkan değer yok.
- **HSIZE hep 0b010** (word).
- SKIP > 0 ise: o okumanın adresine daha önce hiç yazılmadığını `mem`'de
  doğrula (o hücre hâlâ başlangıç değerinde/X).

**Bu testte özel olarak bakılacak:** İki farklı seed ile ayrı ayrı koş;
trafik (adres/veri sırası) farklı ama ikisi de kurallara uyuyor ve FAIL=0.

**Başarısızlık belirtileri:** HADDR[1:0] ≠ 00; HADDR > 0x3C; HSIZE ≠ 010; FAIL>0.

---

## TEST: ahb_b2b_test

**Amaç:** 8 ardışık transfer (4 write + 4 read). Monitor'ün ardışık transfer'leri
kaybetmediğini doğrular; ayrıca driver'ın **non-pipelined** olduğunu gösterir.

**Kapsam:** Ardışık sequence, monitor `pending` mantığı, driver zamanlaması.

**Nasıl koşulur:**
```
Run options: +UVM_TESTNAME=ahb_b2b_test +UVM_VERBOSITY=UVM_MEDIUM
```

**Beklenen konsol çıktısı** (adresler sabit, wdata seed'e bağlı):
```
@ 55 ns: [MON] WRITE addr=0x00000000 ...
@ 85 ns: [MON] WRITE addr=0x00000004 ...
@115 ns: [MON] WRITE addr=0x00000008 ...
@145 ns: [MON] WRITE addr=0x0000000c ...
@175 ns: [MON] READ  addr=0x00000000 ...
@205 ns: [MON] READ  addr=0x00000004 ...
@235 ns: [MON] READ  addr=0x00000008 ...
@265 ns: [MON] READ  addr=0x0000000c ...
```

**Beklenen scoreboard sonucu:**

| WRITE | READ | PASS | FAIL | SKIP |
|-------|------|------|------|------|
|   4   |   4  |   4  |  0   |  0   |

**Dalga formunda ne kontrol edilecek** (EPWave):

- **KRİTİK — transferler arasındaki IDLE cycle'ları SAY.** HTRANS grubu
  `NONSEQ → IDLE → IDLE → NONSEQ ...` deseni gösterir (transfer'ler 30 ns = 3
  cycle arayla; her transfer arasında en az bir IDLE cycle var).
- Bu, driver'ın **NON-PIPELINED** olduğunu kanıtlar. Gerçek back-to-back olsaydı
  desen `NONSEQ → NONSEQ` (araya IDLE girmeden) olurdu.
- Monitor 8 transfer'in HEPSİNİ yakaladı mı → scoreboard WRITE=4 READ=4.

**Bu testte özel olarak bakılacak:** HTRANS'ın ardışık iki cycle'da NONSEQ
OLMADIĞINI doğrula. (Bu gözlem, `c_b2b_txn=0` coverage sonucunun görsel karşılığı.)

**Başarısızlık belirtileri:** WRITE veya READ < 4 (monitor transfer kaybetti);
scoreboard FAIL > 0.

---

## TEST: ahb_walking_test

**Amaç:** 16 adresin (0x00, 0x04, ... 0x3C) tamamına benzersiz pattern
(`addr ^ 0xDEAD0000`) yazma + hepsini geri okuma. Adres decode hatası taraması.

**Kapsam:** Tüm bellek uzayı, adres decode, 32 transfer.

**Nasıl koşulur:**
```
Run options: +UVM_TESTNAME=ahb_walking_test +UVM_VERBOSITY=UVM_MEDIUM
```

**Beklenen konsol çıktısı** (deterministik — pattern sabit):
```
@ 55 ns: [MON] WRITE addr=0x00000000 wdata=0xdead0000
@ 85 ns: [MON] WRITE addr=0x00000004 wdata=0xdead0004
   ... (16 yazma, 0x00 -> 0x3C) ...
@505 ns: [MON] WRITE addr=0x0000003c wdata=0xdead003c
@535 ns: [MON] READ  addr=0x00000000 rdata=0xdead0000
   ... (16 okuma) ...
```

**Beklenen scoreboard sonucu:**

| WRITE | READ | PASS | FAIL | SKIP |
|-------|------|------|------|------|
|  16   |  16  |  16  |  0   |  0   |

**Dalga formunda ne kontrol edilecek** (EPWave):

- HADDR sırayla 0x00, 0x04, 0x08, ... 0x3C ilerliyor mu.
- **`DUT Internal` → `mem`'in 16 hücresinin de DOLDUĞUNU** gör: mem[0]=0xdead0000,
  mem[1]=0xdead0004, ... mem[15]=0xdead003c. (İlk 16 yazma bittiğinde, ~515 ns
  civarı, tüm array dolu olmalı.)
- Her okumanın rdata'sı, o adrese yazılan pattern'e eşit.

**Bu testte özel olarak bakılacak:** mem array'inin HİÇBİR hücresinin boş
kalmadığını ve her hücrenin DOĞRU pattern'i tuttuğunu doğrula.

**Başarısızlık belirtileri:** Bir mem hücresi boş kaldı (decode hatası — o adres
yazılmadı); iki adres aynı hücreye yazdı (rdata pattern uyuşmaz → MISMATCH).

---

## TEST: ahb_regression_test

**Amaç:** Üç sequence'i tek koşuda sırayla çalıştırır: walking → b2b → random
(nested sequence). Sequence geçişlerinin temiz olduğunu ve toplam sonucun
doğruluğunu gösterir.

**Kapsam:** Nested sequence, ardışık senaryo, scoreboard'un kümülatif çalışması.

**Nasıl koşulur:**
```
Run options: +UVM_TESTNAME=ahb_regression_test +UVM_VERBOSITY=UVM_MEDIUM
```

**Beklenen scoreboard sonucu** (random kısmı seed'e bağlı; FAIL=0 sabit):

| WRITE | READ | PASS | FAIL | SKIP |
|-------|------|------|------|------|
|  25   |  27  |  27  |  0   |  0   |

> Not: walking (16w/16r) tüm adresleri doldurduğu için sonraki random okumalar
> SKIP değil PASS olur → SKIP=0. Functional coverage bu testte %100.

**Dalga formunda ne kontrol edilecek** (EPWave):

- İlk faz (walking): HADDR 0x00→0x3C taraması.
- Sequence geçişlerinde bus TEMİZ IDLE'a dönüyor mu (HSEL=0, HTRANS=IDLE).
- Toplam transfer sayısı = walking(32) + b2b(8) + random(değişken) ile tutarlı.

**Bu testte özel olarak bakılacak:** Bir sequence bitip diğeri başlarken
HTRANS'ın IDLE'a döndüğünü ve HSEL'in 0'landığını doğrula (senaryolar birbirine
karışmıyor).

**Başarısızlık belirtileri:** Sequence sınırında yarım transfer; FAIL > 0.

---

## TEST: ahb_align_error_test  (NEGATİF TEST — FAIL BEKLENİR)

**Amaç:** Bilerek hizasız adres (0x11, word) sürerek `a_addr_align` assertion'ının
ateşlediğini gösterir. "Assertion sessiz çünkü doğru" ile "assertion sessiz çünkü
çalışmıyor" ayrımını yapar.

**Kapsam:** SVA `a_addr_align`; negatif (hata bekleyen) test metodolojisi.

**Nasıl koşulur:**
```
Run options: +UVM_TESTNAME=ahb_align_error_test +UVM_VERBOSITY=UVM_MEDIUM
```

**Beklenen konsol çıktısı:**
```
UVM_ERROR testbench.sv @ 45 ns: [SVA] a_addr_align: unaligned addr=0x00000011 for HSIZE=0b010
AHB_RESULT test=ahb_align_error_test UVM_ERROR=1 UVM_FATAL=0 FAIL
```

**Beklenen sonuç:** `UVM_ERROR=1`, **FAIL** — bu bir başarı göstergesidir
(assertion görevini yaptı).

**Dalga formunda ne kontrol edilecek** (EPWave):

- **@45 ns** — HADDR=0x00000011 (hizasız: son iki bit 01), HSIZE=0b010 (word),
  HSEL=1, HTRANS=NONSEQ sürülen cycle'ı bul.
- Assertion tam O cycle'da ateşler. Questa'da assertion durumu:
  **View > Coverage > Assertions** penceresi (veya wave'e assertion'ı sürükle).
- Konsoldaki `UVM_ERROR ... @ 45 ns` ile dalgadaki 45 ns'yi eşleştir.

**Bu testte özel olarak bakılacak:** HADDR[1:0]=01 (hizasız) olan cycle ile
assertion ateşleme zamanının AYNI (45 ns) olduğunu doğrula.

**Başarısızlık belirtileri (bu test için "ters"):** Assertion ATEŞLEMEZSE
(UVM_ERROR=0) sorun var — assertion kuralı yanlış ya da ölü demektir.

---

## Hızlı Doğrulama Checklist

Her dalga penceresinde ~60 saniyede kontrol edilecekler:

- [ ] HRESETn 25 ns'de 1 oldu mu
- [ ] Reset sırasında `addr_d` / `wr_en_d` sıfır mı
- [ ] HADDR değiştiği cycle'da HWDATA DEĞİŞMİYOR (bir cycle sonra) — **PIPELINE DOĞRU MU**
- [ ] `addr_d`, HADDR'dan tam bir cycle geride mi
- [ ] HTRANS sadece 00 (IDLE) ve 10 (NONSEQ) değerlerini alıyor mu (bu kapsamda 01/11 yok)
- [ ] HREADY sabit 1 mi (wait state kapsam dışı)
- [ ] HRESP sabit 0 mi (error response kapsam dışı)
- [ ] HSEL transfer dışında 0'a dönüyor mu
- [ ] HADDR hep word-aligned mi (son iki bit 00)
- [ ] Konsol: `UVM_ERROR : 0` (ahb_align_error_test hariç)
- [ ] Scoreboard `FAIL=0` (ahb_align_error_test hariç)
