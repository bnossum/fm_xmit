/* Morse "HELLO WORLD" on FM. For iCEblink40hx1k development board.
 * 
 * See http://hamsterworks.co.nz/mediawiki/index.php/FM_SOS for original 
 * project. Inspiration: https://github.com/r4d10n/iCEstick-hacks.
 * 
 * Copyright B. Nossum. See LICENCE for licence.
 * 
 * How does it work?
 * When we emit "no sound" FM, we would like to emit a sinus wawe at CENTER
 * frequency. Instead we emit a "square wave" with plenty of jitter at CENTER
 * frequency. For a radio, this is a FM channel with a lot of noise.
 * When we emit a beep we use a slightly lower frequency for a short
 * period, then a slightly higher frequency for a short period, and repeats
 * this for some time. The repetition rate is the pitch of the tune. The
 * difference from the CENTER frequency give the volume.
 * 
 * What is the use of this project?
 * Next to none. However, it demonstrates that we can implement a freerunning
 * clock at 409 MHz, and it shows that we can get FM out of iceblink40hx1k using 
 * few resources. It may possibly be used as a debugging aid for designs where 
 * no wired interface is available. 
 * 
 * User guide:
 * -----------
 * 1. Synthesize with Lattice ICECube2 LSE,  - ensure "auto LUT cascade" is 
 *    off. See placement file top.pcf.
 * 2. Check the frequency of your freerunning clock on your iceblink40hx1k 
 *    board. Set parameter TIMING to 1. After programming the card, observe 
 *    led2. It will stay on for around 14s. 13.9 s, so apperantly 
 *    CLKFRQ ~= 2^32/13.9 = 309 MHz. If your observation is widely off this 
 *    value, examine placement of the instance of m_freeclock. Also, 
 *    perhaps your tool has inserted a global buffer?
 * 3. Select the FM center frequency (CENTER).
 * 4. Compile with ICECube2, upload to board, select board main clock at
 *    0.33 MHz.
 * 4. Tune in your radio at approximately CENTER, and you should hear the 
 *    message in morse.
 */
module top #
  ( parameter
    TIMING = 0,          // Set to 1 for calibration
    CLKFRQ  = 409000000, // Hz
    CENTER  =  91000000  // Hz
//  CENTER  =  87000000  // Hz min on my Tivoli Audio
//  CENTER  = 108500000  // Hz max on my Tivoli Audio
    )
   (
    input        dummy, //     Is 1. To avoid optimizations. (Is really CAP_BTN1).
    input        CLK_I, //     For slow work. Nominally 0.33 MHz
    output       antennae, //  The output
    output [3:0] led    //     Diagnostics. See at end of module.
    );
   wire          clk; //       Fast clock. Do not load.
   wire          msb; //       Msb of phase acc. used as a 1-bit DAC.
   wire          buffermsb; // Buffered msb of phase accumulator close to pin.
   reg [14:0]    cnt;     //   Determines when to shift, and modulate.
   reg           doshift; //   Time to shift the message
   reg [12:0]    addend; //    Input for the phase accumulator
   wire [7:0]    d; //         Data to transmit from low to high bit
   reg [6:0]     adr; //       Address into ROM that holds data
   reg           msg; //       0 : Silent, 1 : Sound
   
   /* 
    * 0.33 MHZ clock domain 
    */
   always @(posedge CLK_I)
      {doshift,cnt} <= cnt + 1;
   
   m_messagerom i_messagerom(.d(d[7:0]),.adr(adr[6:3])); 

   wire          cmbmsg;
   m_mux8to1 i_mux8(.o(cmbmsg),.d(d), .a(adr[2:0]));
   always @(posedge CLK_I)
     msg <= cmbmsg;
   
   wire [6:0]    cmbadr;
   wire          reloadadr;
   assign {reloadadr,cmbadr} = adr + 1;
   
   always @(posedge CLK_I) 
     if ( doshift & reloadadr ) 
       adr <= 'ha;
     else if ( doshift ) 
       adr <= cmbadr;

   /* 
    * The rest in mostly in the fast clock domain 
    */
   
   m_freeclock instclk (.clk(clk),.dummy(dummy)); 
   
   /* Increments to the phase accumulator:
    * The constant are calculated as (2^13)*desired_freq/clkfrq
    */
   localparam real   fTHECENTER  = 8192.0 * CENTER / CLKFRQ;
   localparam [12:0] aTHECENTER = fTHECENTER;
   localparam [12:0] THECENTER  = (aTHECENTER & 13'h1ffc) + 1;
   localparam [12:0] THEHIGH    = THECENTER+1; // THEHIGH[12:2] == {THECENTER[12:2],10}
   // THECENTER ends in 2'b01                                      {THECENTER[12:2],01}
   localparam [12:0] THELOW     = THECENTER-1; // THELOW[12:2]  == {THECENTER[12:2],00}

   /* msg determines if there should be sound or not.
    * cnt[8] modulates high/low and determines the pitch
    * addend[0] = ~msg
    * addend[1] = msg & cnt[8];
    * These two bits are carried through to the highspeed clock domain.
    * Strictly speaking we should double buffer to avoid metastability,
    * but I skip this. 
    * 
    * If onlyinc is set, the accumulator is only a counter, this is for
    * manual timing of the freerunning oscillator.
    */
   generate
      if ( TIMING ) begin
         always @(posedge clk) begin
            addend <= 13'h1;
         end
      end else begin
         always @(posedge clk) begin 
            addend[1:0]  <= {(msg & cnt[8]),~msg};
            addend[12:2] <= THECENTER[12:2];
         end
      end
   endgenerate
   m_phaseaccumulator i_acc(.msb(msb), .clk(clk), .addend(addend)); 

   
   /* Output on LEDs. 
    * led[3] message out   
    * led[2] not in use
    * led[0] Blinks when message is restarted.
    *        TIMING == 0   TIMING == 1
    * led[1] not in use    lights after around 14s. Stays on for about t=14s.
    *                      Time it! Clock frequency is 2^32/t
    */

   wire            calibrationaid;
   generate
      if ( TIMING ) begin
         reg [19:0] timingcnt;
         always @(posedge msb) // Get away from the high frequency clock
           timingcnt <= timingcnt + 1;
         assign calibrationaid = ~timingcnt[19];
      end else begin
         assign calibrationaid = 1'b0;
      end
   endgenerate
   
   SB_DFF r_buffermsb( .Q(buffermsb), .C(clk), .D(msb)); 

   assign antennae = buffermsb;   
   assign led[3]   = msg;
   assign led[2]   = 1'b0;
   assign led[1]   = calibrationaid;
   assign led[0]   = reloadadr;

   /* Estimate of LUTs used       Load on highspeed clock
    * ---------------------       -----------------------
    * Slow counter       16
    * Messagemux8to1      5         
    * Messagerom          8
    * Messageadr          8
    * Freeclock           3        1
    * Low bits addend     2        2
    * Phase accumulator  14       14
    * Buffer of msb phase 1        1
    * Constant_1          1       ==
    * =====================       18
    * Total              58
    * 
    * SynplifyPro does something strange, and through-luts are inserted 
    * to legalize carry-inputs. Unusable.
    * 
    * iCEcube LSE give 58 luts. 
    */
endmodule

/* "Hello world" in a ROM.
 */
module m_messagerom
  (
   output reg [7:0] d,
   input [3:0]      adr
   );
   always @(/*AS*/adr) begin
      case (adr) 
        4'h0 : d = 'b00000000; // ........ 
        4'h1 : d = 'b01010100; // hhhhhH.. 
        4'h2 : d = 'b00010001; // ___E___h 
        4'h3 : d = 'b01011101; // lllllllL 
        4'h4 : d = 'b11010001; // lllL___l 
        4'h5 : d = 'b00010101; // ___lllll 
        4'h6 : d = 'b01110111; // oooooooO 
        4'h7 : d = 'b00000111; // =====ooo 
        4'h8 : d = 'b01110100; // wwwwwW== 
        4'h9 : d = 'b11000111; // oO___www 
        4'ha : d = 'b11011101; // oooooooo 
        4'hb : d = 'b11010001; // rrrR___o 
        4'hc : d = 'b01000101; // lL___rrr 
        4'hd : d = 'b01010111; // _lllllll 
        4'he : d = 'b01011100; // dddddD__ 
        4'hf : d = 'b00000001; // =======d 
      endcase
   end
endmodule

/* The phase accumulator is a CLA variant. Each clock cycle the phase
 * accumulator holds a 13 bit number, but the exact representation 
 * depends on an intermediate carry bit. The real msb *could* be found 
 * after pipelining, but the error is negligible compared with other 
 * errors in this code.
 * 
 * Because ( (309000000+75000)/309000000 - 1)*2^13 ~= 1.5, we need 
 * at a 13 bit accumulator to represent sidebands in a correct way.
 */
module m_phaseaccumulator #
  ( parameter HIGHLEVEL = 0
    )
   (
    input        clk,
    input [12:0] addend,
    output       msb
    );
   
   generate
      if ( HIGHLEVEL ) begin
         // This gave 27 LUTs
         reg [12:0]   acc;
         reg          cy;
         always @(posedge clk) begin
            {cy,acc[4:0]} <= acc[4:0]  + addend[4:0];
            acc[12:5]     <= acc[12:5] + addend[12:5] + cy;
         end
         assign msb = acc[12];
      end else begin
         // This give 14 LUTs
         wire [5:0] cmblowacc,lowacc;
         wire [6:0] lowcy;
         wire       cmbcy,cy;
         assign lowcy[0] = 1'b0;
         SB_LUT4 #(.LUT_INIT(16'hc33c)) cmb_lowsix [5:0] ( .O(cmblowacc), .I3(lowcy[5:0]), .I2(lowacc), .I1(addend[5:0]), .I0(1'b0));
         SB_CARRY cmb_lowfivecarry [5:0]               ( .CO(lowcy[6:1]), .CI(lowcy[5:0]), .I1(lowacc), .I0(addend[5:0]));
         SB_DFF reg_lowsix [5:0] ( .Q(lowacc), .C(clk), .D(cmblowacc) );
         SB_LUT4 #(.LUT_INIT(16'hff00)) cylut( .O(cmbcy), .I3(lowcy[6]), .I2(1'b0), .I1(1'b0), .I0(1'b0));
         SB_DFF reg_cy ( .Q(cy), .C(clk), .D(cmbcy) );
         
         wire [6:0] highaddend = {addend[12:7],cy};
         wire [6:0] cmbhighacc,highacc;
         wire [6:0] highcy;
         assign highcy[0] = addend[6]; // Is a constant
         SB_LUT4 #(.LUT_INIT(16'hc33c)) cmb_high_seven [6:0] ( .O(cmbhighacc),  .I3(highcy),      .I2(highacc),      .I1(highaddend), .I0(1'b0));
         SB_CARRY cmb_high_six_carry [5:0] (                  .CO(highcy[6:1]), .CI(highcy[5:0]), .I1(highacc[5:0]), .I0(highaddend[5:0]));
         SB_DFF reg_high_seven [6:0] ( .Q(highacc), .C(clk), .D(cmbhighacc));
         assign msb = highacc[6];
      end
   endgenerate
endmodule



/* m_freeclock
 * -----------
 * A 3-element ring supplies the clock. I use the under-communicated 
 * LUT chain cascade here, see top.pcf
 * 
 * +--|>--|>--|>o-+-- clk
 * |              |
 * +--------------+
 * 
 * Notes to self: 
 * 8 taps: 229 MHz
 * 7 taps: 253 MHz
 * 6 taps: 274 MHz
 * 5 taps: 309 MHz
 * 4 taps: 358 MHz
 * 3 taps: 409 MHz
 *
 * Global clock networks are specified to work to up to 275 MHz.
 * Pulsewidth for the global buffer is specified at 0.88 ns, which
 * *could* imply that the highest clock that can pass the buffer
 * (but not drive the whole network) can be 1/(2*0.88 ns) = 568 MHz.
 */
module m_freeclock
  (
   input  dummy,
   output clk
   );
   wire      tap0;
   wire      tap1;
   
   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap0(.O(tap0),.I3(dummy),.I2(clk), .I1(1'b0),.I0(1'b0));
   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap1(.O(tap1),.I3(dummy),.I2(tap0),.I1(1'b0),.I0(1'b0));
   SB_LUT4 #(.LUT_INIT(16'h0f00)) cmb_tap2(.O(clk), .I3(dummy),.I2(tap1),.I1(1'b0),.I0(1'b0));
endmodule


/*                                    ________________
 *         ________________   d[2] --|I0 -|0\         |
 * d[0] ---|I0 -|0\        |         |    |  |---|1\  |
 *         |    |  |--|0\  |  d[3] --|I1 -|1/    |  |-|- o
 * d[1] ---|I1 -|1/   |  |-|--b -----|I2 --+-----|0/  |
 * a[0] ---|I2 --+----|1/  |         |            |   |
 * a[1] ---|I3 --------+---|---------|I3 ---------+   |
 *         |_______________|         |________________|
 */
module m_mux4to1
  (
   output      o,
   input [3:0] d,
   input [1:0] a
   );
   wire        b;
   SB_LUT4 #(.LUT_INIT(16'hf0ca)) cmbb( .O(b), .I3(a[1]), .I2(a[0]), .I1(d[1]), .I0(d[0]));
   SB_LUT4 #(.LUT_INIT(16'hcaf0)) cmbo( .O(o), .I3(a[1]), .I2(b),    .I1(d[3]), .I0(d[2]));
endmodule

module m_mux8to1
  (
   output      o,
   input [7:0] d,
   input [2:0] a
   );
   wire [1:0]  b;
   m_mux4to1 muxa( .o(b[0]), .d(d[3:0]), .a(a[1:0]));
   m_mux4to1 muxb( .o(b[1]), .d(d[7:4]), .a(a[1:0]));
   assign o = a[2] ? b[1] : b[0];
endmodule
