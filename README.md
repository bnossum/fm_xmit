### fm_xmit
 
FM transmit "HELLO WORLD" on an iceblink40-hx1k board, without using a
PLL. Total size 60 SB_LUTs. See source code for documentation.  

A picture of the design can be seen here [here](/code/floorplan.png).

#### Requirements

Designed for compilation with iCECube2, with Lattice LSE as Verilog
compiler. Placement,  and use of cascaded LUTSs,  is vital in this design.
