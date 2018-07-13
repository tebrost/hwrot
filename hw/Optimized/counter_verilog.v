/*
-- Author: John Zhu
-- Copyright (c) 2018 University of Maryland Baltimore County
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy 
-- of this software and associated documentation files (the "Software"), to deal 
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
-- copies of the Software, and to permit persons to whom the Software is furnished 
-- to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all 
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A 
-- PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
-- HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION 
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

module counter_verilog	#(
	parameter SIZE = 2
	)
	(
	count     ,  // Output of the counter
	en  ,  // enable for counter
	clk     ,  // clock Input
	rst      // reset Input
);
	//----------Output Ports--------------
	output [SIZE-1:0] count;
	//------------Input Ports--------------
	input en, clk, rst;
	//------------Internal Variables--------
	reg [SIZE-1:0] count;
	//-------------Code Starts Here-------
	always @(posedge clk)
		if (rst) begin
			count <= 0 ;
		end else if (en) begin
			count <= count + 1;
	end
endmodule 
