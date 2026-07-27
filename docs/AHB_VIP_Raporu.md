# AMBA AHB-Lite UVM VIP — Proje Raporu

## 1. Özet

Bu projede AMBA **AHB-Lite** protokolü için UVM (Universal Verification
Methodology) tabanlı bir Verification IP (VIP) geliştirildi. VIP, protokolü hem
**sürer** (driver) hem **gözler** (monitor) ve gelen veriyi bir referans modelle
**karşılaştırır** (scoreboard). Ek olarak pin/protokol seviyesinde **SVA
assertion**'lar ve **functional coverage** eklendi.

- **Dil / metodoloji:** SystemVerilog (IEEE 1800-2012), UVM 1.2
- **Simülatör:** Siemens Questa 2025.2 (EDA Playground)
- **DUT:** Basit AHB-Lite slave — 16 word'lük bellek, tek transfer, wait state
  yok, HRESP hep OKAY.
- **Kapsam:** okuma/yazma transferleri, adres decode, protokol kural kontrolü.
- **Bilinçli kapsam dışı:** burst (INCR/WRAP), wait state, ERROR response,
  pipelined driver, çoklu slave/interconnect, RAL, virtual sequence.

Tüm testler `UVM_ERROR=0` ile geçer. Doğrulama altyapısının kendisi bir negatif
test (kodda: `ahb_align_error_test`) ve iki manuel bozma deneyi ile kanıtlandı;
deneyler geçicidir, geri alınmıştır ve repoda kod karşılıkları yoktur
(bkz. Bölüm 7).

---

## 2. VIP Mimarisi

### 2.1 UVM hiyerarşisi (`print_topology` çıktısı, birebir)

```
UVM testbench topology:
--------------------------------------------------------------
Name                       Type                    Size  Value
--------------------------------------------------------------
uvm_test_top               ahb_smoke_test          -     @339
  env                      ahb_env                 -     @352
    agent                  ahb_agent               -     @361
      drv                  ahb_driver              -     @565
        rsp_port           uvm_analysis_port       -     @584
        seq_item_port      uvm_seq_item_pull_port  -     @574
      mon                  ahb_monitor             -     @409
        ap                 uvm_analysis_port       -     @418
      sqr                  ahb_sequencer           -     @428
        rsp_export         uvm_analysis_export     -     @437
        seq_item_export    uvm_seq_item_pull_imp   -     @555
    cov                    ahb_coverage            -     @389
      analysis_imp         uvm_analysis_imp        -     @398
    sb                     ahb_scoreboard          -     @370
      ap_imp               uvm_analysis_imp        -     @379
--------------------------------------------------------------
```

### 2.2 Blok diyagram

Kaynak dosya: [AHB_VIP_BD.drawio](AHB_VIP_BD.drawio) (draw.io ile açılır).

```
                          ahb_base_test / ahb_*_test
                                     |
                                  ahb_env
                 ______________________|________________________
                |                      |                        |
             ahb_agent            ahb_scoreboard           ahb_coverage
          ______|______              (ap_imp)             (analysis_export)
         |      |      |                 ^                        ^
        sqr -> drv    mon                |  transaction           |  transaction
         |     |      | ap (analysis_port) ----> broadcast --------+
         |     |      |
         |     v      v
         |   +----------------- ahb_if (interface) -----------------+
         |   |  drv_cb (sür)   mon_cb (gözle)   SVA + cover property |
         +-->|                  DUT: ahb_lite_slave                  |
             +------------------------------------------------------+
```

### 2.3 Component görevleri

| Component | Taban sınıf | Görev |
|---|---|---|
| `ahb_seq_item` | `uvm_sequence_item` | Bir AHB transfer'ini veri olarak taşır (addr, wdata, write, size, rdata, resp). |
| `ahb_sequencer` | `uvm_sequencer` | Sequence'ler ile driver arasında trafik yönlendirir. |
| `ahb_driver` | `uvm_driver` | seq_item'ı AHB pipeline'ına uygun pin sürmesine çevirir. |
| `ahb_monitor` | `uvm_monitor` | Pinleri pasifçe gözler, tamamlanan transfer'i `ap` ile yayınlar. |
| `ahb_agent` | `uvm_agent` | sqr+drv+mon demeti (ACTIVE: üçü; PASSIVE: sadece mon). |
| `ahb_scoreboard` | `uvm_scoreboard` | Referans modelle karşılaştırıp PASS/FAIL üretir. |
| `ahb_coverage` | `uvm_subscriber` | covergroup örnekleyerek functional coverage toplar. |
| `ahb_env` | `uvm_env` | agent+scoreboard+coverage'ı birleştirir, bağlantıları kurar. |
| `ahb_base_test` | `uvm_test` | env'i kurar, topoloji + PASS/FAIL raporu basar. |

### 2.4 Veri akışı

- **Stimulus yolu (aşağı):** test → sequence → sequencer → driver → `ahb_if` pinleri → DUT.
- **Kontrol/gözlem yolu (yukarı):** DUT pinleri → monitor (`mon_cb`) → `ap` (analysis_port) → **broadcast** → scoreboard *ve* coverage.
- Tek bir monitor portu (`agent.mon.ap`) iki aboneye bağlıdır (`sb.ap_imp`, `cov.analysis_export`) — analysis port'un çok-dinleyicili yayın özelliği.

### 2.5 AHB pipeline üç yerde görünür

AHB pipelined bir bustur: adres cycle N'de, o adrese ait veri cycle N+1'de gelir.
Bu tek gerçek, tasarımın üç ayrı yerinde karşımıza çıkar:

| Yer | Nasıl | Amaç |
|---|---|---|
| DUT (`ahb_lite_slave`) | `addr_d` register'ı | Adres fazında yakalanan adresi, data fazında kullanmak için saklar. |
| Monitor (`ahb_monitor`) | `pending` değişkeni | Adres fazını gördüğünde açar, data fazında (sonraki cycle) kapatıp veriyi doldurur. |
| SVA (`ahb_if`) | `\|=>` operatörü | `a_wdata_no_x`: HWDATA'nın bir sonraki cycle'da geçerli olmasını kontrol eder. |

---

## 3. Assertion Listesi

Assertion'lar `testbench.sv`'nin interface bölümünde, `default clocking
@(posedge HCLK)` ve `default disable iff (!HRESETn)` altında tanımlıdır.

| İsim | Kural | Operatör | Durum | Not |
|---|---|---|---|---|
| `a_addr_align` | Adres, HSIZE'a göre hizalı olmalı | `\|->` | AKTİF | `ahb_align_error_test` ile ateşlediği kanıtlandı |
| `a_ctrl_stable` | HREADY=0 iken adres-faz sinyalleri sabit | `\|=>` | TETİKLENMEDİ | DUT'ta wait state yok (HREADY hep 1) → vacuous pass |
| `a_no_x` | Geçerli transfer'de HADDR/HSIZE X/Z değil | `\|->` | AKTİF | — |
| `a_wdata_no_x` | Write data fazında HWDATA geçerli | `\|=>` | AKTİF | Pipeline nedeniyle `\|=>` (veri bir cycle sonra) |
| `a_htrans_legal` | HTRANS 4 geçerli değerden biri | — | AKTİF | X yakalar |

**Cover property'ler** (aynı dosyada, kapsama ölçümü için):

| İsim | Ne sayar | Sonuç |
|---|---|---|
| `c_write_txn` | Yazma transfer'i gerçekleşti | Covered (76) |
| `c_read_txn` | Okuma transfer'i gerçekleşti | Covered (65) |
| `c_b2b_txn` | Ardışık iki cycle'da geçerli adres fazı (back-to-back) | **ZERO (0)** — bkz. Bölüm 5 |
| `c_idle_gap` | NONSEQ ardından IDLE (tek transfer boşluğu) | Covered (141) |

---

## 4. Test Senaryoları ve Sonuçları

Her test EDA Playground'da `+UVM_TESTNAME` ile ayrı ayrı koşulur.

### 4.1 PASS/FAIL özeti (birebir çıktı)

Her test EDA Playground'da ayrı koşulur; aşağıda her testin bastığı
`AHB_RESULT` satırı toplu gösterilmiştir (tek koşumda birleşik tablo
üretilmez).

```
AHB_RESULT test=ahb_smoke_test UVM_ERROR=0 UVM_FATAL=0 PASS
AHB_RESULT test=ahb_write_read_test UVM_ERROR=0 UVM_FATAL=0 PASS
AHB_RESULT test=ahb_random_test UVM_ERROR=0 UVM_FATAL=0 PASS
AHB_RESULT test=ahb_b2b_test UVM_ERROR=0 UVM_FATAL=0 PASS
AHB_RESULT test=ahb_walking_test UVM_ERROR=0 UVM_FATAL=0 PASS
AHB_RESULT test=ahb_regression_test UVM_ERROR=0 UVM_FATAL=0 PASS
```

### 4.2 Scoreboard sayımları ve her testin amacı

| Test | Scoreboard | Ne test eder |
|---|---|---|
| `ahb_smoke_test` | WRITE=1 READ=1 PASS=1 FAIL=0 SKIP=0 | Temel bir yazma+okuma; altyapının uçtan uca çalışması. |
| `ahb_write_read_test` | WRITE=3 READ=3 PASS=3 FAIL=0 SKIP=0 | 3 farklı adrese parametrik yazma+okuma (rastgele wdata). |
| `ahb_random_test` | WRITE=27 READ=14 PASS=11 FAIL=0 SKIP=3 | Constraint'li rastgele trafik; SKIP=3 = yazılmamış adres okuması (normal). |
| `ahb_b2b_test` | WRITE=4 READ=4 PASS=4 FAIL=0 SKIP=0 | Ardışık transfer akışı; monitor'ün transfer kaybetmediğini doğrular. |
| `ahb_walking_test` | WRITE=16 READ=16 PASS=16 FAIL=0 SKIP=0 | Tüm 16 adrese benzersiz pattern; adres decode hatası taraması. |
| `ahb_regression_test` | WRITE=25 READ=27 PASS=27 FAIL=0 SKIP=0 | walking→b2b→random (nested sequence); tümü tek koşuda. |

`ahb_random_test` seed'e bağlıdır; üç farklı seed ile trafik değişir ama sonuç
her seferinde FAIL=0:

```
seed=1     -> WRITE=22 READ=19 PASS=12 FAIL=0 SKIP=7
seed=12345 -> WRITE=9  READ=14 PASS=2  FAIL=0 SKIP=12
seed=99999 -> WRITE=22 READ=18 PASS=5  FAIL=0 SKIP=13
```

---

## 5. Coverage Sonuçları

Tüm testler birleştirilerek (UCDB merge) alınan özet. Kod coverage yalnızca DUT
için ölçülmüştür (UVM kütüphanesi enstrümante edilmedi).

> Aşağıdaki tablolar yerel Questa 2025.2'de UCDB merge ile alınmıştır;
> EDA Playground'da tekrar üretilemez.

```
    Enabled Coverage              Bins      Hits    Misses    Weight  Coverage
    ----------------              ----      ----    ------    ------  --------
    Assertions                       5         4         1         1    80.00%
    Branches                         7         6         1         1    85.71%
    Conditions                       2         1         1         1    50.00%
    Covergroups                      1        na        na         1   100.00%
        Covergroup Bins             15        15         0         1   100.00%
    Directives                       4         3         1         1    75.00%
    Statements                       9         9         0         1   100.00%
Total coverage (filtered view): 81.78%
```

Cover directive detayı:

```
c_write_txn   76  Covered
c_read_txn    65  Covered
c_b2b_txn      0  ZERO
c_idle_gap   141  Covered
```

`ahb_regression_test` sonrası functional coverage (covergroup) = **%100.00**.

### 5.1 Eksiklerin sebebi (tek bir kök neden)

Üç ayrı metrikteki eksik, **aynı** bilinçli kapsam sınırlamasından kaynaklanır —
DUT'ta wait state yok ve driver pipelined değil:

| Metrik | Eksik | Sebep |
|---|---|---|
| Assertions 4/5 | `a_ctrl_stable` tetiklenmedi | Önkoşulu `!HREADY`; HREADY hep 1 → vacuous |
| Branches 6/7 | 1 branch çalışmadı | DUT'un HREADY=0 (wait state) dalı hiç uyarılmadı |
| Directives 3/4 | `c_b2b_txn` = 0 | Driver non-pipelined; transfer'ler arasında idle var |

Bunlar hata değil, kapsam kararının doğal ve **tutarlı** sonucudur. Wait state ve
pipelined driver eklenirse üçü de canlanır.

### 5.2 Code coverage vs functional coverage

DUT statement coverage **%100** olmasına rağmen `c_b2b_txn = 0`'dır: yani DUT'un
her satırı çalıştı ama "back-to-back" senaryosu **hiç test edilmedi**. Bu, %100
code coverage'ın tek başına yeterli olmadığını gösterir — code coverage "nereye
dokunmadık", functional coverage "hangi senaryoyu denemedik" sorularını yanıtlar;
ikisi birbirini tamamlar.

---

## 6. Karşılaşılan Zorluklar ve Çözümler

1. **AHB pipeline (veri, adresten bir cycle sonra).** HWDATA'nın adresin bir
   cycle sonrasında gelmesi; adresi saklamadan yazmak yanlış adrese yazmaya yol
   açar. Çözüm: DUT'ta `addr_d` register'ı, monitor'de `pending`, driver'da
   adres/data fazı ayrımı.

2. **Monitor'de "önce kapat sonra aç" sırası.** Bir transfer'in data fazı ile bir
   sonrakinin adres fazı aynı cycle'a düşebildiğinden, `pending`'i önce
   kapatmadan yeni transfer'i açmak kayba yol açar. Kod bu sırayı bilinçli korur.

3. **Sıra-ters testinin beklenmedik sonucu (dürüst kayıt).** Monitor bloklarını
   ters çevirince "transfer kaybı (sayı<4)" bekleniyordu; gerçekte **data
   bozulması** (WRITE=4 READ=4 ama FAIL=1) çıktı. Sebep: driver non-pipelined
   olduğundan transfer'ler arasında idle var; aynı-cycle çakışması oluşmuyor.
   Transfer kaybı ancak gerçek pin-seviyesi back-to-back'te (pipelined driver)
   görülür. İki durum da "sıra kritik"i kanıtlar, ama başarısızlık farklı
   biçimde görünür.

4. **Questa DPI / gcc linkleme (yerel ortam).** Yeni OS (glibc 2.39) ile
   Questa'nın paketlediği eski gcc-10.3 linker'ı DPI linklerken çakıştı
   (`.relr.dyn`). Çözüm: `vsim -cpppath /usr/bin/gcc` ile sistem gcc'sine
   yönlendirme. Bu sadece yerel koşum içindir; EDA Playground'da gerekmez.

---

## 7. Doğrulama Kanıtı

Doğrulama altyapısına körlemesine güvenilmedi; sessizliğin "kural sağlanıyor" mı
"checker ölü" mü olduğunu ayırmak için bir negatif test (kodda) ve iki manuel
bozma deneyi yapıldı.

### 7.1 Scoreboard gerçekten kontrol ediyor mu? (bozuk-DUT)

> **Not:** Bu deney geçici bir değişiklikle yapılmış, değişiklik geri
> alınmıştır; repoda kod karşılığı yoktur.

DUT'un `HRDATA`'sı geçici olarak `^ 32'h1` ile bozuldu:

```
UVM_ERROR [SB] MISMATCH addr=0x00000010 exp=0xa5a51234 got=0xa5a51235
SCOREBOARD SUMMARY: WRITE=1 READ=1 PASS=0 FAIL=1 SKIP=0
UVM_ERROR [SB] SCOREBOARD FAILED with 1 mismatch(es)
UVM_ERROR :    2
```

### 7.2 Monitor sıra mantığı önemli mi? (bloklar ters)

> **Not:** Bu deney geçici bir değişiklikle yapılmış, değişiklik geri
> alınmıştır; repoda kod karşılığı yoktur.

Monitor'ün "kapat/aç" blokları ters çevrilip `ahb_b2b_test` koşuldu:

```
[MON] WRITE addr=0x00000000 wdata=0x00000000
[MON] WRITE addr=0x00000004 wdata=0xa7591fda
UVM_ERROR [SB] MISMATCH addr=0x00000000 exp=0x00000000 got=0x58b10bc2
SCOREBOARD SUMMARY: WRITE=4 READ=4 PASS=3 FAIL=1 SKIP=0
UVM_ERROR :    2
```

Write verisi bir transfer kaymış olarak yakalandı → data bozulması.

### 7.3 Assertion gerçekten ateşliyor mu? (bilerek hizasız adres)

`ahb_align_error_test`, `addr=0x11 size=word` (hizasız) sürer; ayrı koşulur ve
FAIL etmesi beklenir:

```
UVM_ERROR testbench.sv @ 45 ns: [SVA] a_addr_align: unaligned addr=0x00000011 for HSIZE=0b010
AHB_RESULT test=ahb_align_error_test UVM_ERROR=1 UVM_FATAL=0 FAIL
```

**Prensip:** sessiz kalan bir checker, kural sağlandığı için değil, hiç çalışmadığı
için de sessiz olabilir. Her checker en az bir kez kasıtlı hata ile uyarılıp
yakaladığı görülmelidir.

---

## 8. Kapsam Dışı ve Gelecek Çalışmalar

Aşağıdakiler bu projede **bilinçli olarak yapılmadı**:

- **Burst (INCR/WRAP), wait state, ERROR response.** Wait state eklenirse
  `a_ctrl_stable` ve eksik DUT branch'i canlanır.
- **Pipelined driver.** Gerçek pin-seviyesi back-to-back üretir; `c_b2b_txn`
  vurulur ve sıra-ters monitor testi "transfer kaybı" gösterir. Not: pipelined
  driver, read verisinin sequence'e senkron dönmesini değiştirir (veri artık
  scoreboard üzerinden doğrulanır).
- **Çoklu slave / interconnect.** VIP mimarisini kökten değiştirmez; decoder +
  response mux eklenir ve monitor'e HSEL bazlı slave takibi yazılır.
- **RAL (register abstraction layer) ve virtual sequence.** Tek agent olduğu için
  gerekmedi; çok-agent'a geçişte anlamlı olur.

---

## 9. Referanslar

- ARM, *AMBA 3 AHB-Lite Protocol Specification*, ARM IHI 0033.
- Accellera, *Universal Verification Methodology (UVM) 1.2 User's Guide / Class
  Reference*.
- IEEE Std 1800-2012, *SystemVerilog — Unified Hardware Design, Specification, and
  Verification Language*.

> Not: DUT (`ahb_lite_slave.sv`) bu proje kapsamında eğitim amaçlı sıfırdan
> yazılmıştır; harici bir açık kaynak RTL kullanılmamıştır.
