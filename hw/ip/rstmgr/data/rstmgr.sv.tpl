// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// This module is the overall reset manager wrapper
// TODO: This module is only a draft implementation that covers most of the rstmgr
// functoinality but is incomplete

`include "prim_assert.sv"

// This top level controller is fairly hardcoded right now, but will be switched to a template
module rstmgr import rstmgr_pkg::*; (
  // Primary module clocks
  input clk_i,
  input rst_ni, // this is currently connected to top level reset, but will change once ast is in
% for clk in clks:
  input clk_${clk}_i,
% endfor

  // Bus Interface
  input tlul_pkg::tl_h2d_t tl_i,
  output tlul_pkg::tl_d2h_t tl_o,

  // pwrmgr interface
  input pwrmgr_pkg::pwr_rst_req_t pwr_i,
  output pwrmgr_pkg::pwr_rst_rsp_t pwr_o,

  // ast interface
  input rstmgr_ast_t ast_i,

  // cpu related inputs
  input rstmgr_cpu_t cpu_i,

  // Interface to alert handler
  input alert_pkg::alert_crashdump_t alert_dump_i,

  // dft bypass
  input scan_rst_ni,
  input scanmode_i,

  // reset outputs
% for intf in export_rsts:
  output rstmgr_${intf}_out_t resets_${intf}_o,
% endfor
  output rstmgr_out_t resets_o

);

  import rstmgr_reg_pkg::*;

  // receive POR and stretch
  // The por is at first stretched and synced on clk_aon
  // The rst_ni and pok_i input will be changed once AST is integrated
  logic rst_por_aon_n;
  rstmgr_por u_rst_por_aon (
    .clk_i(clk_aon_i),
    .rst_ni(ast_i.aon_pok),
    .scan_rst_ni,
    .scanmode_i,
    .rst_no(rst_por_aon_n)
  );

  prim_clock_mux2 u_rst_por_aon_n_mux (
    .clk0_i(rst_por_aon_n),
    .clk1_i(scan_rst_ni),
    .sel_i(scanmode_i),
    .clk_o(resets_o.rst_por_aon_n)
  );

  ////////////////////////////////////////////////////
  // Register Interface                             //
  ////////////////////////////////////////////////////

  // local_rst_n is the reset used by the rstmgr for its internal logic
  logic local_rst_n;
  assign local_rst_n = resets_o.rst_por_io_div2_n;

  rstmgr_reg_pkg::rstmgr_reg2hw_t reg2hw;
  rstmgr_reg_pkg::rstmgr_hw2reg_t hw2reg;

  rstmgr_reg_top u_reg (
    .clk_i,
    .rst_ni(local_rst_n),
    .tl_i,
    .tl_o,
    .reg2hw,
    .hw2reg,
    .devmode_i(1'b1)
  );

  ////////////////////////////////////////////////////
  // Input handling                                 //
  ////////////////////////////////////////////////////

  logic ndmreset_req_q;
  logic ndm_req_valid;

  prim_flop_2sync #(
    .Width(1),
    .ResetValue('0)
  ) u_sync (
    .clk_i,
    .rst_ni(local_rst_n),
    .d_i(cpu_i.ndmreset_req),
    .q_o(ndmreset_req_q)
  );

  assign ndm_req_valid = ndmreset_req_q & (pwr_i.reset_cause == pwrmgr_pkg::ResetNone);

  ////////////////////////////////////////////////////
  // Source resets in the system                    //
  // These are hardcoded and not directly used.     //
  // Instead they act as async reset roots.         //
  ////////////////////////////////////////////////////

  // The two source reset modules are chained together.  The output of one is fed into the
  // the second.  This ensures that if upstream resets for any reason, the associated downstream
  // reset will also reset.

  logic [PowerDomains-1:0] rst_lc_src_n;
  logic [PowerDomains-1:0] rst_sys_src_n;


  // lc reset sources
  rstmgr_ctrl #(
    .PowerDomains(PowerDomains)
  ) u_lc_src (
    .clk_i,
    .rst_ni(local_rst_n),
    .rst_req_i(pwr_i.rst_lc_req),
    .rst_parent_ni({PowerDomains{1'b1}}),
    .rst_no(rst_lc_src_n)
  );

  // sys reset sources
  rstmgr_ctrl #(
    .PowerDomains(PowerDomains)
  ) u_sys_src (
    .clk_i,
    .rst_ni(local_rst_n),
    .rst_req_i(pwr_i.rst_sys_req | {PowerDomains{ndm_req_valid}}),
    .rst_parent_ni(rst_lc_src_n),
    .rst_no(rst_sys_src_n)
  );

  assign pwr_o.rst_lc_src_n = rst_lc_src_n;
  assign pwr_o.rst_sys_src_n = rst_sys_src_n;


  ////////////////////////////////////////////////////
  // Software reset controls external reg           //
  ////////////////////////////////////////////////////
  logic [NumSwResets-1:0] sw_rst_ctrl_n;

  for (genvar i=0; i < NumSwResets; i++) begin : gen_sw_rst_ext_regs
    prim_subreg #(
      .DW(1),
      .SWACCESS("RW"),
      .RESVAL(1)
    ) u_rst_sw_ctrl_reg (
      .clk_i,
      .rst_ni(local_rst_n),
      .we(reg2hw.sw_rst_ctrl_n[i].qe & reg2hw.sw_rst_regen[i]),
      .wd(reg2hw.sw_rst_ctrl_n[i].q),
      .de('0),
      .d('0),
      .qe(),
      .q(sw_rst_ctrl_n[i]),
      .qs(hw2reg.sw_rst_ctrl_n[i].d)
    );
  end

  ////////////////////////////////////////////////////
  // leaf reset in the system                       //
  // These should all be generated                  //
  ////////////////////////////////////////////////////

% for rst in leaf_rsts:
  logic rst_${rst['name']}_n;

  prim_flop_2sync #(
    .Width(1),
    .ResetValue('0)
  ) u_${rst['name']} (
    .clk_i(clk_${rst['clk']}_i),
  % if "domain" in rst:
    .rst_ni(rst_${rst['parent']}_n[${rst['domain']}]),
  % else:
    .rst_ni(rst_${rst['parent']}_n),
  % endif
  % if "sw" in rst:
    .d_i(sw_rst_ctrl_n[${rst['name'].upper()}]),
  % else:
    .d_i(1'b1),
  % endif
    .q_o(rst_${rst['name']}_n)
  );

  prim_clock_mux2 u_${rst['name']}_mux (
    .clk0_i(rst_${rst['name']}_n),
    .clk1_i(scan_rst_ni),
    .sel_i(scanmode_i),
    .clk_o(resets_o.rst_${rst['name']}_n)
  );

% endfor

  ////////////////////////////////////////////////////
  // Reset info construction                        //
  ////////////////////////////////////////////////////

  logic rst_hw_req;
  logic rst_low_power;
  logic rst_ndm;
  logic rst_cpu_nq;
  logic first_reset;

  // The qualification of first reset below could technically be POR as well.
  // However, that would enforce software to clear POR upon cold power up.  While that is
  // the most likely outcome anyways, hardware should not require that.
  assign rst_hw_req    = ~first_reset & pwr_i.reset_cause == pwrmgr_pkg::HwReq;
  assign rst_ndm       = ~first_reset & ndm_req_valid;
  assign rst_low_power = ~first_reset & pwr_i.reset_cause == pwrmgr_pkg::LowPwrEntry;

  prim_flop_2sync #(
    .Width(1),
    .ResetValue('0)
  ) u_cpu_reset_synced (
    .clk_i,
    .rst_ni(local_rst_n),
    .d_i(cpu_i.rst_cpu_n),
    .q_o(rst_cpu_nq)
  );

  // first reset is a flag that blocks reset recording until first de-assertion
  always_ff @(posedge clk_i or negedge local_rst_n) begin
    if (!local_rst_n) begin
      first_reset <= 1'b1;
    end else if (rst_cpu_nq) begin
      first_reset <= 1'b0;
    end
  end

  // Only sw is allowed to clear a reset reason, hw is only allowed to set it.
  assign hw2reg.reset_info.low_power_exit.d  = 1'b1;
  assign hw2reg.reset_info.low_power_exit.de = rst_low_power;

  assign hw2reg.reset_info.ndm_reset.d  = 1'b1;
  assign hw2reg.reset_info.ndm_reset.de = rst_ndm;

  // HW reset requests most likely will be multi-bit, so OR in whatever reasons
  // that are already set.
  assign hw2reg.reset_info.hw_req.d  = pwr_i.rstreqs | reg2hw.reset_info.hw_req.q;
  assign hw2reg.reset_info.hw_req.de = rst_hw_req;


  ////////////////////////////////////////////////////
  // Exported resets                                //
  ////////////////////////////////////////////////////
% for intf, eps in export_rsts.items():
  % for ep, rsts in eps.items():
    % for rst in rsts:
  assign resets_${intf}_o.rst_${intf}_${ep}_${rst}_n = resets_o.rst_${rst}_n;
    % endfor
  % endfor
% endfor

  ////////////////////////////////////////////////////
  // Crash info capture                             //
  ////////////////////////////////////////////////////
  localparam int CrashRemainder = $bits(alert_pkg::alert_crashdump_t) % RdWidth > 0 ? 1 : 0;
  localparam int CrashStoreSlot = $bits(alert_pkg::alert_crashdump_t) / RdWidth +
      CrashRemainder;
  localparam int TotalWidth     = CrashStoreSlot * RdWidth;
  localparam int SlotCntWidth   = $clog2(CrashStoreSlot);

  logic dump_capture;
  logic [2**SlotCntWidth-1:0][RdWidth-1:0] slots;
  logic [CrashStoreSlot-1:0][RdWidth-1:0] slots_q;

  // capture on any legal reset request
  assign dump_capture = reg2hw.alert_info_ctrl.en.q &
                        (rst_hw_req | rst_ndm | rst_low_power);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      slots_q <= '0;
    end else if (dump_capture) begin
      slots_q <= TotalWidth'(alert_dump_i);
    end
  end

  always_comb begin
    slots = '0;
    slots[CrashStoreSlot-1:0] = slots_q;
  end

  // once dump is captured, no more information is captured until
  // re-eanbled by software.
  assign hw2reg.alert_info_ctrl.en.d  = 1'b0;
  assign hw2reg.alert_info_ctrl.en.de = dump_capture;

  // number of segments to read
  assign hw2reg.alert_info_attr.d = CrashStoreSlot;

  // the actual dump data
  assign hw2reg.alert_info.d = slots[reg2hw.alert_info_ctrl.index.q[SlotCntWidth-1:0]];

  if (SlotCntWidth < IdxWidth) begin : gen_tieoffs
    logic [IdxWidth-SlotCntWidth-1:0] unused_idx;
    assign unused_idx = reg2hw.alert_info_ctrl.index.q[IdxWidth-1:SlotCntWidth];
  end


  ////////////////////////////////////////////////////
  // Assertions                                     //
  ////////////////////////////////////////////////////

  // Make sure the crash dump isn't excessively large
  `ASSERT_INIT(CntWidth_A, SlotCntWidth <= IdxWidth)

  // when upstream resets, downstream must also reset

  // output known asserts
  `ASSERT_KNOWN(TlDValidKnownO_A,    tl_o.d_valid  )
  `ASSERT_KNOWN(TlAReadyKnownO_A,    tl_o.a_ready  )
  `ASSERT_KNOWN(PwrKnownO_A,         pwr_o         )
  `ASSERT_KNOWN(ResetsKnownO_A,      resets_o      )
% for intf in export_rsts:
  `ASSERT_KNOWN(${intf.capitalize()}ResetsKnownO_A, resets_${intf}_o )
% endfor

endmodule // rstmgr
