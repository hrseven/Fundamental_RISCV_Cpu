`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/06 20:49:16
// Design Name: 
// Module Name: SegCtrl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module SegCtrl(
    input rf_we_ex,
    input [1:0] rf_wd_sel,
    input [4:0] rf_wa_ex,
    input [4:0] rf_ra0_id,
    input [4:0] rf_ra1_id,
    input [1:0] npc_sel_ex,
    output reg stall_pc,
    output reg stall_if_id,
    output reg flush_if_id,
    output reg flush_id_ex
    );
    always@(*)begin
        if(rf_we_ex&&rf_wd_sel==2'b10&&rf_wa_ex&&(rf_ra0_id==rf_wa_ex||rf_ra1_id==rf_wa_ex))begin
            flush_id_ex=1;
            stall_pc=1;
            stall_if_id=1;
            flush_if_id=0;
        end
        else if(npc_sel_ex==1||npc_sel_ex==2)begin
            flush_if_id=1;
            flush_id_ex=1;
            stall_pc=0;
            stall_if_id=0;
        end
        else begin
            stall_pc=0;
            stall_if_id=0;
            flush_if_id=0;
            flush_id_ex=0;
        end
    end
endmodule
