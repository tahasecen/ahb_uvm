//======================================================================
// File   : design.sv  (EDA Playground "Design" pane)
// Brief  : Simple AMBA AHB-Lite SLAVE with an internal word memory.
//          Zero wait-state, always-OKAY response. DUT for the AHB-Lite
//          UVM VIP. IEEE 1800-2012.
//======================================================================
`timescale 1ns/1ps

module ahb_lite_slave #(
    parameter int DEPTH = 16                 // number of 32-bit words
) (
    // ---- Global signals ----
    input  logic        HCLK,
    input  logic        HRESETn,             // active-low, async assert

    // ---- AHB-Lite slave inputs (from master / interconnect) ----
    input  logic        HSEL,                // this slave is selected
    input  logic        HWRITE,              // 1 = write, 0 = read
    input  logic        HREADY,              // global HREADY: prev xfer done
    input  logic [1:0]  HTRANS,              // transfer type (see below)
    input  logic [2:0]  HSIZE,               // transfer size (unused: word only)
    input  logic [2:0]  HBURST,              // burst type   (unused: SINGLE only)
    input  logic [31:0] HADDR,               // address (address phase)
    input  logic [31:0] HWDATA,              // write data (data phase)

    // ---- AHB-Lite slave outputs (to master / interconnect) ----
    output logic [31:0] HRDATA,              // read data (data phase)
    output logic        HREADYOUT,           // this slave's ready
    output logic        HRESP                // 0 = OKAY, 1 = ERROR
);

  // -------------------------------------------------------------------
  // HTRANS encoding (AHB): IDLE=2'b00, BUSY=2'b01, NONSEQ=2'b10, SEQ=2'b11
  // HTRANS[1] == 1  =>  a real data-moving transfer (NONSEQ or SEQ).
  // We use HTRANS[1] as the "is there an actual transfer?" flag.
  // -------------------------------------------------------------------

  // Word-addressable backing memory. Deliberately NOT reset (real RAM
  // keeps its contents through a reset; only the control regs clear).
  logic [31:0] mem [0:DEPTH-1];

  // -------------------------------------------------------------------
  // AHB address/data pipeline
  //
  // AHB overlaps two phases of consecutive transfers:
  //   cycle N   : ADDRESS phase -> HADDR/HWRITE/HTRANS are valid
  //   cycle N+1 : DATA phase    -> HWDATA (write) or HRDATA (read) valid
  //
  // So the data for an address arrives ONE CYCLE LATER than the address.
  // The slave must therefore LATCH the address and the write flag during
  // the address phase and USE them in the next (data) phase. If we tried
  // to write using the live HADDR, we would write to the address of the
  // *following* transfer -> silent data corruption.
  //
  // addr_d / wr_en_d are exactly that one-cycle pipeline register.
  // -------------------------------------------------------------------
  logic [31:0] addr_d;                       // address latched for data phase
  logic        wr_en_d;                      // "this is a write" latched flag

  // -------------------------------------------------------------------
  // ADDRESS PHASE capture.
  // Latch address + direction only when the bus grants a valid transfer:
  //   HREADY    : pipeline may advance (previous transfer has completed)
  //   HSEL      : this slave is the target
  //   HTRANS[1] : transfer type is NONSEQ/SEQ (not IDLE/BUSY)
  // -------------------------------------------------------------------
  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      addr_d  <= '0;
      wr_en_d <= 1'b0;
    end
    else if (HREADY) begin
      if (HSEL && HTRANS[1]) begin
        // Valid transfer -> remember address + direction for the next cycle.
        addr_d  <= HADDR;
        wr_en_d <= HWRITE;
      end
      else begin
        // Bus idle / not selected -> guarantee NO write happens next cycle.
        // (addr_d is intentionally held so a stable read address survives.)
        wr_en_d <= 1'b0;
      end
    end
    // if HREADY==0 (wait state) we hold everything. Wait states are not
    // modeled by this DUT.
  end

  // -------------------------------------------------------------------
  // DATA PHASE write commit -- ONE CYCLE AFTER the address phase.
  // wr_en_d/addr_d were latched last cycle, so they point at the correct
  // (pipelined) target while HWDATA is the master's data for this phase.
  //
  // Word index = addr_d[5:2]:
  //   bits [1:0] are the byte offset within a 32-bit word (word aligned),
  //   the next log2(DEPTH) bits select the word. DEPTH=16 -> 4 bits -> [5:2].
  //   (If DEPTH changes, widen/narrow this slice accordingly.)
  // NOTE: when wait states are added later, also gate this on HREADY.
  // -------------------------------------------------------------------
  always_ff @(posedge HCLK) begin
    if (wr_en_d)
      mem[addr_d[5:2]] <= HWDATA;
  end

  // -------------------------------------------------------------------
  // READ data is combinational off the latched address, so it is valid
  // during the DATA phase -- the same pipeline timing as the write.
  // -------------------------------------------------------------------
  assign HRDATA = mem[addr_d[5:2]];

  // -------------------------------------------------------------------
  // Scope limitations:
  //   HREADYOUT = 1 -> never insert a wait state.
  //   HRESP     = 0 -> always OKAY, never ERROR.
  // -------------------------------------------------------------------
  assign HREADYOUT = 1'b1;
  assign HRESP     = 1'b0;

endmodule
