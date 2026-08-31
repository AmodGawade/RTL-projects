// axi_lite_pkg.sv
`timescale 1ns/1ps
// Shared response-code constants for the AXI4-Lite side of this project. APB has its own single
// PSLVERR bit (see apb_regbank.sv), not a 2-bit response code, so it isn't included here.
package axi_lite_pkg;
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;
  localparam logic [1:0] RESP_DECERR = 2'b11;
endpackage
