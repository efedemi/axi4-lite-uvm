// The sequencer arbitrates between sequences and hands items to the driver one at a time.
// The base class already does everything we need.
typedef uvm_sequencer #(axil_seq_item) axil_sequencer;
