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

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mux_simon is 
	generic(
		BLOCK_SIZE : positive := 128;
		SIMON_BPC : positive := 32;
		STEP_SIZE : positive := 2
	);
	port(
		data0x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- H_block
		data1x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- PCR
		data2x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- Key
		data3x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- MSG
		sel_din  : in  std_logic;
		sel_CV   : in	std_logic_vector(1 downto 0);
		step : in unsigned(STEP_SIZE-1 downto 0);
		result_din	: out	unsigned(SIMON_BPC-1 downto 0);
		result_CVin	: out	unsigned(SIMON_BPC-1 downto 0)
	);

end mux_simon;


architecture arch1 of mux_simon is

	signal H_val : unsigned(BLOCK_SIZE-1 downto 0);
	signal PCR_val : unsigned(BLOCK_SIZE-1 downto 0);
	signal msg_val : unsigned(BLOCK_SIZE-1 downto 0);
	signal key_val : unsigned(BLOCK_SIZE-1 downto 0);

begin
	-- Does variable dataslicing by using a shift right unit and extracting the rightmost 32-bits
	-- It is done this way because Quartus 17
	H_val <= data0x srl to_integer(step)*SIMON_BPC;
	PCR_val <= data1x srl to_integer(step)*SIMON_BPC;
	msg_val <= data3x srl to_integer(step)*SIMON_BPC;
	key_val <= data2x srl to_integer(step)*SIMON_BPC;
	
	-- Multiplexer for secret key
	with sel_CV select
		result_CVin <= msg_val(SIMON_BPC-1 downto 0) when B"00",
					 H_val(SIMON_BPC-1 downto 0) when B"01",
					 key_val(SIMON_BPC-1 downto 0) when B"10",
					 (others => '1') when others;
	-- Multiplexer for plaintext input
	with sel_din select
		result_din <= H_val(SIMON_BPC-1 downto 0) when '0',
					 PCR_val(SIMON_BPC-1 downto 0) when '1',
					 (others => '1') when others;
		

end arch1;
