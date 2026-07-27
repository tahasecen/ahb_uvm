//======================================================================
// File   : testbench.sv  (EDA Playground "Testbench" pane)
// Brief  : AHB-Lite UVM VIP -- interface + package + top module merged
//          into ONE file, in dependency order (interface, then package,
//          then module). The DUT lives in the "Design" pane (design.sv).
//
// ---- EDA Playground settings -------------------------------------
//   Simulator : Siemens Questa 2025.2
//   UVM/OVM   : UVM 1.2
//   Run opts  : +UVM_TESTNAME=ahb_regression_test +UVM_VERBOSITY=UVM_MEDIUM
//   Compile   : -sv +cover=bcs -coverage
//   [x] Open EPWave after run
//
//   Other selectable tests (change +UVM_TESTNAME):
//     ahb_smoke_test  ahb_write_read_test  ahb_random_test
//     ahb_b2b_test    ahb_walking_test     ahb_regression_test
//     ahb_align_error_test   (NEGATIVE test -- expected to FAIL: it drives
//                             an unaligned address to fire a_addr_align)
//======================================================================


// ==================== PART 1/3: INTERFACE ====================
//======================================================================
// Brief  : AHB-Lite signal bundle (interface) + clocking blocks for the
//          UVM VIP. drv_cb is used by the driver, mon_cb by the monitor.
//======================================================================
`timescale 1ns/1ps

interface ahb_if (input logic HCLK, input logic HRESETn);

  // UVM is imported ONLY so assertion failures can report through the same
  // UVM error counter as the rest of the testbench (see the assertions at
  // the bottom). The signal bundle / clocking blocks stay pure pin-level.
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // ---- AHB-Lite signal bundle -------------------------------------
  // Plain nets, driven/sampled through the clocking blocks.
  logic        HSEL;
  logic        HWRITE;
  logic        HREADY;     // driven from the slave's HREADYOUT in tb_top
  logic [1:0]  HTRANS;
  logic [2:0]  HSIZE;
  logic [2:0]  HBURST;
  logic [31:0] HADDR;
  logic [31:0] HWDATA;
  logic [31:0] HRDATA;
  logic        HRESP;

  // ---- Driver clocking block --------------------------------------
  // Without a clocking block, a TB drive and a DUT sample at the same
  // instant race and the sampled value is undefined.
  // Sampled before the edge, driven after -> no TB/DUT race.
  clocking drv_cb @(posedge HCLK);
    default input #1step output #1;
    output HSEL, HADDR, HWRITE, HSIZE, HBURST, HTRANS, HWDATA;
    input  HRDATA, HREADY, HRESP;
  endclocking

  // ---- Monitor clocking block -------------------------------------
  // The monitor is PASSIVE: it only samples, it drives nothing. So every
  // signal is 'input' here, all sampled with the same #1step skew.
  clocking mon_cb @(posedge HCLK);
    default input #1step;
    input HSEL, HADDR, HWRITE, HSIZE, HBURST, HTRANS, HWDATA,
          HRDATA, HREADY, HRESP;
  endclocking

  // ---- Modports ----------------------------------------------------
  // The driver connects through DRV, the monitor through MON -- so the
  // monitor physically cannot drive the bus, enforced by the compiler.
  modport DRV (clocking drv_cb);
  modport MON (clocking mon_cb);

  //====================================================================
  // CONCURRENT SVA ASSERTIONS  (pin/protocol-level checks)
  // These live in the interface because that is exactly the pin boundary
  // the protocol rules apply to.
  //
  //   default clocking @(posedge HCLK) : all properties below sample here.
  //   default disable iff (!HRESETn)   : all are switched OFF during reset
  //                                      (signals are not meaningful then).
  //====================================================================
  default clocking @(posedge HCLK); endclocking
  default disable iff (!HRESETn);

  // 1) Address alignment must match the transfer size (AHB rule).
  //    Alignment is a property of the address phase itself.
  property p_addr_align;
    (HSEL && HTRANS[1] && HREADY) |->
      ((HSIZE == 3'b010) -> (HADDR[1:0] == 2'b00)) and
      ((HSIZE == 3'b001) -> (HADDR[0]   == 1'b0));
  endproperty
  a_addr_align: assert property (p_addr_align)
    else `uvm_error("SVA",
      $sformatf("a_addr_align: unaligned addr=0x%08h for HSIZE=0b%03b",
                HADDR, HSIZE))

  // 2) While HREADY is low (a wait state), the address-phase controls must
  //    hold steady until the transfer is accepted.
  //    NOTE: our DUT ties HREADYOUT=1, so !HREADY never happens -> this
  //    assertion is vacuously true (its trigger never fires). It is here so
  //    that when wait states are added later, the check already exists.
  property p_ctrl_stable;
    (HSEL && HTRANS[1] && !HREADY) |=>
      $stable(HADDR) && $stable(HWRITE) && $stable(HTRANS) && $stable(HSIZE);
  endproperty
  a_ctrl_stable: assert property (p_ctrl_stable)
    else `uvm_error("SVA", "a_ctrl_stable: control changed during a wait state")

  // 3) During a valid address phase, address/size must not be X/Z.
  property p_no_x;
    (HSEL && HTRANS[1] && HREADY) |->
      (!$isunknown(HADDR) && !$isunknown(HSIZE));
  endproperty
  a_no_x: assert property (p_no_x)
    else `uvm_error("SVA", "a_no_x: HADDR/HSIZE is X/Z during a valid transfer")

  // 4) Write data must be valid. Checked the cycle after the trigger: in
  //    AHB the write DATA phase is one cycle after the ADDRESS phase.
  property p_wdata_no_x;
    (HSEL && HTRANS[1] && HREADY && HWRITE) |=> !$isunknown(HWDATA);
  endproperty
  a_wdata_no_x: assert property (p_wdata_no_x)
    else `uvm_error("SVA", "a_wdata_no_x: HWDATA is X/Z in the write data phase")

  // 5) HTRANS must always be one of the 4 legal encodings (also catches X).
  property p_htrans_legal;
    HTRANS inside {2'b00, 2'b01, 2'b10, 2'b11};
  endproperty
  a_htrans_legal: assert property (p_htrans_legal)
    else `uvm_error("SVA",
      $sformatf("a_htrans_legal: illegal HTRANS=0b%02b", HTRANS))

  //====================================================================
  // COVER PROPERTIES  (did these scenarios actually occur? -> coverage)
  //====================================================================
  c_write_txn: cover property (HSEL && HTRANS[1] && HREADY &&  HWRITE);
  c_read_txn:  cover property (HSEL && HTRANS[1] && HREADY && !HWRITE);
  // Two valid address phases in CONSECUTIVE cycles = true back-to-back.
  // With our non-pipelined driver (idle between transfers) this should
  // NEVER be covered.
  c_b2b_txn:   cover property ((HSEL && HTRANS[1]) ##1 (HSEL && HTRANS[1]));
  // A NONSEQ address phase followed by IDLE next cycle (single-transfer gap).
  c_idle_gap:  cover property ((HTRANS == 2'b10) ##1 (HTRANS == 2'b00));

endinterface

// ==================== PART 2/3: PACKAGE ====================
//======================================================================
// Brief  : UVM package for the AHB-Lite VIP. Holds the sequence item,
//          agent, sequences, scoreboard, coverage, env and tests.
//======================================================================
`timescale 1ns/1ps

package ahb_pkg;

  // UVM base classes + the `uvm_* macros must be visible in this package.
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // AHB HTRANS encodings, named for readability.
  localparam bit [1:0] HTRANS_IDLE   = 2'b00;
  localparam bit [1:0] HTRANS_BUSY   = 2'b01;
  localparam bit [1:0] HTRANS_NONSEQ = 2'b10;
  localparam bit [1:0] HTRANS_SEQ    = 2'b11;
  localparam bit [2:0] HBURST_SINGLE = 3'b000;

  //====================================================================
  // 1) SEQUENCE ITEM
  //    One AHB transfer described as pure data (address, data, dir...).
  //====================================================================
  class ahb_seq_item extends uvm_sequence_item;

    // Stimulus fields: the sequence chooses these (randomizable).
    rand bit [31:0] addr;
    rand bit [31:0] wdata;
    rand bit        write;     // 1 = write, 0 = read
    rand bit [2:0]  size;      // AHB HSIZE

    // Response fields: the driver/monitor fills these, so NOT rand.
    bit [31:0] rdata;          // read data returned by the DUT
    bit        resp;           // HRESP captured (0 = OKAY)

    // Factory + automation (copy/print/compare/pack).
    `uvm_object_utils_begin(ahb_seq_item)
      `uvm_field_int(addr,  UVM_ALL_ON)
      `uvm_field_int(wdata, UVM_ALL_ON)
      `uvm_field_int(write, UVM_ALL_ON)
      `uvm_field_int(size,  UVM_ALL_ON)
      `uvm_field_int(rdata, UVM_ALL_ON)
      `uvm_field_int(resp,  UVM_ALL_ON)
    `uvm_object_utils_end

    // Only word transfers (soft => a test can override).
    constraint c_size { soft size == 3'b010; }

    // Address alignment must match the transfer size (AHB rule).
    constraint c_align {
      (size == 3'b010) -> addr[1:0] == 2'b00;   // word     => 4-byte aligned
      (size == 3'b001) -> addr[0]   == 1'b0;     // halfword => 2-byte aligned
    }

    // Keep inside our 16-word memory window (0x00..0x3C, word 0..15).
    constraint c_range { addr inside {[32'h0000_0000 : 32'h0000_003C]}; }

    function new(string name = "ahb_seq_item");
      super.new(name);
    endfunction

    // Human-readable one-liner for the log.
    virtual function string convert2string();
      return $sformatf("%s addr=0x%08h size=0b%03b wdata=0x%08h rdata=0x%08h resp=%0b",
                       (write ? "WRITE" : "READ "), addr, size, wdata, rdata, resp);
    endfunction

  endclass

  //====================================================================
  // 2) SEQUENCER
  //    Standard sequencer, parameterized on ahb_seq_item.
  //====================================================================
  class ahb_sequencer extends uvm_sequencer #(ahb_seq_item);
    `uvm_component_utils(ahb_sequencer)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  //====================================================================
  // 3) DRIVER
  //    Converts an abstract ahb_seq_item into pin wiggles on the bus,
  //    honoring the AHB address/data pipeline.
  //====================================================================
  class ahb_driver extends uvm_driver #(ahb_seq_item);
    `uvm_component_utils(ahb_driver)

    // Handle to the physical interface (the "class world -> module world"
    // bridge). Set by the test via the config_db; grabbed in build_phase.
    virtual ahb_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(),
                   "Virtual interface 'vif' not found in config_db")
    endfunction

    // Park the bus in a legal idle state.
    task reset_signals();
      vif.drv_cb.HSEL   <= 1'b0;
      vif.drv_cb.HTRANS <= HTRANS_IDLE;
      vif.drv_cb.HADDR  <= 32'h0;
      vif.drv_cb.HWRITE <= 1'b0;
      vif.drv_cb.HSIZE  <= 3'b010;
      vif.drv_cb.HBURST <= HBURST_SINGLE;
      vif.drv_cb.HWDATA <= 32'h0;
    endtask

    // Drive ONE transfer, respecting the AHB pipeline:
    //   ADDRESS phase (cycle N)  : present HADDR/HWRITE/HTRANS
    //   DATA    phase (cycle N+1): present/collect HWDATA/HRDATA
    task drive_transfer(ahb_seq_item req);
      // ---- ADDRESS PHASE ----
      @(vif.drv_cb);                        // sync to a driver clock edge
      vif.drv_cb.HSEL   <= 1'b1;
      vif.drv_cb.HADDR  <= req.addr;
      vif.drv_cb.HWRITE <= req.write;
      vif.drv_cb.HSIZE  <= req.size;
      vif.drv_cb.HBURST <= HBURST_SINGLE;
      vif.drv_cb.HTRANS <= HTRANS_NONSEQ;
      // Address phase is accepted on the first edge where HREADY is high.
      do @(vif.drv_cb); while (!vif.drv_cb.HREADY);

      // ---- DATA PHASE (one cycle after the address) ----
      vif.drv_cb.HTRANS <= HTRANS_IDLE;     // no follow-up transfer
      vif.drv_cb.HSEL   <= 1'b0;
      if (req.write)
        vif.drv_cb.HWDATA <= req.wdata;     // write data lives in this phase
      // Data phase completes on the next edge where HREADY is high.
      do @(vif.drv_cb); while (!vif.drv_cb.HREADY);

      // For a read, HRDATA is valid now -> hand it back through the item.
      if (!req.write)
        req.rdata = vif.drv_cb.HRDATA;
      req.resp = vif.drv_cb.HRESP;
    endtask

    task run_phase(uvm_phase phase);
      reset_signals();
      @(posedge vif.HRESETn);               // wait for reset de-assert
      @(vif.drv_cb);                        // align to a clean edge
      forever begin
        seq_item_port.get_next_item(req);
        drive_transfer(req);
        seq_item_port.item_done();
      end
    endtask

  endclass

  //====================================================================
  // 3b) MONITOR
  //    PASSIVE observer. It NEVER drives the bus -- it only SAMPLES pins
  //    through mon_cb and reconstructs each completed AHB transfer as an
  //    ahb_seq_item, then broadcasts it on its analysis port, so checking
  //    is independent of the driver's own view of the transfer.
  //====================================================================
  class ahb_monitor extends uvm_monitor;
    `uvm_component_utils(ahb_monitor)

    virtual ahb_if vif;

    // Broadcast channel to the scoreboard and coverage subscribers.
    uvm_analysis_port #(ahb_seq_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual ahb_if)::get(this, "", "vif", vif))
        `uvm_fatal(get_type_name(),
                   "Virtual interface 'vif' not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
      // 'pending' holds a transfer whose ADDRESS phase we already saw and
      // whose DATA phase we are still waiting for -- the monitor-side echo
      // of the AHB pipeline (address now, data one accepted cycle later).
      ahb_seq_item pending;
      pending = null;

      forever begin
        @(vif.mon_cb);                 // sample on every rising edge

        // A phase only "counts" on cycles where HREADY is high (the bus
        // actually advanced). During wait states nothing is committed.
        if (vif.mon_cb.HREADY) begin

          // ---- STEP 1: CLOSE the previous transfer FIRST ----------------
          // If we captured an address last accepted cycle, THIS cycle is
          // its data phase -> grab the data/response and publish it.
          //
          // ORDER MATTERS: close before open. On a back-to-back
          // stream, the DATA phase of transfer N and the ADDRESS phase of
          // transfer N+1 fall in the SAME cycle. If we opened first we would
          // overwrite 'pending' and silently LOSE transfer N.
          if (pending != null) begin
            if (pending.write) pending.wdata = vif.mon_cb.HWDATA;
            else               pending.rdata = vif.mon_cb.HRDATA;
            pending.resp = vif.mon_cb.HRESP;
            ap.write(pending);         // broadcast the completed transfer
            `uvm_info("MON", pending.convert2string(), UVM_MEDIUM)
            pending = null;
          end

          // ---- STEP 2: OPEN a new transfer SECOND -----------------------
          // A valid address phase = this slave selected AND a real
          // transfer type (HTRANS[1] => NONSEQ or SEQ, not IDLE/BUSY).
          if (vif.mon_cb.HSEL && vif.mon_cb.HTRANS[1]) begin
            pending = ahb_seq_item::type_id::create("mon_item");
            pending.addr  = vif.mon_cb.HADDR;
            pending.write = vif.mon_cb.HWRITE;
            pending.size  = vif.mon_cb.HSIZE;
          end

        end
      end
    endtask

  endclass

  //====================================================================
  // 4) SEQUENCE: single directed WRITE (addr 0x10 <= 0xA5A5_1234)
  //====================================================================
  class ahb_single_write_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_single_write_seq)

    function new(string name = "ahb_single_write_seq");
      super.new(name);
    endfunction

    virtual task body();
      ahb_seq_item req;
      req = ahb_seq_item::type_id::create("req");
      start_item(req);
      req.write = 1'b1;
      req.addr  = 32'h0000_0010;
      req.wdata = 32'hA5A5_1234;
      req.size  = 3'b010;       // word
      finish_item(req);
      `uvm_info("SEQ", $sformatf("Sent %s", req.convert2string()), UVM_LOW)
    endtask
  endclass

  //====================================================================
  // 5) SEQUENCE: single directed READ (addr 0x10) + report result
  //====================================================================
  class ahb_single_read_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_single_read_seq)

    function new(string name = "ahb_single_read_seq");
      super.new(name);
    endfunction

    virtual task body();
      ahb_seq_item req;
      req = ahb_seq_item::type_id::create("req");
      start_item(req);
      req.write = 1'b0;         // READ
      req.addr  = 32'h0000_0010;
      req.size  = 3'b010;
      finish_item(req);         // after this returns, req.rdata is filled
      `uvm_info("SEQ", $sformatf("Read back addr=0x%08h rdata=0x%08h",
                req.addr, req.rdata), UVM_LOW)
    endtask
  endclass

  //====================================================================
  // 5a) SEQUENCE: write-then-read the SAME (parametric) address.
  //     target_addr is a rand field the test can set OR randomize.
  //     The write uses RANDOM data; the read checks it via scoreboard.
  //====================================================================
  class ahb_write_read_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_write_read_seq)

    rand bit [31:0] target_addr;
    // Default legal target: word-aligned, inside our memory window.
    constraint c_target {
      target_addr inside {[32'h0000_0000 : 32'h0000_003C]};
      target_addr[1:0] == 2'b00;
    }

    function new(string name = "ahb_write_read_seq");
      super.new(name);
    endfunction

    virtual task body();
      ahb_seq_item req;
      bit [31:0]   wdata_used;

      // WRITE: random data to target_addr.
      req = ahb_seq_item::type_id::create("wr");
      start_item(req);
      if (!req.randomize() with { write == 1'b1;
                                  addr  == target_addr;
                                  size  == 3'b010; })
        `uvm_fatal("SEQ", "write randomize failed")
      wdata_used = req.wdata;
      finish_item(req);

      // READ: same address back.
      req = ahb_seq_item::type_id::create("rd");
      start_item(req);
      if (!req.randomize() with { write == 1'b0;
                                  addr  == target_addr;
                                  size  == 3'b010; })
        `uvm_fatal("SEQ", "read randomize failed")
      finish_item(req);

      `uvm_info("SEQ", $sformatf("W/R addr=0x%08h wrote=0x%08h read=0x%08h",
                target_addr, wdata_used, req.rdata), UVM_MEDIUM)
    endtask
  endclass

  //====================================================================
  // 5b) SEQUENCE: N fully-random transfers (write/read mix, random addr).
  //     num_txn is rand; a test must randomize this sequence or it stays 0.
  //====================================================================
  class ahb_random_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_random_seq)

    rand int unsigned num_txn;
    constraint c_num { num_txn inside {[10:50]}; }

    function new(string name = "ahb_random_seq");
      super.new(name);
    endfunction

    virtual task body();
      ahb_seq_item req;
      `uvm_info("SEQ", $sformatf("random_seq: %0d transfers", num_txn), UVM_LOW)
      repeat (num_txn) begin
        req = ahb_seq_item::type_id::create("rnd");
        start_item(req);
        // No inline constraints -> the item's OWN constraints (c_size,
        // c_align, c_range) fully define a legal random transfer.
        if (!req.randomize())
          `uvm_fatal("SEQ", "random transfer randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  //====================================================================
  // 5c) SEQUENCE: back-to-back stream (NO delay between finish_items).
  //     PURPOSE: stress the monitor's pending "close-before-open" logic.
  //     4 writes to distinct addrs, then 4 reads from the same addrs.
  //====================================================================
  class ahb_b2b_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_b2b_seq)

    function new(string name = "ahb_b2b_seq");
      super.new(name);
    endfunction

    virtual task body();
      ahb_seq_item req;
      bit [31:0]   addrs[4];
      addrs = '{32'h00, 32'h04, 32'h08, 32'h0C};

      // 4 WRITES, one immediately after another (no #delay anywhere).
      foreach (addrs[i]) begin
        req = ahb_seq_item::type_id::create($sformatf("b2b_w%0d", i));
        start_item(req);
        if (!req.randomize() with { write == 1'b1;
                                    addr  == addrs[i];
                                    size  == 3'b010; })
          `uvm_fatal("SEQ", "b2b write randomize failed")
        finish_item(req);
      end

      // 4 READS from the same addresses, again back-to-back.
      foreach (addrs[i]) begin
        req = ahb_seq_item::type_id::create($sformatf("b2b_r%0d", i));
        start_item(req);
        if (!req.randomize() with { write == 1'b0;
                                    addr  == addrs[i];
                                    size  == 3'b010; })
          `uvm_fatal("SEQ", "b2b read randomize failed")
        finish_item(req);
      end
    endtask
  endclass

  //====================================================================
  // 5d) SEQUENCE: walking address. Write a unique pattern to EVERY valid
  //     word address, then read them all back. Catches address-decode bugs
  //     (wrong-address write/read shows up as a scoreboard MISMATCH).
  //====================================================================
  class ahb_walking_addr_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_walking_addr_seq)

    function new(string name = "ahb_walking_addr_seq");
      super.new(name);
    endfunction

    virtual task body();
      ahb_seq_item req;

      // Phase 1: write addr ^ 0xDEAD0000 to each of the 16 words.
      for (int i = 0; i < 16; i++) begin
        bit [31:0] a = i * 4;                 // 0x00, 0x04, ... 0x3C
        req = ahb_seq_item::type_id::create($sformatf("walk_w%0d", i));
        start_item(req);
        req.write = 1'b1;
        req.addr  = a;
        req.size  = 3'b010;
        req.wdata = a ^ 32'hDEAD_0000;        // unique per-address pattern
        finish_item(req);
      end

      // Phase 2: read every address back (scoreboard verifies each).
      for (int i = 0; i < 16; i++) begin
        bit [31:0] a = i * 4;
        req = ahb_seq_item::type_id::create($sformatf("walk_r%0d", i));
        start_item(req);
        req.write = 1'b0;
        req.addr  = a;
        req.size  = 3'b010;
        finish_item(req);
      end
    endtask
  endclass

  //====================================================================
  // 5e) SEQUENCE: regression. Runs walking -> b2b -> random as nested
  //     sub-sequences.
  //====================================================================
  class ahb_regression_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_regression_seq)

    function new(string name = "ahb_regression_seq");
      super.new(name);
    endfunction

    virtual task body();
      ahb_walking_addr_seq wseq;
      ahb_b2b_seq          bseq;
      ahb_random_seq       rseq;

      wseq = ahb_walking_addr_seq::type_id::create("wseq");
      wseq.start(m_sequencer, this);

      bseq = ahb_b2b_seq::type_id::create("bseq");
      bseq.start(m_sequencer, this);

      rseq = ahb_random_seq::type_id::create("rseq");
      if (!rseq.randomize())
        `uvm_fatal("SEQ", "regression: rseq randomize failed")
      rseq.start(m_sequencer, this);
    endtask
  endclass

  //====================================================================
  // 6) SCOREBOARD
  //    Compares monitored read data against a golden reference model.
  //====================================================================
  class ahb_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(ahb_scoreboard)

    // Analysis imp: receives every transaction the monitor publishes.
    uvm_analysis_imp #(ahb_seq_item, ahb_scoreboard) ap_imp;

    // Reference model: a golden shadow of memory, keyed by byte address.
    // Associative array => stores ONLY addresses we actually wrote, and
    // exists() tells us whether an address was ever initialized.
    bit [31:0] ref_mem [bit [31:0]];

    // Counters for the end-of-test summary.
    int unsigned wr_cnt, rd_cnt, pass_cnt, fail_cnt, skip_cnt;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap_imp = new("ap_imp", this);
    endfunction

    function void write(ahb_seq_item t);
      if (t.write) begin
        // Predict: after this write, memory[addr] should equal wdata.
        ref_mem[t.addr] = t.wdata;
        wr_cnt++;
        `uvm_info("SB",
          $sformatf("WRITE addr=0x%08h data=0x%08h", t.addr, t.wdata),
          UVM_MEDIUM)
      end
      else begin
        rd_cnt++;
        // Read of an address we never wrote => no golden value to check.
        if (!ref_mem.exists(t.addr)) begin
          skip_cnt++;
          `uvm_info("SB",
            $sformatf("READ  addr=0x%08h from UNINITIALIZED addr - skip check",
                      t.addr), UVM_LOW)
          return;
        end
        // Compare DUT read data against the golden model.
        if (t.rdata === ref_mem[t.addr]) begin
          pass_cnt++;
          `uvm_info("SB",
            $sformatf("PASS  addr=0x%08h data=0x%08h", t.addr, t.rdata),
            UVM_MEDIUM)
        end
        else begin
          fail_cnt++;
          `uvm_error("SB",
            $sformatf("MISMATCH addr=0x%08h exp=0x%08h got=0x%08h",
                      t.addr, ref_mem[t.addr], t.rdata))
        end
      end
    endfunction

    // Final scoreboard summary and verdict.
    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("SB", $sformatf(
        {"\n---------------- SCOREBOARD SUMMARY ----------------",
         "\n  WRITE=%0d  READ=%0d  PASS=%0d  FAIL=%0d  SKIP=%0d",
         "\n----------------------------------------------------"},
        wr_cnt, rd_cnt, pass_cnt, fail_cnt, skip_cnt), UVM_LOW)
      if (fail_cnt > 0)
        `uvm_error("SB",
          $sformatf("SCOREBOARD FAILED with %0d mismatch(es)", fail_cnt))
      else
        `uvm_info("SB", "SCOREBOARD PASSED", UVM_LOW)
    endfunction
  endclass

  //====================================================================
  // 6b) FUNCTIONAL COVERAGE
  //    Samples a covergroup on every observed transaction.
  //====================================================================
  class ahb_coverage extends uvm_subscriber #(ahb_seq_item);
    `uvm_component_utils(ahb_coverage)

    // The transaction currently being sampled (covergroup reads this).
    ahb_seq_item item;

    covergroup ahb_cg;
      option.per_instance = 1;          // needed for get_inst_coverage()
      option.name         = "ahb_functional_cov";

      // Which direction did we see?
      cp_write: coverpoint item.write {
        bins write_op = {1};
        bins read_op  = {0};
      }
      // Which region of the address map did we touch?
      cp_addr: coverpoint item.addr {
        bins low  = {[32'h00 : 32'h0F]};
        bins mid  = {[32'h10 : 32'h2F]};
        bins high = {[32'h30 : 32'h3C]};
      }
      // Direction TRANSITIONS between consecutive transfers.
      cp_wr_trans: coverpoint item.write {
        bins wr_then_rd = (1 => 0);
        bins rd_then_wr = (0 => 1);
        bins wr_then_wr = (1 => 1);
        bins rd_then_rd = (0 => 0);
      }
      // Every direction x every region combination.
      x_write_addr: cross cp_write, cp_addr;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ahb_cg = new();
    endfunction

    function void write(ahb_seq_item t);
      item = t;
      ahb_cg.sample();                  // take one coverage sample
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("COV",
        $sformatf("Functional coverage = %0.2f %%", ahb_cg.get_inst_coverage()),
        UVM_LOW)
    endfunction
  endclass

  //====================================================================
  // 7) AGENT
  //    ACTIVE builds sequencer+driver+monitor; PASSIVE only monitor.
  //====================================================================
  class ahb_agent extends uvm_agent;
    `uvm_component_utils(ahb_agent)

    ahb_sequencer sqr;
    ahb_driver    drv;
    ahb_monitor   mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon = ahb_monitor::type_id::create("mon", this);
      // Sequencer + driver only when ACTIVE. Overridable via config_db.
      if (get_is_active() == UVM_ACTIVE) begin
        sqr = ahb_sequencer::type_id::create("sqr", this);
        drv = ahb_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      // The sequencer<->driver TLM link exists only if we built them.
      if (get_is_active() == UVM_ACTIVE)
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  //====================================================================
  // 8) ENVIRONMENT
  //    Container that assembles the reusable pieces for this DUT: the
  //    agent (stimulus+observe) and the scoreboard (checking), and wires
  //    the monitor's broadcast into the scoreboard's ear.
  //====================================================================
  class ahb_env extends uvm_env;
    `uvm_component_utils(ahb_env)

    ahb_agent      agent;
    ahb_scoreboard sb;
    ahb_coverage   cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = ahb_agent::type_id::create("agent", this);
      sb    = ahb_scoreboard::type_id::create("sb", this);
      cov   = ahb_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      // One monitor port -> two subscribers. Broadcast in practice: the
      // scoreboard (checks data) and the coverage (records what happened)
      // both receive every transaction the monitor publishes.
      agent.mon.ap.connect(sb.ap_imp);
      agent.mon.ap.connect(cov.analysis_export);
    endfunction
  endclass

  //====================================================================
  // 9) TESTS
  //    ahb_base_test: owns the env + prints the assembled topology.
  //    ahb_smoke_test: the actual scenario (one write, one read).
  //====================================================================
  class ahb_base_test extends uvm_test;
    `uvm_component_utils(ahb_base_test)

    ahb_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = ahb_env::type_id::create("env", this);
    endfunction

    // Topology is fully built and connected by this phase.
    function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      uvm_top.print_topology();
    endfunction

    // Read the global error/fatal counts from the report server and print
    // one machine-readable verdict line.
    function void final_phase(uvm_phase phase);
      uvm_report_server rs;
      int unsigned n_err, n_ftl;
      string       line;
      super.final_phase(phase);
      rs    = uvm_report_server::get_server();
      n_err = rs.get_severity_count(UVM_ERROR);
      n_ftl = rs.get_severity_count(UVM_FATAL);
      line  = $sformatf("AHB_RESULT test=%s UVM_ERROR=%0d UVM_FATAL=%0d %s",
                        get_type_name(), n_err, n_ftl,
                        ((n_err == 0 && n_ftl == 0) ? "PASS" : "FAIL"));
      $display(line);
    endfunction
  endclass

  class ahb_smoke_test extends ahb_base_test;
    `uvm_component_utils(ahb_smoke_test)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      ahb_single_write_seq wr_seq;
      ahb_single_read_seq  rd_seq;

      phase.raise_objection(this, "smoke test running");

      wr_seq = ahb_single_write_seq::type_id::create("wr_seq");
      rd_seq = ahb_single_read_seq::type_id::create("rd_seq");

      // The sequencer now lives inside env.agent -> address it there.
      wr_seq.start(env.agent.sqr);
      rd_seq.start(env.agent.sqr);

      #100ns;
      phase.drop_objection(this, "smoke test done");
    endtask
  endclass

  //--------------------------------------------------------------------
  // write-then-read at 3 different addresses.
  //--------------------------------------------------------------------
  class ahb_write_read_test extends ahb_base_test;
    `uvm_component_utils(ahb_write_read_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      ahb_write_read_seq seq;
      bit [31:0] addrs[3];
      addrs = '{32'h00, 32'h20, 32'h3C};
      phase.raise_objection(this);
      foreach (addrs[i]) begin
        seq = ahb_write_read_seq::type_id::create($sformatf("wr_seq%0d", i));
        seq.target_addr = addrs[i];      // set the parametric address
        seq.start(env.agent.sqr);
      end
      #200ns;
      phase.drop_objection(this);
    endtask
  endclass

  //--------------------------------------------------------------------
  // seed-dependent random traffic.
  //--------------------------------------------------------------------
  class ahb_random_test extends ahb_base_test;
    `uvm_component_utils(ahb_random_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      ahb_random_seq seq;
      phase.raise_objection(this);
      seq = ahb_random_seq::type_id::create("rnd_seq");
      // Randomize the SEQUENCE object to pick num_txn (in [10:50]).
      if (!seq.randomize())
        `uvm_fatal("TEST", "random_seq randomize failed")
      seq.start(env.agent.sqr);
      #200ns;
      phase.drop_objection(this);
    endtask
  endclass

  //--------------------------------------------------------------------
  // back-to-back stream (stresses the monitor's pending logic).
  //--------------------------------------------------------------------
  class ahb_b2b_test extends ahb_base_test;
    `uvm_component_utils(ahb_b2b_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      ahb_b2b_seq seq;
      phase.raise_objection(this);
      seq = ahb_b2b_seq::type_id::create("b2b_seq");
      seq.start(env.agent.sqr);
      #200ns;
      phase.drop_objection(this);
    endtask
  endclass

  //--------------------------------------------------------------------
  // walking address (full memory sweep, catches address-decode bugs).
  //--------------------------------------------------------------------
  class ahb_walking_test extends ahb_base_test;
    `uvm_component_utils(ahb_walking_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      ahb_walking_addr_seq seq;
      phase.raise_objection(this);
      seq = ahb_walking_addr_seq::type_id::create("walk_seq");
      seq.start(env.agent.sqr);
      #200ns;
      phase.drop_objection(this);
    endtask
  endclass

  //--------------------------------------------------------------------
  // regression: run walking -> b2b -> random in sequence (nested seq).
  //--------------------------------------------------------------------
  class ahb_regression_test extends ahb_base_test;
    `uvm_component_utils(ahb_regression_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      ahb_regression_seq seq;
      phase.raise_objection(this);
      seq = ahb_regression_seq::type_id::create("reg_seq");
      seq.start(env.agent.sqr);
      #200ns;
      phase.drop_objection(this);
    endtask
  endclass

  //====================================================================
  // NEGATIVE SEQUENCE + TEST: deliberately drive an ILLEGAL transfer so
  // the a_addr_align assertion FIRES. This proves the assertion actually
  // works (silence would otherwise be ambiguous). Run it SEPARATELY -- it
  // is expected to FAIL and is NOT part of the normal regression list.
  //====================================================================
  class ahb_align_error_seq extends uvm_sequence #(ahb_seq_item);
    `uvm_object_utils(ahb_align_error_seq)
    function new(string name = "ahb_align_error_seq");
      super.new(name);
    endfunction
    virtual task body();
      ahb_seq_item req;
      req = ahb_seq_item::type_id::create("bad");
      start_item(req);
      // Fill fields BY HAND: randomize() would refuse this (c_align blocks
      // a word transfer to a non-aligned address). That is exactly why we
      // set them directly -- to force the illegal stimulus onto the bus.
      req.write = 1'b1;
      req.addr  = 32'h0000_0011;   // word transfer, but NOT 4-byte aligned
      req.size  = 3'b010;          // HSIZE = word
      req.wdata = 32'hBAD0_BAD0;
      finish_item(req);
    endtask
  endclass

  class ahb_align_error_test extends ahb_base_test;
    `uvm_component_utils(ahb_align_error_test)
    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
    task run_phase(uvm_phase phase);
      ahb_align_error_seq seq;
      phase.raise_objection(this);
      seq = ahb_align_error_seq::type_id::create("align_err_seq");
      seq.start(env.agent.sqr);
      #200ns;
      phase.drop_objection(this);
    endtask
  endclass

endpackage

// ==================== PART 3/3: TOP MODULE ====================
//======================================================================
// Brief  : Top-level testbench: clock/reset, DUT wiring, UVM launch.
//======================================================================
`timescale 1ns/1ps

module tb_top;

  // UVM + our package must be visible here for config_db / run_test.
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import ahb_pkg::*;

  // -------------------------------------------------------------------
  // Clock & reset generation
  // -------------------------------------------------------------------
  logic HCLK;
  logic HRESETn;

  initial HCLK = 1'b0;
  always  #5 HCLK = ~HCLK;               // 10 ns period

  initial begin
    HRESETn = 1'b0;
    #25 HRESETn = 1'b1;                   // release reset at t = 25 ns
  end

  // -------------------------------------------------------------------
  // Interface + DUT
  // -------------------------------------------------------------------
  ahb_if intf (.HCLK(HCLK), .HRESETn(HRESETn));

  logic hreadyout_w;

  ahb_lite_slave #(.DEPTH(16)) dut (
    .HCLK      (HCLK),
    .HRESETn   (HRESETn),
    .HSEL      (intf.HSEL),
    .HWRITE    (intf.HWRITE),
    .HREADY    (intf.HREADY),
    .HTRANS    (intf.HTRANS),
    .HSIZE     (intf.HSIZE),
    .HBURST    (intf.HBURST),
    .HADDR     (intf.HADDR),
    .HWDATA    (intf.HWDATA),
    .HRDATA    (intf.HRDATA),
    .HREADYOUT (hreadyout_w),
    .HRESP     (intf.HRESP)
  );

  assign intf.HREADY = hreadyout_w;      // HREADYOUT -> HREADY loopback

  // -------------------------------------------------------------------
  // Housekeeping
  // -------------------------------------------------------------------
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_top);
    // Print simulation time in ns: -9 => 10^-9, 0 decimals, " ns" suffix,
    // min field width 10.
    $timeformat(-9, 0, " ns", 10);
  end

  // -------------------------------------------------------------------
  // Hand the physical interface to the UVM (class) world, then start.
  //   set(null, "*", "vif", intf) => visible to EVERY component as "vif".
  //   run_test() with no arg => the test name comes from +UVM_TESTNAME.
  // -------------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual ahb_if)::set(null, "*", "vif", intf);
    run_test();
  end

endmodule
