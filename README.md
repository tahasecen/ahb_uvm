# AMBA AHB-Lite UVM Verification IP

AMBA **AHB-Lite** protokolü için UVM 1.2 tabanlı bir Verification IP (VIP).
Bir AHB-Lite slave DUT'unu sürer, gözler, referans modelle karşılaştırır ve
SVA assertion + functional coverage ile protokol/kapsama kontrolü yapar.

- **Dil / metodoloji:** SystemVerilog (IEEE 1800-2012), UVM 1.2
- **Simülatör:** Siemens Questa 2025.2
- **Koşum ortamı:** EDA Playground (yerel `.do` akışı bu repoda yer almaz)
- Ayrıntılı rapor: [docs/AHB_VIP_Raporu.md](docs/AHB_VIP_Raporu.md)
- Test prosedürleri: [docs/AHB_VIP_Test_Prosedurleri.md](docs/AHB_VIP_Test_Prosedurleri.md)

## Mimari

![AHB VIP mimari diyagramı](docs/AHB_VIP_BD-1-UVM%20Hiyerarsi.png)

*UVM bileşen hiyerarşisi ve TLM bağlantıları*

![AHB VIP veri akışı diyagramı](docs/AHB_VIP_BD-2-Veri%20Akisi.png)

*Stimulus ve gözlem yolları: sequence → driver → DUT → monitor → scoreboard/coverage*

![AHB pipeline diyagramı](docs/AHB_VIP_BD-3-AHB%20Pipeline.png)

*AHB adres/veri pipeline'ı: veriler adresten bir cycle sonra gelir*

Diyagramların kaynak dosyası: [docs/AHB_VIP_BD.drawio](docs/AHB_VIP_BD.drawio) (draw.io ile açılır).

## Dizin yapısı

```
.
├── hdl/
│   ├── design.sv                          ahb_lite_slave (DUT)
│   └── testbench.sv                       ahb_if + ahb_pkg + tb_top (tek dosya)
├── docs/
│   ├── AHB_VIP_Raporu.md                  Teslim raporu (mimari, assertion, test, coverage)
│   ├── AHB_VIP_Test_Prosedurleri.md       Test başına koşum + dalga inceleme rehberi
│   └── AHB_VIP_BD.drawio                  Blok diyagram kaynağı (render'ı: Mimari bölümü)
└── README.md
```

## Nasıl çalıştırılır

### EDA Playground (asıl teslim ortamı)

1. **Design** panosuna `hdl/design.sv` içeriğini yapıştır.
2. **Testbench** panosuna `hdl/testbench.sv` içeriğini yapıştır.
3. Ayarlar:
   - Simulator: **Siemens Questa 2025.2**
   - UVM/OVM: **UVM 1.2**
   - Compile options: `-sv +cover=bcs -coverage`
   - Run options: `+UVM_TESTNAME=ahb_regression_test +UVM_VERBOSITY=UVM_MEDIUM`
   - **[x] Open EPWave after run**

4. **Run**. Başka bir test için `+UVM_TESTNAME` değerini değiştir.

Dalga penceresi için "Open EPWave after run" işaretli olmalı; `tb_top`
`dump.vcd` üretir. Test başına "neye bakılacak" için:
[docs/AHB_VIP_Test_Prosedurleri.md](docs/AHB_VIP_Test_Prosedurleri.md).


## Test listesi

| Test | Ne test eder |
|---|---|
| `ahb_smoke_test` | Temel yazma+okuma, uçtan uca altyapı |
| `ahb_write_read_test` | 3 adrese parametrik yazma+okuma |
| `ahb_random_test` | Constraint'li rastgele trafik (seed'e bağlı) |
| `ahb_b2b_test` | Ardışık transfer akışı |
| `ahb_walking_test` | Tüm 16 adres taraması (decode kontrolü) |
| `ahb_regression_test` | Hepsi tek koşuda (nested sequence) |
| `ahb_align_error_test` | **Negatif** — hizasız adres, `a_addr_align`'i ateşler (FAIL beklenir) |

Beklenen sonuç: `ahb_align_error_test` dışındaki tüm testler `UVM_ERROR=0` ile
PASS; regression sonrası functional coverage **%100**.
