// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class i2c_common_vseq extends i2c_base_vseq;
  `uvm_object_utils(i2c_common_vseq)
  `uvm_object_new

  constraint num_trans_c { num_trans inside {[1:2]}; }

  virtual task pre_start();
    super.pre_start();
    // for this vseq, $value$plusargs "+en_scb=0" is defined in i2c_sim_cfg.hjson
    // disable i2c_monitor and i2c_scoreboard since they can not handle this test
    if (!cfg.en_scb) begin
      cfg.m_i2c_agent_cfg.en_monitor = 1'b0;
      `uvm_info(`gfn, $sformatf("\n  disable i2c_monitor and i2c_scoreboard"), UVM_DEBUG)
    end
  endtask : pre_start

  virtual task body();
    `uvm_info(`gfn, "\n--> start of i2c_common_vseq", UVM_DEBUG)
    run_common_vseq_wrapper(num_trans);
    `uvm_info(`gfn, "\n--> end of i2c_common_vseq", UVM_DEBUG)
  endtask : body

endclass : i2c_common_vseq
