/* Morse "HELLO WORLD" on FM.
 * For iCEblink40hx1k development board.
 * 
 * See http://hamsterworks.co.nz/mediawiki/index.php/FM_SOS for original project.
 * This implementation inspired by https://github.com/r4d10n/iCEstick-hacks, 
 * that breaks timing constraints, and also requires a PLL.
 * 
 * Copyright B. Nossum. See LICENCE.txt for licence.
 * 
 * User guide:
 * -----------
 * 1. When synthesizing with Lattice ICECube2 - ensure "auto LUT cascade" is off. This is needed to realize 
 *    the freerunning clock. See placement file top.pcf.
 * 2. Check the frequency of your freerunning clock on your iceblink40hx1k board. Set parameter TIMING to 1.
 *    After programming the card, observe led2. After around 8 s it should light, and will stay on for
 *    around 8 s. Time this, and calculate the CLKFRQ. For my board, the led is high for 7.84 s, so
 *    apperantly CLKFRQ ~= 2^31/7.84 = 274 MHz. If your calculation is widely off this value, examine 
 *    placement of the instance of m_freeclock.
 * 3. Select the FM center frequency (CENTER) and what translates into volume (BAND). 
 * 4. Compile with ICECube2, upload to board, select board main frequency 3.33 MHz (JP2 open).
 * 4. Tune in your radio at approximately CENTER, and you should hear the message in morse.
 * 
 * Note to self: The following parameters give a short phase accumulator, the Lattice LSE syntethizer does
 * not allow real paramters (at least not in this example? Miswrites a float as integer in edf file).
 * ( parameter real CLKFRQ = 273000000.0,
 *   parameter real CENTER =  88511718.75,
 *   parameter real BAND   =     66650.4 )
 *
 */
module top #
  ( parameter
    TIMING = 0,
    CLKFRQ  = 274000000,
    CENTER  =  91000000,
    BAND    =     75000 
    )
   (
    input        dummy, // Is 1. I attach these to logic I want to keep. Actually CAP_BTN1
    input        CLK_I, // For slow work. Nominally 3.3 MHz
    output [3:0] led    // See at end of module.
    );
   wire          onlyinc = TIMING; // For timing of the freerunning clk
   wire          clk; //              Fast clock
   wire          msb; //              Msb of phase accumulator used as a 1-bit DAC.
   reg           buffermsb; //        Buffered msb of phase accumulator
   reg [18:0]    cnt;     //          Determines when to shift, and when to modulate.
   reg           doshift; //          Time to shift the message
   //reg [29:0]  message; // Holds "SMS"
   reg [118:0]   message; // Holds "HELLO WORLD"
   reg           running; //          Ease init of message
   reg [31:0]    addend; //           Input for the phase accumulator
   reg           meta_active, meta_highband, active, highband; // Cross clock domains.

   /* 
    * 3.3 MHZ clock domain 
    */
   always @(posedge CLK_I) begin
      cnt <= cnt + 1;
      doshift <= &cnt;
      
      if ( doshift ) begin
         if ( running == 0 ) begin
            //               S         M           S    
            //message <= 30'b10101_000_1110111_000_10101_0000000;
            //              H           E     L             L             O                   W             O               R           L             D      
            message <= 118'b1010101_000_1_000_101110101_000_101110101_000_11101110111_0000000_101110111_000_11101110111_000_1011101_000_101110101_000_1110101_0000000;
         end else begin            
            //message <= {message[28:0],message[29]};
            message <= {message[116:0],message[117]};
         end
         running <= dummy; // Must not "always be 1"
      end
   end


   /* 
    * The rest in fast clock domain 
    */
   
   m_freeclock instclk (.clk(clk),.dummy(dummy)); // Gives ~ 274 MHz for me
   
   /* message[0] determines if there should be sound or not.
    * cnt[12] modulates high/low and determines the pitch
    * These two bits are carried through to the highspeed clock domain.
    * If onlyinc is set, the accumulator is only a counter, this is for
    * manual timing of the freerunning oscillator.
    */
   always @(posedge clk) begin
      meta_active   <= message[0] & ~onlyinc;
      meta_highband <= cnt[12];
      active   <= meta_active;
      highband <= meta_highband;
   end
   
   /* Increments to the phase accumulator:
    * The constants are calculated as (desired freq)/clkfrq*2^32
    */
   localparam real fTHECENTER = 4294967296.0 * (CENTER     )/CLKFRQ; 
   localparam real fTHEHIGH   = 4294967296.0 * (CENTER+BAND)/CLKFRQ;
   localparam real fTHELOW    = 4294967296.0 * (CENTER-BAND)/CLKFRQ;
   localparam [31:0] THECENTER = fTHECENTER;
   localparam [31:0] THEHIGH   = fTHEHIGH;
   localparam [31:0] THELOW    = fTHELOW;
   
   always @(posedge clk)
     addend <= active ? (highband ? THEHIGH : THELOW) : (onlyinc ? 1 : THECENTER);
   
   m_phaseaccumulator i_acc(.msb(msb), .clk(clk), .addend(addend[31:0]));
   
   /* Output on LEDs. 
    * When onlyinc == 0
    * led[3] is the message out
    * led[2] is the antenna
    * led[1] not in use
    * led[0] not in use
    * 
    * When onlyinc == 1
    * led[3] not in use
    * led[2] lights after about t = 9s. Time it! Clock frequency is 2^31/t.
    * led[1] not in use
    * led[0] blinks fast to show that the board is indeed working.
    */
   
   always @(posedge clk)
     buffermsb <= msb;
   
   assign led[3] = active & ~onlyinc;
   assign led[2] = buffermsb;
   assign led[1] = 1'b0;
   assign led[0] = onlyinc & cnt[18];
endmodule


/* The phase accumulator is a CLA variant. Each clock cycle the phase
 * accumulator holds a 32 bit number, but the exact representation 
 * depends on a number of carry bits. The real msb *could* be found 
 * after pipelining, but the error is not large compared with other 
 * errors in this hack.
 */
module m_phaseaccumulator
  (
   input        clk,
   input [31:0] addend,
   output       msb
   );

   reg [31:0]   acc;
   reg [1:0]    cy;
   reg [1:0]    cybuf;
   always @(posedge clk) begin
      {cy[0],acc[10:0]}  <= acc[10:0]  + addend[10:0];
      cybuf[0] <= cy[0];
      {cy[1],acc[21:11]} <= acc[21:11] + addend[21:11] + cybuf[0];
      cybuf[1] <= cy[1];
      acc[31:22]         <= acc[31:22] + addend[31:22] + cybuf[1];
   end
   assign msb = acc[31];   
endmodule

/*
 * A 6-element ring supplies the clock. I use the under-communicated 
 * LUT chain cascade here.
 * 
 * +--|>--|>--|>--|>--|>--|>o-+-- fastclk
 * |                          |
 * +--------------------------+
 * 
 * 8 taps: 75 s to count to 2^34 : 229 MHz
 * 7 taps: 68 s to count to 2^34 : 253 MHz
 * 6 taps: 63 s to count to 2^34 : 274 MHz
 * 5 taps: 57 s to count to 2^34 : 301 MHz
 * 4 taps: 48 s to count to 2^34 : 358 MHz
 * 3 taps: 42 s to count to 2^34 : 409 MHz
 * 2 taps: No result.
 *
 * Note to self: 
 * Global clock netwirks are specified to work to up to 275 MHz.
 * Pulsewidth for the global buffer is specified at 0.88 ns, which
 * should imply that the highest clock that can pass the buffer
 * (but not drive the whole network) should be 1/(2*0.88 ns) = 568 MHz.
 * I will be nice, and uses 6 taps. On my board this give a 274 MHz clock,
 * but this will vary according to temperature, voltage, and die.
 * 
 */
module m_freeclock
  (
   input  dummy,
   output clk
   );
   wire      tap0;
   wire      tap1;
   wire      tap2;
   wire      tap3;
   wire      tap4;
//   wire      tap5;
//   wire      tap6;
   wire      fastclk;
   
   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap0( .O(tap0),    .I3(dummy), .I2(fastclk), .I1(1'b0), .I0(1'b0));
   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap1( .O(tap1),    .I3(dummy), .I2(tap0),    .I1(1'b0), .I0(1'b0));
   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap2( .O(tap2),    .I3(dummy), .I2(tap1),    .I1(1'b0), .I0(1'b0));
   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap3( .O(tap3),    .I3(dummy), .I2(tap2),    .I1(1'b0), .I0(1'b0));
   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap4( .O(tap4),    .I3(dummy), .I2(tap3),    .I1(1'b0), .I0(1'b0));
   SB_LUT4 #(.LUT_INIT(16'h0f00)) cmb_tap5( .O(fastclk), .I3(dummy), .I2(tap4),    .I1(1'b0), .I0(1'b0));
   
//   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap5( .O(tap5),    .I3(dummy), .I2(tap4),    .I1(1'b0), .I0(1'b0));
//   SB_LUT4 #(.LUT_INIT(16'h0f00)) cmb_tap6( .O(fastclk), .I3(dummy), .I2(tap5),    .I1(1'b0), .I0(1'b0));   
//   SB_LUT4 #(.LUT_INIT(16'hf000)) cmb_tap6( .O(tap6),    .I3(dummy), .I2(tap5),    .I1(1'b0), .I0(1'b0));
//   SB_LUT4 #(.LUT_INIT(16'h0f00)) cmb_tap7( .O(fastclk), .I3(dummy), .I2(tap6),    .I1(1'b0), .I0(1'b0));
   SB_GB gbbuf( .USER_SIGNAL_TO_GLOBAL_BUFFER(fastclk), .GLOBAL_BUFFER_OUTPUT(clk));
endmodule
