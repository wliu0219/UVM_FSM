package dv_env;
import uvm_pkg::*;
`include "uvm_macros.svh"
`include "macro.svh"
//Sequence Item
class Item extends uvm_sequence_item;
`uvm_object_utils(Item)
rand bit in;
bit      out;

virtual function string convert2str();
  return $sformatf("in = %0d, out = %0d",in,out);
endfunction

function new(string name = "Item");
  super.new(name);
endfunction

constraint c1 {in dist {0:/20,1:/80};}  // in "0" -> 20%  "1" -> 80%

endclass


//Sequence
class gen_item_seq extends uvm_sequence;
`uvm_object_utils(gen_item_seq)

function new(string name = "gen_item_seq");
  super.new(name);
endfunction

rand int num;

constraint c1 {soft num inside {[10:50]};}

virtual task body();
  for (int i = 0; i < num; i++)begin
    Item m_item = Item::type_id::create("m_item");
    start_item(m_item);
    m_item.randomize();
    `uvm_info("SEQ",$sformatf("Generate new item: %s", m_item.convert2str()),UVM_HIGH)
    finish_item(m_item);
  end
  `uvm_info("SEQ",$sformatf("Done generation of %0d items",num),UVM_LOW)
endtask

endclass


//Driver
class driver extends uvm_driver #(Item);
`uvm_component_utils(driver)

function new(string name = "driver",uvm_component parent = null);
  super.new(name,parent);
endfunction

virtual des_if vif;

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  if(!uvm_config_db#(virtual des_if)::get(this,"","des_vif",vif))
    `uvm_fatal("DRV","Cound not get vif")
endfunction

virtual task run_phase(uvm_phase phase);
  super.run_phase(phase);
  forever begin
    Item m_item;
    `uvm_info("DRV",$sformatf("Wait for item from sequencer"),UVM_HIGH)
    seq_item_port.get_next_item(m_item);
    drive_item(m_item);
    seq_item_port.item_done();
  end
endtask

virtual task drive_item(Item m_item);
 @(vif.cb);
    vif.cb.in <= m_item.in;
endtask
endclass

//Monitor 
class monitor extends uvm_monitor;
  `uvm_component_utils(monitor)
  function new(string name = "monitor",uvm_component parent = null);
    super.new(name,parent);
  endfunction

  uvm_analysis_port  #(Item) mon_analysis_port;
  virtual des_if vif;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual des_if)::get(this,"","des_vif",vif))
      `uvm_fatal("MON","Could not get vif")
    mon_analysis_port = new("mon_analysis_port",this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);
    forever begin
      @(vif.cb);
        if(vif.rstn)begin
            Item item = Item::type_id::create("item");
            item.in = vif.in;
            item.out= vif.cb.out;
            mon_analysis_port.write(item);
            `uvm_info("MON",$sformatf("Saw item %s", item.convert2str()),UVM_HIGH)
        end
    end
  endtask
endclass


//Scoreboard
class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
  function new(string name = "scoreboard",uvm_component parent = null);
    super.new(name,parent);
  endfunction

  bit[`LENGTH-1:0] ref_pattern;
  bit[`LENGTH-1:0] act_pattern;
  bit              exp_out;

  uvm_analysis_imp #(Item,scoreboard) m_analysis_imp;

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_analysis_imp = new("m_analysis_imp",this);
    if(!uvm_config_db#(bit[`LENGTH-1:0])::get(this,"*","ref_pattern",ref_pattern))
        `uvm_fatal("SCBD","Did not get ref_pattern!")
  endfunction

  virtual function write(Item item);
    act_pattern = act_pattern << 1 | item.in;
    `uvm_info("SCBD",$sformatf("in = %0d out = %0d ref = 0b%0b act = 0b%0b",item.in,item.out,ref_pattern,act_pattern),UVM_LOW)
    if(item.out != exp_out)begin
      `uvm_error("SCBD",$sformatf("ERROR ! out = %0d exp = %0d",item.out,exp_out))
    end else begin
      `uvm_info("SCBD",$sformatf("PASS ! out = %0d exp = %0d",item.out,exp_out),UVM_HIGH)
    end

    if(!(ref_pattern ^ act_pattern))begin
      `uvm_info("SCBD",$sformatf("Pattern found to match, next out should be 1"),UVM_LOW)
      exp_out = 1;
    end else begin
      exp_out = 0;
    end
  endfunction

endclass


//agent
class agent extends uvm_agent;
`uvm_component_utils(agent)
function new(string name = "agent", uvm_component parent = null);
  super.new(name,parent);
endfunction

driver                d0;
monitor               m0;
uvm_sequencer #(Item) s0;

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  s0 = uvm_sequencer#(Item)::type_id::create("s0",this);
  d0 = driver::type_id::create("d0",this);
  m0 = monitor::type_id::create("m0",this);  
endfunction

virtual function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  d0.seq_item_port.connect(s0.seq_item_export);
endfunction

endclass


//environment
class env extends uvm_env;
`uvm_component_utils(env)
function new(string name = "env", uvm_component parent = null);
  super.new(name,parent);
endfunction

agent       a0;
scoreboard  sb0;

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  a0  = agent::type_id::create("a0",this);
  sb0 = scoreboard::type_id::create("sb0",this);  
endfunction

virtual function void connect_phase(uvm_phase phase);
  super.connect_phase(phase);
  a0.m0.mon_analysis_port.connect(sb0.m_analysis_imp);
endfunction

endclass  


//Base Test
class base_test extends uvm_test;
`uvm_component_utils(base_test)
function new(string name = "base_test",uvm_component parent = null);
  super.new(name,parent);
endfunction

env  e0;
bit [`LENGTH-1:0] pattern = 4'b1011;
gen_item_seq  seq;
virtual  des_if  vif;

virtual function void build_phase(uvm_phase phase);
  super.build_phase(phase);
  e0 = env::type_id::create("e0",this);
  if(!uvm_config_db#(virtual des_if)::get(this,"","des_vif",vif))
    `uvm_fatal("TEST","Did not get vif")
  uvm_config_db#(virtual des_if)::set(this,"e0.a0.*","des_vif",vif);
  uvm_config_db#(bit[`LENGTH-1:0])::set(this,"*","ref_pattern",pattern);

  seq = gen_item_seq::type_id::create("seq",this);
  seq.randomize();
endfunction

virtual task run_phase(uvm_phase phase);
  phase.raise_objection(this);
  apply_reset();
  seq.start(e0.a0.s0);
  #200;
  phase.drop_objection(this);
endtask

virtual task apply_reset();
  vif.rstn <= 0;
  vif.in   <= 0;
  repeat(5)@(posedge vif.clk);
  vif.rstn <= 1;
  repeat(10)@(posedge vif.clk);
endtask

endclass


endpackage
